import CoreGraphics
import CoreLocation
import EventKit
import Foundation

/// Pure-ish mapping between EventKit objects and the wire payloads. All members are called
/// on the `EventKitService` actor, so passing non-`Sendable` EventKit objects is race-free.
extension EventKitService {

    // MARK: - EventKit -> payload

    static func map(_ reminder: EKReminder) -> ReminderPayload {
        ReminderPayload(
            title: reminder.title ?? "",
            notes: reminder.notes,
            dueDate: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
            completed: reminder.isCompleted,
            priority: reminder.priority,
            url: reminder.url?.absoluteString,
            recurrence: recurrenceString(reminder.recurrenceRules?.first),
            listId: reminder.calendar?.calendarIdentifier ?? "",
            listName: reminder.calendar?.title ?? "",
            location: map(reminder.alarms?.compactMap { $0.structuredLocation }.first),
            alarms: mapAlarms(reminder.alarms)
        )
    }

    static func map(_ event: EKEvent) -> CalendarEventPayload {
        CalendarEventPayload(
            title: event.title ?? "",
            startTime: event.startDate,
            endTime: event.endDate,
            allDay: event.isAllDay,
            notes: event.notes,
            url: event.url?.absoluteString,
            recurrence: recurrenceString(event.recurrenceRules?.first),
            calendarId: event.calendar?.calendarIdentifier ?? "",
            calendarName: event.calendar?.title ?? "",
            location: event.location,
            alarms: mapAlarms(event.alarms)
        )
    }

    func map(_ calendar: EKCalendar) -> CalendarPayload {
        let isDefault = calendar.calendarIdentifier == defaultReminderCalendarIdentifier()
            || calendar.calendarIdentifier == defaultEventCalendarIdentifier()
        return CalendarPayload(
            title: calendar.title,
            sourceName: calendar.source?.title ?? "",
            color: Self.hexString(from: calendar.cgColor),
            isDefault: isDefault
        )
    }

    static func mapAlarms(_ alarms: [EKAlarm]?) -> [AlarmPayload] {
        (alarms ?? []).map { alarm in
            AlarmPayload(
                absoluteDate: alarm.absoluteDate,
                relativeOffset: alarm.absoluteDate == nil ? Int(alarm.relativeOffset) : nil,
                proximity: map(alarm.proximity),
                location: map(alarm.structuredLocation)
            )
        }
    }

    static func map(_ location: EKStructuredLocation?) -> LocationPayload? {
        guard let location, let coordinate = location.geoLocation?.coordinate else { return nil }
        return LocationPayload(
            title: location.title ?? "",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            radius: location.radius
        )
    }

    static func map(_ proximity: EKAlarmProximity) -> AlarmPayload.Proximity {
        switch proximity {
        case .enter: return .enter
        case .leave: return .leave
        default: return .none
        }
    }

    // MARK: - payload -> EventKit

    func apply(_ payload: ReminderPayload, to reminder: EKReminder) {
        reminder.title = payload.title
        reminder.notes = payload.notes
        reminder.isCompleted = payload.completed
        reminder.priority = payload.priority
        reminder.url = payload.url.flatMap(URL.init(string:))
        if let dueDate = payload.dueDate {
            // All-day (date-only) is derived from the absence of a time-of-day: a due at local
            // midnight carries only [year, month, day] so the reminder does not alert at 00:00.
            let fields: Set<Calendar.Component> = Self.isDateOnly(dueDate)
                ? [.year, .month, .day]
                : [.year, .month, .day, .hour, .minute]
            reminder.dueDateComponents = Calendar.current.dateComponents(fields, from: dueDate)
        } else {
            reminder.dueDateComponents = nil
        }
        applyRecurrence(payload.recurrence, to: reminder)
        // EventKit never derives an alarm from the due date, so without one a reminder is silent.
        // Attach a default alarm so it notifies (and plays the system sound): at the due time when
        // timed, or at the default hour of the day for date-only reminders (never at midnight).
        reminder.alarms = defaultAlarms(explicit: payload.alarms, dueDate: payload.dueDate)
    }

