import EventKit
import Foundation
@testable import SentinelAPI

/// In-memory EventKit substitute for route tests. No EKEventStore — no TCC permission required.
/// Throws `EventKitService.EventKitError` to exercise the same HTTP error mapping as production.
actor MockEventKitService: EventKitOperations {

    private var reminders: [String: ReminderPayload] = [:]
    private var events: [String: CalendarEventPayload] = [:]
    private var reminderLists: [String: CalendarPayload] = [:]
    private var eventCalendars: [String: CalendarPayload] = [:]

    func requestAccess() async throws {}

    func changeStream() async -> AsyncStream<Void> {
        AsyncStream { continuation in continuation.finish() }
    }

    func buildSnapshot() async -> [EntityRecord] {
        reminders.map { EntityRecord(entityId: $0.key, entityType: .reminder, payload: .reminder($0.value)) }
        + events.map { EntityRecord(entityId: $0.key, entityType: .calendarEvent, payload: .calendarEvent($0.value)) }
        + reminderLists.map { EntityRecord(entityId: $0.key, entityType: .reminderList, payload: .calendar($0.value)) }
        + eventCalendars.map { EntityRecord(entityId: $0.key, entityType: .calendar, payload: .calendar($0.value)) }
    }

    func fetchReminders() async -> [EntityRecord] {
        reminders.map { EntityRecord(entityId: $0.key, entityType: .reminder, payload: .reminder($0.value)) }
    }

    func fetchEvents() async -> [EntityRecord] {
        events.map { EntityRecord(entityId: $0.key, entityType: .calendarEvent, payload: .calendarEvent($0.value)) }
    }

    func fetchCalendars(for entityType: EKEntityType) async -> [EntityRecord] {
        if entityType == .reminder {
            return reminderLists.map { EntityRecord(entityId: $0.key, entityType: .reminderList, payload: .calendar($0.value)) }
        }
        return eventCalendars.map { EntityRecord(entityId: $0.key, entityType: .calendar, payload: .calendar($0.value)) }
    }

    func createReminder(_ payload: ReminderPayload) throws -> String {
        let id = UUID().uuidString
        reminders[id] = payload
        return id
    }

    func updateReminder(id: String, _ payload: ReminderPayload) throws {
        guard reminders[id] != nil else { throw EventKitService.EventKitError.notFound(id: id) }
        reminders[id] = payload
    }

    func deleteReminder(id: String) throws {
        guard reminders.removeValue(forKey: id) != nil else { throw EventKitService.EventKitError.notFound(id: id) }
    }

    func createEvent(_ payload: CalendarEventPayload) throws -> String {
        let id = UUID().uuidString
        events[id] = payload
        return id
    }

    func updateEvent(id: String, _ payload: CalendarEventPayload) throws {
        guard events[id] != nil else { throw EventKitService.EventKitError.notFound(id: id) }
        events[id] = payload
    }

    func deleteEvent(id: String) throws {
        guard events.removeValue(forKey: id) != nil else { throw EventKitService.EventKitError.notFound(id: id) }
    }

    func createCalendar(_ payload: CalendarPayload, entityType: EKEntityType) throws -> String {
        let id = UUID().uuidString
        if entityType == .reminder {
            reminderLists[id] = payload
        } else {
            eventCalendars[id] = payload
        }
        return id
    }

    func updateCalendar(id: String, _ payload: CalendarPayload) throws {
        if reminderLists[id] != nil {
            reminderLists[id] = payload
        } else if eventCalendars[id] != nil {
            eventCalendars[id] = payload
        } else {
            throw EventKitService.EventKitError.notFound(id: id)
        }
    }

    func deleteCalendar(id: String) throws {
        if reminderLists.removeValue(forKey: id) == nil,
           eventCalendars.removeValue(forKey: id) == nil {
            throw EventKitService.EventKitError.notFound(id: id)
        }
    }

    func apply(command: WriteCommand) throws -> String {
        switch (command.commandType, command.operation, command.payload) {
        case (.reminder, .created, .reminder(let p)): return try createReminder(p)
        case (.reminder, .updated, .reminder(let p)):
            let id = command.entityId ?? UUID().uuidString
            try updateReminder(id: id, p); return id
        case (.reminder, .deleted, _):
            let id = command.entityId ?? ""; try deleteReminder(id: id); return id
        case (.calendarEvent, .created, .calendarEvent(let p)): return try createEvent(p)
        case (.calendarEvent, .updated, .calendarEvent(let p)):
            let id = command.entityId ?? UUID().uuidString
            try updateEvent(id: id, p); return id
        case (.calendarEvent, .deleted, _):
            let id = command.entityId ?? ""; try deleteEvent(id: id); return id
        default: throw EventKitService.EventKitError.wrongType(id: command.commandId.uuidString)
        }
    }
}
