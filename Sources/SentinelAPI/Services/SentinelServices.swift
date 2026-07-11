import Vapor

/// Holds the long-lived actors that make up SentinelAPI, wired together at boot.
struct SentinelServices: Sendable {
    let eventKit: any EventKitOperations
    let snapshotStore: SnapshotStore
    let publisher: any EventPublisher
    /// Sink for user commands (HU-01b): SQS `user-commands.fifo` in production,
    /// logging in local-test mode.
    let commandPublisher: any UserCommandPublisher
    /// Nil in local-test mode (no AWS): the Core → Apple command consumer is disabled.
    let consumer: SQSConsumer?
    let monitor: ChangeMonitor
    let loopGuard: LoopGuard
}

extension Application {
    private struct SentinelServicesKey: StorageKey {
        typealias Value = SentinelServices
    }

    var sentinel: SentinelServices? {
        get { storage[SentinelServicesKey.self] }
        set { storage[SentinelServicesKey.self] = newValue }
    }
}
