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

/// `POST /commands/sleep-score` request body. `date` is never accepted from the client —
/// it is derived server-side (HU-01b contract).
struct SleepScoreRequest: Content {
    /// Integer 0–100 (Core EnergyThresholds scale); validated in the route.
    let score: Int
}

/// `202 Accepted` body for `POST /commands/*`: the `command_id` published to `user-commands.fifo`.
struct CommandAcceptedResponse: Content {
    let commandId: UUID
}
