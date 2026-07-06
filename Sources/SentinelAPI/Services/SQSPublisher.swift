import AWSSQS
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
            messageGroupId: event.entityId,
            queueUrl: queueURL
        )
        _ = try await client.sendMessage(input: input)
    }
}
