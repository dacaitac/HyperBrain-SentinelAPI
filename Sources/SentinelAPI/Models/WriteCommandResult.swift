import Foundation

/// Result published to `apple-commands-results.fifo` after applying a `WriteCommand`
/// (Apple → Core, ADR-010 / HU-09c). On `CREATED` it echoes the native EventKit identifier
/// the Core needs to close its `sync_mapping`; correlation is by `command_id`.
struct WriteCommandResult: Codable, Sendable, Equatable {
    enum Status: String, Codable, Sendable {
        case applied = "APPLIED"
        case failed = "FAILED"
    }

    let schemaVersion: String
    let commandId: UUID
    let status: Status
    let operation: Operation
    /// Native EventKit identifier; nil when the command failed.
    let entityId: String?
    /// Failure detail when `status == .failed`.
    let error: String?
    let appliedAt: Date

    static let currentSchemaVersion = "1"

    init(
        commandId: UUID,
        status: Status,
        operation: Operation,
        entityId: String?,
        error: String? = nil,
        appliedAt: Date = Date()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.commandId = commandId
        self.status = status
        self.operation = operation
        self.entityId = entityId
        self.error = error
        self.appliedAt = appliedAt
    }
}
