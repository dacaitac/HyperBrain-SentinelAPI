import Vapor

// Wire payloads double as REST request/response bodies. Vapor's Content uses the
// snake_case + ISO-8601 coders registered in `configure` (see ContentConfiguration).
extension ReminderPayload: Content {}
extension CalendarEventPayload: Content {}
extension CalendarPayload: Content {}
extension AlarmPayload: Content {}
extension LocationPayload: Content {}

/// `{ "id": "<EventKit identifier>" }` — returned on create.
struct IdResponse: Content {
    let id: String
}

/// An entity paired with its EventKit identifier, for GET/list responses.
struct Identified<T: Content>: Content {
    let id: String
    let payload: T
}
