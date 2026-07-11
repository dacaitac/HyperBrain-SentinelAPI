import EventKit
import Foundation
import Testing
@testable import SentinelAPI

/// Unit coverage for the HU-01b agenda write-back: the CALENDAR_EVENT payload → EKEvent mapping and
/// the managed "HyperBrain" calendar contract. Tests that build/save real EventKit calendars or
/// events require TCC (Calendar access) and a live `EKEventStore`, so they are exercised on the Mac
/// Mini; here we cover the store-free mapping and the wire-shape decode.
@Suite("Agenda write-back (HU-01b)")
struct AgendaWriteBackTests {
    private let decoder = JSONCoding.makeDecoder()

    /// Exact CALENDAR_EVENT block emitted by the Core for an agenda block: empty calendar_id and the
    /// managed calendar name. Confirms the payload the resolver keys on decodes as expected.
    @Test("Agenda block CALENDAR_EVENT decodes with empty calendar_id and the HyperBrain name")
    func agendaBlockDecodes() throws {
        let body = """
        {
          "command_id": "3F2504E0-4F89-41D3-9A0C-0305E82C3401",
          "command_type": "CALENDAR_EVENT",
          "operation": "CREATED",
          "entity_id": null,
          "payload": {
            "title": "Deep work: HU-01b",
            "start_time": "2026-07-11T09:00:00-05:00",
            "end_time": "2026-07-11T10:30:00-05:00",
            "all_day": false,
            "notes": "High-leverage block\\n\\nRequires F6 focus energy",
            "url": null, "recurrence": null,
            "calendar_id": "", "calendar_name": "HyperBrain",
            "location": null, "alarms": []
          }
        }
        """
        let command = try decoder.decode(WriteCommand.self, from: Data(body.utf8))
        #expect(command.commandType == .calendarEvent)
        #expect(command.operation == .created)
        #expect(command.entityId == nil)
        guard case .calendarEvent(let payload) = command.payload else {
            Issue.record("expected calendarEvent payload")
            return
        }
        #expect(payload.calendarId.isEmpty)
        #expect(payload.calendarName == EventKitService.managedCalendarName)
        #expect(payload.title == "Deep work: HU-01b")
        #expect(payload.allDay == false)
        #expect(payload.notes?.contains("F6") == true)
    }

    @Test("Managed calendar name is the agreed HyperBrain calendar title")
    func managedCalendarName() {
        #expect(EventKitService.managedCalendarName == "HyperBrain")
    }

    /// The window-empty signal is a REMINDER (a checkable notice), handled by the existing HU-09c
    /// reminder path — it must decode into the reminder branch, not the calendar-event branch.
    @Test("Empty-window signal decodes as a REMINDER for the HyperBrain list")
    func emptyWindowSignalDecodesAsReminder() throws {
        let body = """
        {
          "command_id": "3F2504E0-4F89-41D3-9A0C-0305E82C3402",
          "command_type": "REMINDER",
          "operation": "CREATED",
          "entity_id": null,
          "payload": {
            "title": "No agenda blocks today",
            "notes": "No useful blocks fit today's window — planned for tomorrow instead.",
            "due_date": "2026-07-11T08:00:00-05:00",
            "completed": false, "priority": 0, "url": null, "recurrence": null,
            "list_id": "", "list_name": "HyperBrain", "location": null, "alarms": []
          }
        }
        """
        let command = try decoder.decode(WriteCommand.self, from: Data(body.utf8))
        #expect(command.commandType == .reminder)
        guard case .reminder(let payload) = command.payload else {
            Issue.record("expected reminder payload")
            return
        }
        #expect(payload.listId.isEmpty)
        #expect(payload.listName == "HyperBrain")
        #expect(payload.title == "No agenda blocks today")
    }
}
