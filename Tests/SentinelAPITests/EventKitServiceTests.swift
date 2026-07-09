import Foundation
import Testing
@testable import SentinelAPI

@Suite("EventKitService helpers")
struct EventKitServiceTests {
    private struct Occurrence {
        let id: String
        let start: Date
    }

    @Test("firstPerIdentifier keeps one element per identifier, preserving order")
    func dedupesRecurringOccurrences() {
        // A yearly recurring event expanded into four occurrences sharing one identifier,
        // interleaved with two one-off events — the exact shape that made the snapshot
        // flip-flop and re-publish UPDATED forever.
        let items = [
            Occurrence(id: "recurring", start: Date(timeIntervalSince1970: 0)),
            Occurrence(id: "one-off-a", start: Date(timeIntervalSince1970: 100)),
            Occurrence(id: "recurring", start: Date(timeIntervalSince1970: 200)),
            Occurrence(id: "recurring", start: Date(timeIntervalSince1970: 300)),
            Occurrence(id: "one-off-b", start: Date(timeIntervalSince1970: 400)),
            Occurrence(id: "recurring", start: Date(timeIntervalSince1970: 500)),
        ]

        let deduped = EventKitService.firstPerIdentifier(items) { $0.id }

        #expect(deduped.map(\.id) == ["recurring", "one-off-a", "one-off-b"])
        // The earliest occurrence is the canonical one, so repeated snapshots are stable.
        #expect(deduped[0].start == Date(timeIntervalSince1970: 0))
    }

    @Test("firstPerIdentifier is a no-op when identifiers are unique")
    func keepsUniqueItems() {
        let items = [
            Occurrence(id: "a", start: Date(timeIntervalSince1970: 0)),
            Occurrence(id: "b", start: Date(timeIntervalSince1970: 1)),
        ]
        let deduped = EventKitService.firstPerIdentifier(items) { $0.id }
        #expect(deduped.map(\.id) == ["a", "b"])
    }

    @Test("isDateOnly flags only local midnight — the all-day / date-only signal")
    func detectsDateOnly() {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(EventKitService.isDateOnly(midnight))

        let nineSharp = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: midnight)!
        #expect(!EventKitService.isDateOnly(nineSharp))

        let nineThirty = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: midnight)!
        #expect(!EventKitService.isDateOnly(nineThirty))
    }
}
