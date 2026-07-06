import Vapor

/// Registers every REST route. Tailscale-only access is enforced at the network layer (RNF-09).
func registerRoutes(_ app: Application, _ services: SentinelServices) throws {
    app.get("health") { _ in ["status": "ok"] }
    app.get("openapi.yaml") { req in try openAPIResponse(req) }

    let eventKit = services.eventKit
    let monitor = services.monitor

    // MARK: Snapshot / resync

    app.get("snapshot") { _ -> SnapshotResponse in
        let records = await eventKit.buildSnapshot()
        return SnapshotResponse(
            reminders: records.reminders(),
            events: records.events(),
            reminderLists: records.calendars(ofType: .reminderList),
            calendars: records.calendars(ofType: .calendar)
        )
    }
    app.post("resync") { _ -> HTTPStatus in
        await monitor.resync()
        return .accepted
    }

    // MARK: Reminders

    app.get("reminders") { _ in await eventKit.fetchReminders().reminders() }
    app.post("reminders") { req -> IdResponse in
        let payload = try req.content.decode(ReminderPayload.self)
        return IdResponse(id: try await eventKit.createReminder(payload))
    }
    app.put("reminders", ":id") { req -> HTTPStatus in
        let id = try req.parameters.require("id")
        try await eventKit.updateReminder(id: id, req.content.decode(ReminderPayload.self))
        return .ok
    }
    app.delete("reminders", ":id") { req -> HTTPStatus in
        try await eventKit.deleteReminder(id: req.parameters.require("id"))
        return .noContent
    }

    // MARK: Events

    app.get("events") { _ in await eventKit.fetchEvents().events() }
    app.post("events") { req -> IdResponse in
        let payload = try req.content.decode(CalendarEventPayload.self)
        return IdResponse(id: try await eventKit.createEvent(payload))
    }
    app.put("events", ":id") { req -> HTTPStatus in
        let id = try req.parameters.require("id")
        try await eventKit.updateEvent(id: id, req.content.decode(CalendarEventPayload.self))
        return .ok
    }
    app.delete("events", ":id") { req -> HTTPStatus in
        try await eventKit.deleteEvent(id: req.parameters.require("id"))
        return .noContent
    }

    // MARK: Reminder lists (EKCalendar / .reminder)

    app.get("reminder-lists") { _ in await eventKit.fetchCalendars(for: .reminder).calendars(ofType: .reminderList) }
    app.post("reminder-lists") { req -> IdResponse in
        let payload = try req.content.decode(CalendarPayload.self)
        return IdResponse(id: try await eventKit.createCalendar(payload, entityType: .reminder))
    }
    app.put("reminder-lists", ":id") { req -> HTTPStatus in
        let id = try req.parameters.require("id")
        try await eventKit.updateCalendar(id: id, req.content.decode(CalendarPayload.self))
        return .ok
    }
    app.delete("reminder-lists", ":id") { req -> HTTPStatus in
        try await eventKit.deleteCalendar(id: req.parameters.require("id"))
        return .noContent
    }

    // MARK: Calendars (EKCalendar / .event)

    app.get("calendars") { _ in await eventKit.fetchCalendars(for: .event).calendars(ofType: .calendar) }
    app.post("calendars") { req -> IdResponse in
        let payload = try req.content.decode(CalendarPayload.self)
        return IdResponse(id: try await eventKit.createCalendar(payload, entityType: .event))
    }
    app.put("calendars", ":id") { req -> HTTPStatus in
        let id = try req.parameters.require("id")
        try await eventKit.updateCalendar(id: id, req.content.decode(CalendarPayload.self))
        return .ok
    }
    app.delete("calendars", ":id") { req -> HTTPStatus in
        try await eventKit.deleteCalendar(id: req.parameters.require("id"))
        return .noContent
    }
}

/// Aggregated debug view of the local snapshot (`GET /snapshot`).
struct SnapshotResponse: Content {
    let reminders: [Identified<ReminderPayload>]
    let events: [Identified<CalendarEventPayload>]
    let reminderLists: [Identified<CalendarPayload>]
    let calendars: [Identified<CalendarPayload>]
}

private func openAPIResponse(_ req: Request) throws -> Response {
    guard let url = Bundle.module.url(forResource: "openapi", withExtension: "yaml"),
          let data = try? Data(contentsOf: url) else {
        throw Abort(.notFound, reason: "openapi.yaml resource missing")
    }
    var headers = HTTPHeaders()
    headers.contentType = HTTPMediaType(type: "application", subType: "yaml")
    return Response(status: .ok, headers: headers, body: .init(data: data))
}

extension Array where Element == EntityRecord {
    func reminders() -> [Identified<ReminderPayload>] {
        compactMap { record in
            if case .reminder(let payload) = record.payload {
                return Identified(id: record.entityId, payload: payload)
            }
            return nil
        }
    }

    func events() -> [Identified<CalendarEventPayload>] {
        compactMap { record in
            if case .calendarEvent(let payload) = record.payload {
                return Identified(id: record.entityId, payload: payload)
            }
            return nil
        }
    }

    func calendars(ofType entityType: EntityType) -> [Identified<CalendarPayload>] {
        compactMap { record in
            guard record.entityType == entityType, case .calendar(let payload) = record.payload else {
                return nil
            }
            return Identified(id: record.entityId, payload: payload)
        }
    }
}
