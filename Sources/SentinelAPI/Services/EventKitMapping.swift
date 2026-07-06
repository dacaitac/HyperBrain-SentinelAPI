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
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: dueDate)
        } else {
            reminder.dueDateComponents = nil
        }
        applyRecurrence(payload.recurrence, to: reminder)
        reminder.alarms = buildAlarms(payload.alarms)
    }

    func apply(_ payload: CalendarEventPayload, to event: EKEvent) {
        event.title = payload.title
        event.startDate = payload.startTime
        event.endDate = payload.endTime ?? payload.startTime
        event.isAllDay = payload.allDay
        event.notes = payload.notes
        event.location = payload.location
        event.url = payload.url.flatMap(URL.init(string:))
        applyRecurrence(payload.recurrence, to: event)
        event.alarms = buildAlarms(payload.alarms)
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
