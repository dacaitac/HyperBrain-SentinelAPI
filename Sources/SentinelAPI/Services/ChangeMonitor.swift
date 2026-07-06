import Foundation
import Logging

/// Observes EventKit, diffs against the persisted snapshot and publishes each real change to
/// `sync-events.fifo`. Replaces the legacy `sentinel-daemon` webhook loop.
actor ChangeMonitor {
    private let eventKit: any EventKitOperations
    private let snapshotStore: SnapshotStore
    private let publisher: any EventPublisher
    private let loopGuard: LoopGuard
    private let logger: Logger
    private let debounce: Duration
    private var task: Task<Void, Never>?

    init(
        eventKit: any EventKitOperations,
        snapshotStore: SnapshotStore,
        publisher: any EventPublisher,
        loopGuard: LoopGuard,
        logger: Logger,
        debounce: Duration = .seconds(1)
    ) {
        self.eventKit = eventKit
        self.snapshotStore = snapshotStore
        self.publisher = publisher
        self.loopGuard = loopGuard
        self.logger = logger
        self.debounce = debounce
    }

    /// Loads the baseline, seeds it from the current store (no emission on first run) and starts
    /// observing changes.
    func start() async {
        await snapshotStore.load()
        await reconcileAndPublish()

        let stream = await eventKit.changeStream()
        task = Task { [weak self] in
            for await _ in stream {
                guard let self, !Task.isCancelled else { break }
                try? await Task.sleep(for: self.debounce)
                await self.reconcileAndPublish()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Forces a snapshot rebuild against EventKit and publishes any drift (`POST /resync`).
    func resync() async {
        await reconcileAndPublish()
    }

    private func reconcileAndPublish() async {
        do {
            let records = await eventKit.buildSnapshot()
            let changes = await snapshotStore.reconcile(with: records)
            for change in changes {
                if await loopGuard.shouldSkip(change.entityId) { continue }
                let event = AppleEntityChangedEvent(
                    entityType: change.entityType,
                    entityId: change.entityId,
                    operation: change.operation,
                    payload: change.payload
                )
                try await publisher.publish(event)
                logger.info("published \(change.entityType.rawValue) \(change.operation.rawValue) \(change.entityId)")
            }
        } catch {
            logger.error("reconcile failed: \(error)")
        }
    }
}
