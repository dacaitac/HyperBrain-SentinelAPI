import Crypto
import Foundation

/// A single detected change to publish to `sync-events.fifo`.
struct EntityChange: Sendable {
    let entityType: EntityType
    let entityId: String
    let operation: Operation
    /// Nil for `DELETED`.
    let payload: EntityPayload?
}

/// Persists a checksum-per-entity snapshot to disk so the service can survive restarts
/// without re-emitting the whole state, and diff EventKit against the last known baseline.
actor SnapshotStore {
    private let fileURL: URL
    /// entityId -> "\(entityType.rawValue):\(checksum)"
    private var state: [String: String] = [:]
    private var loaded = false

    private let checksumEncoder: JSONEncoder = {
        let encoder = JSONCoding.makeEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Loads the persisted snapshot (empty if none exists).
    func load() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        state = decoded
    }

    /// Whether a baseline exists. On the very first run there is none, so the first diff is
    /// swallowed as a baseline (no spurious CREATED storm for pre-existing data).
    var hasBaseline: Bool { !state.isEmpty }

    /// Computes the changes between the current EventKit records and the stored baseline,
    /// then updates and persists the baseline. Returns [] on the first-ever run (baseline seed).
    func reconcile(with records: [EntityRecord]) -> [EntityChange] {
        let seeding = state.isEmpty
        var next: [String: String] = [:]
        var changes: [EntityChange] = []

        for record in records {
            let checksum = checksum(of: record.payload)
            let fingerprint = "\(record.entityType.rawValue):\(checksum)"
            next[record.entityId] = fingerprint

            guard !seeding else { continue }
            if let previous = state[record.entityId] {
                if previous != fingerprint {
                    changes.append(EntityChange(entityType: record.entityType, entityId: record.entityId,
                                                operation: .updated, payload: record.payload))
                }
            } else {
                changes.append(EntityChange(entityType: record.entityType, entityId: record.entityId,
                                            operation: .created, payload: record.payload))
            }
        }

        if !seeding {
            for (entityId, fingerprint) in state where next[entityId] == nil {
                let entityType = EntityType(rawValue: String(fingerprint.prefix(while: { $0 != ":" }))) ?? .reminder
                changes.append(EntityChange(entityType: entityType, entityId: entityId,
                                            operation: .deleted, payload: nil))
            }
        }

        state = next
        persist()
        return changes
    }

    private func persist() {
        guard let data = try? checksumEncoder.encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func checksum(of payload: EntityPayload) -> String {
        let data: Data
        switch payload {
        case .reminder(let value): data = (try? checksumEncoder.encode(value)) ?? Data()
        case .calendarEvent(let value): data = (try? checksumEncoder.encode(value)) ?? Data()
        case .calendar(let value): data = (try? checksumEncoder.encode(value)) ?? Data()
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
