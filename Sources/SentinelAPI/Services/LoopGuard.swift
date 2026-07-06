import Foundation

/// Short-lived record of entity ids that SentinelAPI itself just wrote via EventKit
/// (from `apple-commands.fifo`). The `ChangeMonitor` consults it to avoid re-emitting those
/// writes to `sync-events.fifo`, which would loop Core → Apple → Core.
actor LoopGuard {
    private var suppressed: [String: Date] = [:]
    private let window: TimeInterval

    init(window: TimeInterval = 30) {
        self.window = window
    }

    func suppress(_ entityId: String) {
        suppressed[entityId] = Date()
    }

    /// Returns true if this id was recently written by us (and consumes the suppression).
    func shouldSkip(_ entityId: String) -> Bool {
        prune()
        guard let timestamp = suppressed[entityId], Date().timeIntervalSince(timestamp) < window else {
            return false
        }
        suppressed[entityId] = nil
        return true
    }

    private func prune() {
        let now = Date()
        suppressed = suppressed.filter { now.timeIntervalSince($0.value) < window }
    }
}
