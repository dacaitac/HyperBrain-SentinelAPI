import Foundation

enum SourceSystem: String, Codable, Sendable {
    case apple = "APPLE"
}

enum EntityType: String, Codable, Sendable {
    case reminder = "REMINDER"
    case calendarEvent = "CALENDAR_EVENT"
    case reminderList = "REMINDER_LIST"
    case calendar = "CALENDAR"
}

enum Operation: String, Codable, Sendable {
    case created = "CREATED"
    case updated = "UPDATED"
    case deleted = "DELETED"
}

/// Concrete payload carried by `AppleEntityChangedEvent`, discriminated by `entity_type`.
/// `REMINDER_LIST` and `CALENDAR` share the `EKCalendar` shape (`CalendarPayload`).
enum EntityPayload: Sendable, Equatable {
    case reminder(ReminderPayload)
    case calendarEvent(CalendarEventPayload)
    case calendar(CalendarPayload)
}

/// Envelope published to `sync-events.fifo` when an EventKit entity changes (Apple → Core).
///
/// Wire contract: HU-09 #14 / `eventsentinel.md`. Keys are `snake_case` (see `JSONCoding`).
/// `source_system` is always `APPLE` to drive the Core's Loop Protection (RF-17) — never change it.
struct AppleEntityChangedEvent: Codable, Sendable {
    let schemaVersion: String
    let eventId: UUID
    let sourceSystem: SourceSystem
    let entityType: EntityType
    let entityId: String
    let operation: Operation
    let occurredAt: Date
    let payload: EntityPayload?

    static let currentSchemaVersion = "1"

    init(
        eventId: UUID = UUID(),
        entityType: EntityType,
        entityId: String,
        operation: Operation,
        occurredAt: Date = Date(),
        payload: EntityPayload?
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.eventId = eventId
        self.sourceSystem = .apple
        self.entityType = entityType
        self.entityId = entityId
        self.operation = operation
        self.occurredAt = occurredAt
        self.payload = payload
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, eventId, sourceSystem, entityType, entityId, operation, occurredAt, payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        eventId = try container.decode(UUID.self, forKey: .eventId)
        sourceSystem = try container.decode(SourceSystem.self, forKey: .sourceSystem)
        entityType = try container.decode(EntityType.self, forKey: .entityType)
        entityId = try container.decode(String.self, forKey: .entityId)
        operation = try container.decode(Operation.self, forKey: .operation)
        occurredAt = try container.decode(Date.self, forKey: .occurredAt)

        if operation == .deleted || !container.contains(.payload) {
            payload = nil
        } else {
            switch entityType {
            case .reminder:
                payload = .reminder(try container.decode(ReminderPayload.self, forKey: .payload))
            case .calendarEvent:
                payload = .calendarEvent(try container.decode(CalendarEventPayload.self, forKey: .payload))
            case .reminderList, .calendar:
                payload = .calendar(try container.decode(CalendarPayload.self, forKey: .payload))
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(eventId, forKey: .eventId)
        try container.encode(sourceSystem, forKey: .sourceSystem)
        try container.encode(entityType, forKey: .entityType)
        try container.encode(entityId, forKey: .entityId)
        try container.encode(operation, forKey: .operation)
        try container.encode(occurredAt, forKey: .occurredAt)
        switch payload {
        case .reminder(let value): try container.encode(value, forKey: .payload)
        case .calendarEvent(let value): try container.encode(value, forKey: .payload)
        case .calendar(let value): try container.encode(value, forKey: .payload)
        case .none: break
        }
    }
}
