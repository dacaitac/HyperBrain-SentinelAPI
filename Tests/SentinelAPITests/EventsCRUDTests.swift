import Foundation
import Logging
import XCTest
import XCTVapor
@testable import SentinelAPI

/// REST CRUD tests for `GET/POST/PUT/DELETE /events`.
/// Uses `MockEventKitService` — no real EventKit / TCC permission needed.
final class EventsCRUDTests: XCTestCase {

    // MARK: - Helpers

    private func makeApp() throws -> Application {
        let app = Application(.testing)
        ContentConfiguration.global.use(encoder: JSONCoding.makeEncoder(), for: .json)
        ContentConfiguration.global.use(decoder: JSONCoding.makeDecoder(), for: .json)

        let mock = MockEventKitService()
        let loopGuard = LoopGuard()
        let publisher = LoggingEventPublisher(logger: app.logger)
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentinel-test-\(UUID().uuidString).json")
        let snapshotStore = SnapshotStore(fileURL: tmpURL)
        let monitor = ChangeMonitor(
            eventKit: mock,
            snapshotStore: snapshotStore,
            publisher: publisher,
            loopGuard: loopGuard,
            logger: app.logger
        )
        let services = SentinelServices(
            eventKit: mock,
            snapshotStore: snapshotStore,
            publisher: publisher,
            commandPublisher: LoggingUserCommandPublisher(logger: app.logger),
            consumer: nil,
            monitor: monitor,
            loopGuard: loopGuard
        )
        try registerRoutes(app, services)
        return app
    }

    private var samplePayload: CalendarEventPayload {
        CalendarEventPayload(
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
            alarms: []
        )
    }

    private func encode(_ payload: CalendarEventPayload) throws -> ByteBuffer {
        let data = try JSONCoding.makeEncoder().encode(payload)
        return ByteBuffer(data: data)
    }

    // MARK: - Tests

    func testGetEventsReturnsEmptyList() throws {
        let app = try makeApp()
        defer { app.shutdown() }

        try app.test(.GET, "events") { res in
            XCTAssertEqual(res.status, .ok)
            let list = try JSONDecoder().decode([Identified<CalendarEventPayload>].self, from: res.body)
            XCTAssertTrue(list.isEmpty)
        }
    }

    func testPostEventCreatesAndReturnsId() throws {
        let app = try makeApp()
        defer { app.shutdown() }

        var createdId: String?
        try app.test(.POST, "events",
                     headers: ["Content-Type": "application/json"],
                     body: try encode(samplePayload)) { res in
            XCTAssertEqual(res.status, .ok)
            let response = try JSONDecoder().decode(IdResponse.self, from: res.body)
            XCTAssertFalse(response.id.isEmpty)
            createdId = response.id
        }
        XCTAssertNotNil(createdId)
    }

    func testGetEventsAfterCreateContainsNewEvent() throws {
        let app = try makeApp()
        defer { app.shutdown() }

        var createdId: String?
        try app.test(.POST, "events",
                     headers: ["Content-Type": "application/json"],
                     body: try encode(samplePayload)) { res in
            createdId = try JSONDecoder().decode(IdResponse.self, from: res.body).id
        }

        try app.test(.GET, "events") { res in
            XCTAssertEqual(res.status, .ok)
            let decoder = JSONCoding.makeDecoder()
            let list = try decoder.decode([Identified<CalendarEventPayload>].self, from: Data(buffer: res.body))
            let found = list.first { $0.id == createdId }
            XCTAssertNotNil(found)
            XCTAssertEqual(found?.payload.title, "Sprint Review")
            XCTAssertEqual(found?.payload.calendarName, "Work")
        }
    }

    func testPutEventUpdatesTitle() throws {
        let app = try makeApp()
        defer { app.shutdown() }

        var createdId: String?
        try app.test(.POST, "events",
                     headers: ["Content-Type": "application/json"],
                     body: try encode(samplePayload)) { res in
            createdId = try JSONDecoder().decode(IdResponse.self, from: res.body).id
        }

        let updated = CalendarEventPayload(
            title: "Retro",
            startTime: samplePayload.startTime,
            endTime: samplePayload.endTime,
            allDay: false,
            notes: nil,
            url: nil,
            recurrence: nil,
            calendarId: "cal-work",
            calendarName: "Work",
            location: nil,
            alarms: []
        )

        try app.test(.PUT, "events/\(createdId!)",
                     headers: ["Content-Type": "application/json"],
                     body: try encode(updated)) { res in
            XCTAssertEqual(res.status, .ok)
        }

        try app.test(.GET, "events") { res in
            let decoder = JSONCoding.makeDecoder()
            let list = try decoder.decode([Identified<CalendarEventPayload>].self, from: Data(buffer: res.body))
            let found = list.first { $0.id == createdId }
            XCTAssertEqual(found?.payload.title, "Retro")
        }
    }

    func testDeleteEventRemovesIt() throws {
        let app = try makeApp()
        defer { app.shutdown() }

        var createdId: String?
        try app.test(.POST, "events",
                     headers: ["Content-Type": "application/json"],
                     body: try encode(samplePayload)) { res in
            createdId = try JSONDecoder().decode(IdResponse.self, from: res.body).id
        }

        try app.test(.DELETE, "events/\(createdId!)") { res in
            XCTAssertEqual(res.status, .noContent)
        }

        try app.test(.GET, "events") { res in
            let decoder = JSONCoding.makeDecoder()
            let list = try decoder.decode([Identified<CalendarEventPayload>].self, from: Data(buffer: res.body))
            XCTAssertTrue(list.isEmpty)
        }
    }

    func testDeleteNonexistentEventReturns404() throws {
        let app = try makeApp()
        defer { app.shutdown() }

        try app.test(.DELETE, "events/no-such-id") { res in
            XCTAssertEqual(res.status, .notFound)
        }
    }

    func testAllDayEventRoundTrips() throws {
        let app = try makeApp()
        defer { app.shutdown() }

        let allDay = CalendarEventPayload(
            title: "Company Holiday",
            startTime: Date(timeIntervalSince1970: 1_752_192_000),
            endTime: nil,
            allDay: true,
            notes: nil,
            url: nil,
            recurrence: nil,
            calendarId: "cal-personal",
            calendarName: "Personal",
            location: nil,
            alarms: []
        )

        var createdId: String?
        try app.test(.POST, "events",
                     headers: ["Content-Type": "application/json"],
                     body: try encode(allDay)) { res in
            XCTAssertEqual(res.status, .ok)
            createdId = try JSONDecoder().decode(IdResponse.self, from: res.body).id
        }

        try app.test(.GET, "events") { res in
            let decoder = JSONCoding.makeDecoder()
            let list = try decoder.decode([Identified<CalendarEventPayload>].self, from: Data(buffer: res.body))
            let found = list.first { $0.id == createdId }
            XCTAssertEqual(found?.payload.allDay, true)
            XCTAssertNil(found?.payload.endTime)
        }
    }
}
