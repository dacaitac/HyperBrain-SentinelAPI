import Foundation

/// Write command consumed from `apple-commands.fifo` (Core → Apple).
///
/// The Core orders SentinelAPI to create/update/delete a reminder or calendar event via EventKit.
/// Symmetric to `AppleEntityChangedEvent`: `command_type` discriminates the nested `payload`.
/// `command_type == REMINDER` is the logical `WriteReminderCommand`; `CALENDAR_EVENT` the
/// `WriteCalendarEventCommand`. Writes applied by the consumer must NOT be re-emitted to
/// `sync-events.fifo` (local loop protection).
struct WriteCommand: Codable, Sendable {
    /// Only `REMINDER` and `CALENDAR_EVENT` are writable from the Core.
    enum CommandType: String, Codable, Sendable {
        case reminder = "REMINDER"
        case calendarEvent = "CALENDAR_EVENT"
    }

    enum Payload: Sendable, Equatable {
        case reminder(ReminderPayload)
        case calendarEvent(CalendarEventPayload)
    }

    let commandId: UUID
    let commandType: CommandType
    let operation: Operation
    /// Required for `UPDATED` / `DELETED`; nil for `CREATED`.
    let entityId: String?
    /// Nil for `DELETED`.
    let payload: Payload?

    private enum CodingKeys: String, CodingKey {
        case commandId, commandType, operation, entityId, payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        commandId = try container.decode(UUID.self, forKey: .commandId)
        commandType = try container.decode(CommandType.self, forKey: .commandType)
        operation = try container.decode(Operation.self, forKey: .operation)
        entityId = try container.decodeIfPresent(String.self, forKey: .entityId)

        if operation == .deleted || !container.contains(.payload) {
            payload = nil
        } else {
            switch commandType {
            case .reminder:
                payload = .reminder(try container.decode(ReminderPayload.self, forKey: .payload))
            case .calendarEvent:
                payload = .calendarEvent(try container.decode(CalendarEventPayload.self, forKey: .payload))
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(commandId, forKey: .commandId)
        try container.encode(commandType, forKey: .commandType)
        try container.encode(operation, forKey: .operation)
        try container.encodeIfPresent(entityId, forKey: .entityId)
        switch payload {
        case .reminder(let value): try container.encode(value, forKey: .payload)
        case .calendarEvent(let value): try container.encode(value, forKey: .payload)
        case .none: break
        }
    }
}
