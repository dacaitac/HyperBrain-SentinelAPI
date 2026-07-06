import EventKit
import Foundation

/// Abstraction over EventKit operations. Allows dependency injection in tests without requiring
/// a real `EKEventStore` (TCC permission) on the test machine.
protocol EventKitOperations: Sendable {
    func requestAccess() async throws
    func changeStream() async -> AsyncStream<Void>
    func buildSnapshot() async -> [EntityRecord]
    func fetchReminders() async -> [EntityRecord]
    func fetchEvents() async -> [EntityRecord]
    func fetchCalendars(for entityType: EKEntityType) async -> [EntityRecord]
    @discardableResult func createReminder(_ payload: ReminderPayload) async throws -> String
    func updateReminder(id: String, _ payload: ReminderPayload) async throws
    func deleteReminder(id: String) async throws
    @discardableResult func createEvent(_ payload: CalendarEventPayload) async throws -> String
    func updateEvent(id: String, _ payload: CalendarEventPayload) async throws
    func deleteEvent(id: String) async throws
    @discardableResult func createCalendar(_ payload: CalendarPayload, entityType: EKEntityType) async throws -> String
    func updateCalendar(id: String, _ payload: CalendarPayload) async throws
    func deleteCalendar(id: String) async throws
    @discardableResult func apply(command: WriteCommand) async throws -> String
}

extension EventKitService: EventKitOperations {}
