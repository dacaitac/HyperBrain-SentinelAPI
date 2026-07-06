import Foundation
import Testing
@testable import SentinelAPI

@Suite("Wire contract")
struct ContractTests {
    private let encoder = JSONCoding.makeEncoder()
    private let decoder = JSONCoding.makeDecoder()

    private func json(_ value: some Encodable) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
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

    @Test("CalendarEvent event serializes with snake_case keys and CALENDAR_EVENT entity type")
    func calendarEventEnvelope() throws {
        let payload = CalendarEventPayload(
            title: "Sprint Review",
            startTime: Date(timeIntervalSince1970: 1_752_300_000),
            endTime: Date(timeIntervalSince1970: 1_752_303_600),
            allDay: false,
            notes: "Demo completed work",
            url: nil,
            recurrence: nil,
            calendarId: "cal-work",
            calendarName: "Work",
            location: "Room 101",
            alarms: [AlarmPayload(absoluteDate: nil, relativeOffset: -900, proximity: .none, location: nil)]
        )
        let event = AppleEntityChangedEvent(
            entityType: .calendarEvent, entityId: "evt-1", operation: .updated, payload: .calendarEvent(payload)
        )
        let string = try json(event)

        #expect(string.contains("\"schema_version\":\"1\""))
        #expect(string.contains("\"source_system\":\"APPLE\""))
        #expect(string.contains("\"entity_type\":\"CALENDAR_EVENT\""))
        #expect(string.contains("\"operation\":\"UPDATED\""))
        #expect(string.contains("\"start_time\""))
        #expect(string.contains("\"end_time\""))
        #expect(string.contains("\"all_day\":false"))
        #expect(string.contains("\"calendar_id\":\"cal-work\""))
        #expect(string.contains("\"calendar_name\":\"Work\""))
        #expect(string.contains("\"relative_offset\":-900"))
    }

    @Test("Envelope round-trips for every entity type")
    func roundTrip() throws {
        let calendarPayload = CalendarPayload(title: "Work", sourceName: "iCloud", color: "#FF0000", isDefault: true)
        let eventPayload = CalendarEventPayload(
            title: "Standup", startTime: Date(timeIntervalSince1970: 1_752_300_000),
            endTime: Date(timeIntervalSince1970: 1_752_301_800), allDay: false, notes: nil,
            url: nil, recurrence: nil, calendarId: "c1", calendarName: "Work", location: nil, alarms: []
        )
        let cases: [AppleEntityChangedEvent] = [
            AppleEntityChangedEvent(entityType: .calendar, entityId: "cal-1", operation: .updated, payload: .calendar(calendarPayload)),
            AppleEntityChangedEvent(entityType: .reminderList, entityId: "list-1", operation: .created, payload: .calendar(calendarPayload)),
            AppleEntityChangedEvent(entityType: .reminder, entityId: "rem-1", operation: .deleted, payload: nil),
            AppleEntityChangedEvent(entityType: .calendarEvent, entityId: "evt-1", operation: .created, payload: .calendarEvent(eventPayload)),
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

    @Test("WriteCommand decodes CALENDAR_EVENT by command_type discriminator")
    func writeCommandCalendarEventDecodes() throws {
        let body = """
        {
          "command_id": "3F2504E0-4F89-41D3-9A0C-0305E82C3302",
          "command_type": "CALENDAR_EVENT",
          "operation": "CREATED",
          "payload": {
            "title": "Sprint Review",
            "start_time": "2026-07-07T10:00:00Z",
            "end_time": "2026-07-07T11:00:00Z",
            "all_day": false,
            "calendar_id": "cal-work",
            "calendar_name": "Work",
            "alarms": []
          }
        }
        """
        let command = try decoder.decode(WriteCommand.self, from: Data(body.utf8))
        #expect(command.commandType == .calendarEvent)
        #expect(command.operation == .created)
        if case .calendarEvent(let payload) = command.payload {
            #expect(payload.title == "Sprint Review")
            #expect(payload.calendarName == "Work")
            #expect(payload.allDay == false)
        } else {
            Issue.record("expected calendarEvent payload")
        }
    }

    @Test("WriteCommand from the Core decodes with null entity_id and empty list_id")
    func writeCommandFromCoreDecodes() throws {
        // Exact shape emitted by the Core's WriteCommandWireMapper (HU-09c).
        let body = """
        {
          "command_id": "3F2504E0-4F89-41D3-9A0C-0305E82C3303",
          "command_type": "REMINDER",
          "operation": "CREATED",
          "entity_id": null,
          "payload": {
            "title": "Agenda item", "notes": null, "due_date": "2026-07-07T09:00:00Z",
            "completed": false, "priority": 0, "url": null, "recurrence": null,
            "list_id": "", "list_name": "HyperBrain", "location": null, "alarms": []
          }
        }
        """
        let command = try decoder.decode(WriteCommand.self, from: Data(body.utf8))
        #expect(command.entityId == nil)
        if case .reminder(let payload) = command.payload {
            #expect(payload.listId.isEmpty)
            #expect(payload.alarms.isEmpty)
        } else {
            Issue.record("expected reminder payload")
        }
    }

    @Test("WriteCommandResult encodes the ADR-010 wire contract")
    func writeCommandResultEncodes() throws {
        let result = WriteCommandResult(
            commandId: UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3304")!,
            status: .applied,
            operation: .created,
            entityId: "EK-123",
            appliedAt: Date(timeIntervalSince1970: 1_720_000_000)
        )
        let string = try json(result)
        #expect(string.contains("\"schema_version\":\"1\""))
        #expect(string.contains("\"command_id\":\"3F2504E0-4F89-41D3-9A0C-0305E82C3304\""))
        #expect(string.contains("\"status\":\"APPLIED\""))
        #expect(string.contains("\"operation\":\"CREATED\""))
        #expect(string.contains("\"entity_id\":\"EK-123\""))
        #expect(string.contains("applied_at"))
    }

    @Test("FAILED WriteCommandResult carries the error and a null entity_id")
    func failedWriteCommandResultEncodes() throws {
        let result = WriteCommandResult(
            commandId: UUID(),
            status: .failed,
            operation: .updated,
            entityId: nil,
            error: "No EventKit item with identifier 'x'"
        )
        let string = try json(result)
        #expect(string.contains("\"status\":\"FAILED\""))
        #expect(string.contains("\"error\":\"No EventKit item with identifier 'x'\""))
        #expect(!string.contains("\"entity_id\":\"")) // nil is omitted or null, never a value
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
