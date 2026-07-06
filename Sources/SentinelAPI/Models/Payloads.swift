import Foundation

/// A geofence attached to an alarm or event (`EKStructuredLocation`).
/// Not a top-level entity — always nested inside a reminder/event payload.
struct LocationPayload: Codable, Sendable, Equatable {
    let title: String
    let latitude: Double
    let longitude: Double
    let radius: Double
}

/// A reminder/event alarm (`EKAlarm`): absolute date, relative offset (seconds),
/// or a location-based (proximity) trigger. Nested, never a top-level entity.
struct AlarmPayload: Codable, Sendable, Equatable {
    enum Proximity: String, Codable, Sendable {
        case none
        case enter
        case leave
    }

    let absoluteDate: Date?
    /// Offset in seconds relative to the entity's date (`EKAlarm.relativeOffset`).
    let relativeOffset: Int?
    let proximity: Proximity
    let location: LocationPayload?
}

/// `REMINDER` payload — mirror of `EKReminder` plus its list, alarms and location.
struct ReminderPayload: Codable, Sendable, Equatable {
    let title: String
    let notes: String?
    let dueDate: Date?
    let completed: Bool
    let priority: Int
    let url: String?
    let recurrence: String?
    let listId: String
    let listName: String
    let location: LocationPayload?
    let alarms: [AlarmPayload]
}

/// `CALENDAR_EVENT` payload — mirror of `EKEvent` plus its calendar, alarms and location.
struct CalendarEventPayload: Codable, Sendable, Equatable {
    let title: String
    let startTime: Date
    let endTime: Date?
    let allDay: Bool
    let notes: String?
    let url: String?
    let recurrence: String?
    let calendarId: String
    let calendarName: String
    let location: String?
    let alarms: [AlarmPayload]
}

/// `REMINDER_LIST` and `CALENDAR` payload — both map to `EKCalendar`.
struct CalendarPayload: Codable, Sendable, Equatable {
    let title: String
    let sourceName: String
    let color: String?
    let isDefault: Bool
}
