import Foundation
import Testing
@testable import SentinelAPI

@Suite("SnapshotStore diff")
struct SnapshotStoreTests {
    private func makeStore() -> SnapshotStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot-\(UUID().uuidString).json")
        return SnapshotStore(fileURL: url)
    }

    private func reminderRecord(_ id: String, title: String) -> EntityRecord {
        EntityRecord(
            entityId: id, entityType: .reminder,
            payload: .reminder(ReminderPayload(
                title: title, notes: nil, dueDate: nil, completed: false, priority: 0,
                url: nil, recurrence: nil, listId: "l1", listName: "Inbox", location: nil, alarms: []
            ))
        )
    }

    @Test("First reconcile seeds the baseline and emits nothing")
    func baselineSeed() async {
        let store = makeStore()
        let changes = await store.reconcile(with: [reminderRecord("a", title: "A")])
        #expect(changes.isEmpty)
    }

    @Test("New, changed and removed entities produce the right operations")
    func detectsChanges() async {
        let store = makeStore()
        _ = await store.reconcile(with: [reminderRecord("a", title: "A"), reminderRecord("b", title: "B")])

        let changes = await store.reconcile(with: [
            reminderRecord("a", title: "A"),          // unchanged
            reminderRecord("b", title: "B changed"),  // updated
            reminderRecord("c", title: "C"),          // created
            // "b"? still present; "a" present; removed none yet
        ])
        let byId = Dictionary(uniqueKeysWithValues: changes.map { ($0.entityId, $0.operation) })
        #expect(byId["b"] == .updated)
        #expect(byId["c"] == .created)
        #expect(byId["a"] == nil) // unchanged -> not emitted
    }

    @Test("Removed entity emits DELETED")
    func detectsDeletion() async {
        let store = makeStore()
        _ = await store.reconcile(with: [reminderRecord("a", title: "A"), reminderRecord("b", title: "B")])
        let changes = await store.reconcile(with: [reminderRecord("a", title: "A")])
        #expect(changes.count == 1)
        #expect(changes.first?.entityId == "b")
        #expect(changes.first?.operation == .deleted)
    }
}

@Suite("LoopGuard")
struct LoopGuardTests {
    @Test("Suppressed id is skipped exactly once")
    func skipsOnce() async {
        let guardActor = LoopGuard()
        await guardActor.suppress("x")
        #expect(await guardActor.shouldSkip("x") == true)
        #expect(await guardActor.shouldSkip("x") == false)
    }

    @Test("Unknown id is never skipped")
    func passesUnknown() async {
        let guardActor = LoopGuard()
        #expect(await guardActor.shouldSkip("never") == false)
    }
}
