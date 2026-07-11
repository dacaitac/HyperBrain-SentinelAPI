import Foundation
import Testing
@testable import SentinelAPI

/// Wire-contract coverage for `UserCommand` (HU-01b slice 2, `user-commands.fifo`).
/// The Core consumes exactly this shape: snake_case keys, `origin` always `USER`,
/// `payload: null` for REPLAN_AGENDA and `{ score, date }` for SLEEP_SCORE.
@Suite("UserCommand wire contract")
struct UserCommandContractTests {
    private let encoder = JSONCoding.makeEncoder()
    private let decoder = JSONCoding.makeDecoder()

    private func json(_ value: some Encodable) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    @Test("REPLAN_AGENDA serializes with snake_case keys, USER origin and explicit null payload")
    func replanAgendaEnvelope() throws {
        let command = UserCommand.replanAgenda(
            commandId: UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3501")!,
            occurredAt: Date(timeIntervalSince1970: 1_752_300_000)
        )
        let string = try json(command)

        #expect(string.contains("\"command_id\":\"3F2504E0-4F89-41D3-9A0C-0305E82C3501\""))
        #expect(string.contains("\"command_type\":\"REPLAN_AGENDA\""))
        #expect(string.contains("\"origin\":\"USER\""))
        #expect(string.contains("\"occurred_at\""))
        // Contract pins payload as null | object — REPLAN_AGENDA must carry an explicit null.
        #expect(string.contains("\"payload\":null"))
    }

    @Test("SLEEP_SCORE serializes with score and server-derived date")
    func sleepScoreEnvelope() throws {
        let utc = TimeZone(identifier: "UTC")!
        let occurredAt = Date(timeIntervalSince1970: 1_752_300_000)
        let command = UserCommand.sleepScore(87, occurredAt: occurredAt, timeZone: utc)
        let string = try json(command)

        #expect(string.contains("\"command_type\":\"SLEEP_SCORE\""))
        #expect(string.contains("\"origin\":\"USER\""))
        #expect(string.contains("\"score\":87"))
        #expect(string.contains("\"date\":\"\(UserCommand.localDateString(for: occurredAt, in: utc))\""))
        // date is a bare calendar day, never a timestamp.
        #expect(string.range(of: #""date":"\d{4}-\d{2}-\d{2}""#, options: .regularExpression) != nil)
    }

    @Test("Both command types round-trip through the wire coders")
    func roundTrip() throws {
        let cases: [UserCommand] = [
            .replanAgenda(occurredAt: Date(timeIntervalSince1970: 1_752_300_000)),
            .sleepScore(42, occurredAt: Date(timeIntervalSince1970: 1_752_303_600)),
        ]
        for original in cases {
            let decoded = try decoder.decode(UserCommand.self, from: try encoder.encode(original))
            #expect(decoded == original)
            #expect(decoded.origin == .user)
        }
    }

    @Test("Fresh command_id per factory call — never reused")
    func freshCommandId() {
        #expect(UserCommand.replanAgenda().commandId != UserCommand.replanAgenda().commandId)
        #expect(UserCommand.sleepScore(50).commandId != UserCommand.sleepScore(50).commandId)
    }

    @Test("Non-USER origin is rejected on decode")
    func rejectsForeignOrigin() {
        let body = """
        {
          "command_id": "3F2504E0-4F89-41D3-9A0C-0305E82C3502",
          "command_type": "REPLAN_AGENDA",
          "origin": "CORE",
          "occurred_at": "2026-07-11T09:00:00Z",
          "payload": null
        }
        """
        #expect(throws: DecodingError.self) {
            try decoder.decode(UserCommand.self, from: Data(body.utf8))
        }
    }

    @Test("localDateString derives the calendar day in the given timezone")
    func localDateStringDerivation() {
        let epoch = Date(timeIntervalSince1970: 0)
        #expect(UserCommand.localDateString(for: epoch, in: TimeZone(identifier: "UTC")!) == "1970-01-01")
        // One hour west of UTC it is still the previous day.
        #expect(UserCommand.localDateString(for: epoch, in: TimeZone(secondsFromGMT: -3600)!) == "1969-12-31")
    }
}
