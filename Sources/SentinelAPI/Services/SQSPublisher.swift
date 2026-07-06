import AWSSQS
import CryptoKit
import Foundation

/// Publishes `AppleEntityChangedEvent`s to `sync-events.fifo` (Apple → Core).
///
/// FIFO parameters per contract: `MessageGroupId = entity_id` (per-entity ordering),
/// `MessageDeduplicationId = event_id` (native dedup, `ContentBasedDeduplication=false`).
actor SQSPublisher {
    private let client: SQSClient
    private let queueURL: String
    private let encoder = JSONCoding.makeEncoder()

    init(region: String, queueURL: String) async throws {
        self.client = SQSClient(config: try await SQSClient.SQSClientConfig(region: region))
        self.queueURL = queueURL
    }

    func publish(_ event: AppleEntityChangedEvent) async throws {
        let body = String(decoding: try encoder.encode(event), as: UTF8.self)
        let input = SendMessageInput(
            messageBody: body,
            messageDeduplicationId: event.eventId.uuidString,
            messageGroupId: groupId(for: event.entityId),
            queueUrl: queueURL
        )
        _ = try await client.sendMessage(input: input)
    }

    /// SQS FIFO MessageGroupId max = 128 chars. Some EventKit identifiers (Exchange/Outlook)
    /// produce composite IDs like `<calendarUUID>:<96-char-hex>` that exceed this limit.
    /// Hash with SHA-256 (64 hex chars) when needed — deterministic, preserves per-entity ordering.
    private func groupId(for entityId: String) -> String {
        guard entityId.count > 128 else { return entityId }
        return SHA256.hash(data: Data(entityId.utf8))
            .compactMap { String(format: "%02x", $0) }.joined()
    }
}