    func apply(_ payload: CalendarEventPayload, to event: EKEvent) {
        event.title = payload.title
        event.startDate = payload.startTime
        event.endDate = payload.endTime ?? payload.startTime
        // All-day is derived from the times when the Core does not set it explicitly: start (and
        // end, if any) on local midnight means a date-only event with no meaningful time-of-day.
        event.isAllDay = payload.allDay
            || (Self.isDateOnly(payload.startTime)
                && (payload.endTime.map(Self.isDateOnly) ?? true))
        event.notes = payload.notes
        event.location = payload.location
        event.url = payload.url.flatMap(URL.init(string:))
        applyRecurrence(payload.recurrence, to: event)
        // As with reminders, an event needs an explicit alarm to notify. Attach a default one at the
        // start time, or at the default hour for all-day events (rather than midnight).
        event.alarms = defaultAlarms(explicit: payload.alarms, dueDate: payload.startTime, allDay: event.isAllDay)
    }

    /// Whether a date falls exactly on local midnight — the signal for an all-day / date-only
    /// item, since the Core anchors date-only values (no time-of-day) to midnight.
    static func isDateOnly(_ date: Date) -> Bool {
        let time = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return time.hour == 0 && time.minute == 0 && time.second == 0
    }

    /// Default notification hour (seconds past local midnight) for date-only / all-day items, so they
    /// alert at a sensible time instead of 00:00. Matches Apple's own all-day default (09:00).
    private static let defaultAllDayAlarmOffset: TimeInterval = 9 * 3600

    /// Resolves the alarms to write. Explicit payload alarms win; otherwise a single default alarm is
    /// synthesized so the item notifies (and plays the system sound): at the due/start time when it
    /// carries a time-of-day, or at ``defaultAllDayAlarmOffset`` for date-only / all-day items. An
    /// item without any date gets no alarm.
    ///
    /// - Parameters:
    ///   - explicit: alarms carried in the payload (currently the Core sends none).
    ///   - dueDate:  the reminder due date or event start; nil means no date and thus no alarm.
    ///   - allDay:   forces the all-day branch (used for events whose all-day flag is set explicitly).
    private func defaultAlarms(explicit: [AlarmPayload], dueDate: Date?, allDay: Bool = false) -> [EKAlarm] {
        guard explicit.isEmpty else { return buildAlarms(explicit) }
        guard let dueDate else { return [] }
        let isAllDay = allDay || Self.isDateOnly(dueDate)
        let offset = isAllDay ? Self.defaultAllDayAlarmOffset : 0
        return [EKAlarm(relativeOffset: offset)]
    }

    private func buildAlarms(_ payloads: [AlarmPayload]) -> [EKAlarm] {
        payloads.map { payload in
            let alarm: EKAlarm
            if let absolute = payload.absoluteDate {
                alarm = EKAlarm(absoluteDate: absolute)
            } else {
                alarm = EKAlarm(relativeOffset: TimeInterval(payload.relativeOffset ?? 0))
            }
            if let location = payload.location {
                let structured = EKStructuredLocation(title: location.title)
                structured.geoLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
                structured.radius = location.radius
                alarm.structuredLocation = structured
                alarm.proximity = Self.proximity(from: payload.proximity)
            }
            return alarm
        }
    }

    private func applyRecurrence(_ recurrence: String?, to item: EKCalendarItem) {
        guard let frequency = Self.frequency(from: recurrence) else {
            item.recurrenceRules = nil
            return
        }
        item.recurrenceRules = [EKRecurrenceRule(recurrenceWith: frequency, interval: 1, end: nil)]
    }

    // MARK: - Small helpers

    private static func hexString(from cgColor: CGColor?) -> String? {
        guard let components = cgColor?.components, components.count >= 3 else { return nil }
        let r = Int((components[0] * 255).rounded())
        let g = Int((components[1] * 255).rounded())
        let b = Int((components[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private static func recurrenceString(_ rule: EKRecurrenceRule?) -> String? {
        guard let rule else { return nil }
        switch rule.frequency {
        case .daily: return "daily"
        case .weekly: return "weekly"
        case .monthly: return "monthly"
        case .yearly: return "yearly"
        @unknown default: return nil
        }
    }

    private static func frequency(from recurrence: String?) -> EKRecurrenceFrequency? {
        switch recurrence?.lowercased() {
        case "daily": return .daily
        case "weekly": return .weekly
        case "monthly": return .monthly
        case "yearly": return .yearly
        default: return nil
        }
    }

    private static func proximity(from proximity: AlarmPayload.Proximity) -> EKAlarmProximity {
        switch proximity {
        case .enter: return .enter
        case .leave: return .leave
        case .none: return .none
        }
    }
}
