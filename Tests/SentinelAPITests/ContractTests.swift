import Foundation
import Testing
@testable import SentinelAPI

@Suite("Wire contract")
struct ContractTests {
    private let encoder = JSONCoding.makeEncoder()
    private let decoder = JSONCoding.makeDecoder()

    private func json(_ event: AppleEntityChangedEvent) throws -> String {
        String(decoding: try encoder.encode(event), as: UTF8.self)
    }

    @Test("Reminder event serializes with snake_case keys and APPLE source")
    func reminderEnvelope() throws {
        let payload = ReminderPayload(
            title: "Buy milk", notes: "2%", dueDate: Date(timeIntervalSince1970: 1_720_000_000),
            completed: false, priority: 1, url: nil, recurrence: "weekly",
            listId: "list-1", listName: "Groceries", location: nil,
            alarms: [AlarmPayload(absoluteDate: nil, relativeOffset: -600, proximity: .none, location: nil)]
        )
        let event = AppleEntityChangedEvent(
            entityType: .reminder, entityId: "rem-1", operation: .created, payload: .reminder(payload)
        )
        let string = try json(event)

        #expect(string.contains("\"schema_version\":\"1\""))
        #expect(string.contains("\"source_system\":\"APPLE\""))
        #expect(string.contains("\"entity_type\":\"REMINDER\""))
        #expect(string.contains("\"operation\":\"CREATED\""))
        #expect(string.contains("\"list_id\":\"list-1\""))
        #expect(string.contains("\"relative_offset\":-600"))
    }

    @Test("Envelope round-trips for every entity type")
    func roundTrip() throws {
        let calendarPayload = CalendarPayload(title: "Work", sourceName: "iCloud", color: "#FF0000", isDefault: true)
        let cases: [AppleEntityChangedEvent] = [
            AppleEntityChangedEvent(entityType: .calendar, entityId: "cal-1", operation: .updated, payload: .calendar(calendarPayload)),
            AppleEntityChangedEvent(entityType: .reminderList, entityId: "list-1", operation: .created, payload: .calendar(calendarPayload)),
            AppleEntityChangedEvent(entityType: .reminder, entityId: "rem-1", operation: .deleted, payload: nil),
        ]
        for original in cases {
            let data = try encoder.encode(original)
            let decoded = try decoder.decode(AppleEntityChangedEvent.self, from: data)
            #expect(decoded.entityType == original.entityType)
            #expect(decoded.entityId == original.entityId)
            #expect(decoded.operation == original.operation)
            #expect(decoded.sourceSystem == .apple)
        }
    }

    @Test("DELETED envelope carries no payload")
    func deletedHasNoPayload() throws {
        let event = AppleEntityChangedEvent(entityType: .calendarEvent, entityId: "e-1", operation: .deleted, payload: nil)
        let string = try json(event)
        #expect(!string.contains("\"payload\""))
    }

    @Test("WriteCommand decodes by command_type discriminator")
    func writeCommandDecodes() throws {
        let body = """
        {
          "command_id": "3F2504E0-4F89-41D3-9A0C-0305E82C3301",
          "command_type": "REMINDER",
          "operation": "CREATED",
          "payload": {
            "title": "From core", "completed": false, "priority": 0,
            "list_id": "l1", "list_name": "Inbox", "alarms": []
          }
        }
        """
        let command = try decoder.decode(WriteCommand.self, from: Data(body.utf8))
        #expect(command.commandType == .reminder)
        #expect(command.operation == .created)
        if case .reminder(let payload) = command.payload {
            #expect(payload.title == "From core")
        } else {
            Issue.record("expected reminder payload")
        }
    }

    @Test("ISO-8601 timestamps keep an explicit offset")
    func iso8601Offset() throws {
        let event = AppleEntityChangedEvent(
            entityType: .reminder, entityId: "r", operation: .deleted,
            occurredAt: Date(timeIntervalSince1970: 1_720_000_000), payload: nil
        )
        let string = try json(event)
        // withInternetDateTime always emits a numeric offset or Z, never a bare local time.
        #expect(string.contains("occurred_at"))
        let hasOffset = string.contains("+") || string.range(of: #"[-+]\d\d:\d\d"#, options: .regularExpression) != nil || string.contains("Z")
        #expect(hasOffset)
    }
}
