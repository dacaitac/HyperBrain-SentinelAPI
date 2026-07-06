import AWSSQS
import Foundation
import Logging

/// Long-polls `apple-commands.fifo` (Core → Apple), decodes `WriteCommand`s and applies them
/// via EventKit. On success the message is deleted; on failure it is left for SQS to retry and
/// eventually redrive to `apple-commands-dlq.fifo`.
///
/// Loop protection: entity ids written here are registered in `LoopGuard` so the `ChangeMonitor`
/// does not re-emit them back to `sync-events.fifo`.
actor SQSConsumer {
    private let client: SQSClient
    private let queueURL: String
    private let eventKit: any EventKitOperations
    private let loopGuard: LoopGuard
    private let decoder = JSONCoding.makeDecoder()
    private let logger: Logger
    private var task: Task<Void, Never>?

    init(region: String, queueURL: String, eventKit: any EventKitOperations, loopGuard: LoopGuard, logger: Logger) async throws {
        self.client = SQSClient(config: try await SQSClient.SQSClientConfig(region: region))
        self.queueURL = queueURL
        self.eventKit = eventKit
        self.loopGuard = loopGuard
        self.logger = logger
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func pollOnce() async {
        do {
            let input = ReceiveMessageInput(maxNumberOfMessages: 10, queueUrl: queueURL, waitTimeSeconds: 20)
            let output = try await client.receiveMessage(input: input)
            for message in output.messages ?? [] {
                await handle(message)
            }
        } catch {
            logger.error("apple-commands poll failed: \(error)")
            try? await Task.sleep(for: .seconds(5))
        }
    }

    private func handle(_ message: SQSClientTypes.Message) async {
        guard let body = message.body, let receiptHandle = message.receiptHandle else { return }
        do {
            let command = try decoder.decode(WriteCommand.self, from: Data(body.utf8))
            let entityId = try await eventKit.apply(command: command)
            await loopGuard.suppress(entityId)
            try await deleteMessage(receiptHandle)
            logger.info("applied \(command.commandType.rawValue) \(command.operation.rawValue) -> \(entityId)")
        } catch {
            // Leave the message on the queue; SQS redrives to the DLQ after maxReceiveCount.
            logger.error("failed to apply write command: \(error)")
        }
    }

    private func deleteMessage(_ receiptHandle: String) async throws {
        _ = try await client.deleteMessage(input: DeleteMessageInput(queueUrl: queueURL, receiptHandle: receiptHandle))
    }
}
