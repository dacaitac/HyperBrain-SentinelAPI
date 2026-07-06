import EventKit
import Foundation

/// Wraps a NotificationCenter observer token so it can cross into the `@Sendable` termination
/// handler. The token is only ever read to unregister; access is otherwise inert.
private struct ObserverBox: @unchecked Sendable {
    let observer: NSObjectProtocol
    init(_ observer: NSObjectProtocol) { self.observer = observer }
}

/// Identified pair of an entity id and its wire payload (used by the REST layer and snapshots).
struct EntityRecord: Sendable {
    let entityId: String
    let entityType: EntityType
    let payload: EntityPayload
}

/// Unified EventKit layer over a single `EKEventStore`. Merges the two legacy daemons:
/// CRUD (`reminder-api`) and change detection (`sentinel-daemon`). Serialized as an `actor`
/// because `EKEventStore` is not `Sendable`.
actor EventKitService {
    private let store = EKEventStore()

    enum EventKitError: Error, CustomStringConvertible {
        case accessDenied
        case notFound(id: String)
        case wrongType(id: String)
        case invalidCalendar(id: String)
        case noDefaultCalendar

        var description: String {
            switch self {
            case .accessDenied: return "EventKit full access was denied"
            case .notFound(let id): return "No EventKit item with identifier '\(id)'"
            case .wrongType(let id): return "Item '\(id)' is not of the expected type"
            case .invalidCalendar(let id): return "No calendar with identifier '\(id)'"
            case .noDefaultCalendar: return "No default calendar available"
            }
        }
    }

    // MARK: - Access

    /// Requests full access to both Reminders and Calendar. Both are required.
    func requestAccess() async throws {
        let reminders = try await store.requestFullAccessToReminders()
        let events = try await store.requestFullAccessToEvents()
        guard reminders && events else { throw EventKitError.accessDenied }
    }

    /// Emits a tick every time the underlying EventKit store changes (`.EKEventStoreChanged`).
    func changeStream() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let box = ObserverBox(NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged, object: store, queue: nil
            ) { _ in
                continuation.yield(())
            })
            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(box.observer)
            }
        }
    }

    // MARK: - Snapshot

    /// Full snapshot of every reminder, event, reminder list and calendar as wire records.
    func buildSnapshot() async -> [EntityRecord] {
        var records: [EntityRecord] = []

        records.append(contentsOf: await fetchReminderRecords())
        for event in fetchAllEvents() {
            records.append(EntityRecord(
                entityId: event.eventIdentifier ?? event.calendarItemIdentifier,
                entityType: .calendarEvent,
                payload: .calendarEvent(Self.map(event))
            ))
        }
        for list in store.calendars(for: .reminder) {
            records.append(EntityRecord(
                entityId: list.calendarIdentifier,
                entityType: .reminderList,
                payload: .calendar(map(list))
            ))
        }
        for calendar in store.calendars(for: .event) {
            records.append(EntityRecord(
                entityId: calendar.calendarIdentifier,
                entityType: .calendar,
                payload: .calendar(map(calendar))
            ))
        }
        return records
    }

    // MARK: - Reminder CRUD

    @discardableResult
    func createReminder(_ payload: ReminderPayload) throws -> String {
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = try reminderCalendar(id: payload.listId)
        apply(payload, to: reminder)
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    func updateReminder(id: String, _ payload: ReminderPayload) throws {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw EventKitError.notFound(id: id)
        }
        apply(payload, to: reminder)
        try store.save(reminder, commit: true)
    }

    func deleteReminder(id: String) throws {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw EventKitError.notFound(id: id)
        }
        try store.remove(reminder, commit: true)
    }

    func fetchReminders() async -> [EntityRecord] {
        await fetchReminderRecords()
    }

    // MARK: - Event CRUD

    @discardableResult
    func createEvent(_ payload: CalendarEventPayload) throws -> String {
        let event = EKEvent(eventStore: store)
        event.calendar = try eventCalendar(id: payload.calendarId)
        apply(payload, to: event)
        try store.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier ?? event.calendarItemIdentifier
    }

    func updateEvent(id: String, _ payload: CalendarEventPayload) throws {
        guard let event = store.event(withIdentifier: id) ?? (store.calendarItem(withIdentifier: id) as? EKEvent) else {
            throw EventKitError.notFound(id: id)
        }
        apply(payload, to: event)
        try store.save(event, span: .thisEvent, commit: true)
    }

    func deleteEvent(id: String) throws {
        guard let event = store.event(withIdentifier: id) ?? (store.calendarItem(withIdentifier: id) as? EKEvent) else {
            throw EventKitError.notFound(id: id)
        }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    func fetchEvents() -> [EntityRecord] {
        fetchAllEvents().map {
            EntityRecord(entityId: $0.eventIdentifier ?? $0.calendarItemIdentifier, entityType: .calendarEvent, payload: .calendarEvent(Self.map($0)))
        }
    }

    // MARK: - Calendar / list CRUD

    @discardableResult
    func createCalendar(_ payload: CalendarPayload, entityType: EKEntityType) throws -> String {
        let calendar = EKCalendar(for: entityType, eventStore: store)
        calendar.title = payload.title
        calendar.source = source(named: payload.sourceName) ?? store.defaultCalendarForNewReminders()?.source
        try store.saveCalendar(calendar, commit: true)
        return calendar.calendarIdentifier
    }

    func updateCalendar(id: String, _ payload: CalendarPayload) throws {
        guard let calendar = store.calendar(withIdentifier: id) else { throw EventKitError.invalidCalendar(id: id) }
        calendar.title = payload.title
        try store.saveCalendar(calendar, commit: true)
    }

    func deleteCalendar(id: String) throws {
        guard let calendar = store.calendar(withIdentifier: id) else { throw EventKitError.invalidCalendar(id: id) }
        try store.removeCalendar(calendar, commit: true)
    }

    func fetchCalendars(for entityType: EKEntityType) -> [EntityRecord] {
        let type: EntityType = entityType == .reminder ? .reminderList : .calendar
        return store.calendars(for: entityType).map {
            EntityRecord(entityId: $0.calendarIdentifier, entityType: type, payload: .calendar(map($0)))
        }
    }

    // MARK: - Command application (Core → Apple)

    /// Applies a write command from `apple-commands.fifo`. Returns the affected entity id.
    @discardableResult
    func apply(command: WriteCommand) throws -> String {
        switch (command.commandType, command.operation, command.payload) {
        case (.reminder, .created, .reminder(let payload)):
            return try createReminder(payload)
        case (.reminder, .updated, .reminder(let payload)):
            let id = try requireEntityId(command)
            try updateReminder(id: id, payload)
            return id
        case (.reminder, .deleted, _):
            let id = try requireEntityId(command)
            try deleteReminder(id: id)
            return id
        case (.calendarEvent, .created, .calendarEvent(let payload)):
            return try createEvent(payload)
        case (.calendarEvent, .updated, .calendarEvent(let payload)):
            let id = try requireEntityId(command)
            try updateEvent(id: id, payload)
            return id
        case (.calendarEvent, .deleted, _):
            let id = try requireEntityId(command)
            try deleteEvent(id: id)
            return id
        default:
            throw EventKitError.wrongType(id: command.entityId ?? command.commandId.uuidString)
        }
    }

    private func requireEntityId(_ command: WriteCommand) throws -> String {
        guard let id = command.entityId else { throw EventKitError.notFound(id: command.commandId.uuidString) }
        return id
    }

    // MARK: - Fetch helpers

    /// Maps reminders to Sendable records *inside* the EventKit completion so no `EKReminder`
    /// crosses the concurrency boundary.
    private func fetchReminderRecords() async -> [EntityRecord] {
        let predicate = store.predicateForReminders(in: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let records = (reminders ?? []).map {
                    EntityRecord(
                        entityId: $0.calendarItemIdentifier,
                        entityType: .reminder,
                        payload: .reminder(Self.map($0))
                    )
                }
                continuation.resume(returning: records)
            }
        }
    }

    private func fetchAllEvents() -> [EKEvent] {
        let calendars = store.calendars(for: .event)
        guard !calendars.isEmpty else { return [] }
        let now = Date()
        // Apple recommends keeping the window under 4 years. 2 years back / 2 years forward
        // covers the full productive horizon for a personal productivity system.
        let start = Calendar.current.date(byAdding: .year, value: -2, to: now) ?? now
        let end = Calendar.current.date(byAdding: .year, value: 2, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
    }

    private func reminderCalendar(id: String) throws -> EKCalendar {
        if let calendar = store.calendar(withIdentifier: id) { return calendar }
        guard let fallback = store.defaultCalendarForNewReminders() else { throw EventKitError.noDefaultCalendar }
        return fallback
    }

    private func eventCalendar(id: String) throws -> EKCalendar {
        if let calendar = store.calendar(withIdentifier: id) { return calendar }
        guard let fallback = store.defaultCalendarForNewEvents else { throw EventKitError.noDefaultCalendar }
        return fallback
    }

    private func source(named name: String) -> EKSource? {
        store.sources.first { $0.title == name }
    }

    func defaultReminderCalendarIdentifier() -> String? {
        store.defaultCalendarForNewReminders()?.calendarIdentifier
    }

    func defaultEventCalendarIdentifier() -> String? {
        store.defaultCalendarForNewEvents?.calendarIdentifier
    }
}
