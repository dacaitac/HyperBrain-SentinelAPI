import Vapor

/// Holds the long-lived actors that make up SentinelAPI, wired together at boot.
struct SentinelServices: Sendable {
    let eventKit: EventKitService
    let snapshotStore: SnapshotStore
    let publisher: any EventPublisher
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
