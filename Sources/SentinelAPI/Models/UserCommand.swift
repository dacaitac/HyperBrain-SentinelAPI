import Foundation

/// User-triggered command published to `user-commands.fifo` (iOS Shortcut → SentinelAPI → Core).
///
/// HU-01b slice 2: the "replan" button and the sleep-score input. Wire contract (fixed, the Core
/// consumes exactly this): `snake_case` keys via `JSONCoding`, `origin` always `USER`, `payload`
/// present only for `SLEEP_SCORE` and explicit `null` otherwise.
/// FIFO parameters: `MessageGroupId = "user-commands"`, `MessageDeduplicationId = command_id`.
struct UserCommand: Codable, Sendable, Equatable {
    enum CommandType: String, Codable, Sendable {
        case replanAgenda = "REPLAN_AGENDA"
        case sleepScore = "SLEEP_SCORE"
    }

    /// Only user-originated commands travel on this channel.
    enum Origin: String, Codable, Sendable {
        case user = "USER"
    }

    /// `SLEEP_SCORE` payload. `score` is an integer 0–100 (Core EnergyThresholds scale);
    /// `date` is the calendar day `YYYY-MM-DD` derived **server-side** (Mac Mini timezone),
    /// never sent by the iOS Shortcut.
    struct SleepScorePayload: Codable, Sendable, Equatable {
        let score: Int
        let date: String
    }

    /// Fresh UUID per request — SQS FIFO deduplication id.
    let commandId: UUID
    let commandType: CommandType
    let origin: Origin
    let occurredAt: Date
    /// Present only for `SLEEP_SCORE`; encoded as explicit `null` for `REPLAN_AGENDA`.
    let payload: SleepScorePayload?

    /// Valid sleep-score range accepted by the Core (integer, inclusive).
    static let sleepScoreRange = 0...100

    static func replanAgenda(commandId: UUID = UUID(), occurredAt: Date = Date()) -> UserCommand {
        UserCommand(
            commandId: commandId,
            commandType: .replanAgenda,
            origin: .user,
            occurredAt: occurredAt,
            payload: nil
        )
    }

    static func sleepScore(
        _ score: Int,
        commandId: UUID = UUID(),
        occurredAt: Date = Date(),
        timeZone: TimeZone = .current
    ) -> UserCommand {
        UserCommand(
            commandId: commandId,
            commandType: .sleepScore,
            origin: .user,
            occurredAt: occurredAt,
            payload: SleepScorePayload(score: score, date: localDateString(for: occurredAt, in: timeZone))
        )
    }

    /// `YYYY-MM-DD` for the given instant in the given timezone (server-derived contract date).
    static func localDateString(for date: Date = Date(), in timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private enum CodingKeys: String, CodingKey {
        case commandId, commandType, origin, occurredAt, payload
    }

    init(commandId: UUID, commandType: CommandType, origin: Origin, occurredAt: Date, payload: SleepScorePayload?) {
        self.commandId = commandId
        self.commandType = commandType
        self.origin = origin
        self.occurredAt = occurredAt
        self.payload = payload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        commandId = try container.decode(UUID.self, forKey: .commandId)
        commandType = try container.decode(CommandType.self, forKey: .commandType)
        origin = try container.decode(Origin.self, forKey: .origin)
        occurredAt = try container.decode(Date.self, forKey: .occurredAt)
        payload = try container.decodeIfPresent(SleepScorePayload.self, forKey: .payload)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(commandId, forKey: .commandId)
        try container.encode(commandType, forKey: .commandType)
        try container.encode(origin, forKey: .origin)
        try container.encode(occurredAt, forKey: .occurredAt)
        // The contract pins `payload` as `null | object` — encode an explicit null, never omit.
        if let payload {
            try container.encode(payload, forKey: .payload)
        } else {
            try container.encodeNil(forKey: .payload)
        }
    }
}
