import AWSSQS
import Foundation
import Logging

/// Long-polls `apple-commands.fifo` (Core → Apple), decodes `WriteCommand`s and applies them
/// via EventKit. After applying, publishes a `WriteCommandResult` to
/// `apple-commands-results.fifo` (ADR-010) — on CREATED it carries the fresh EventKit id the
/// Core needs to close its `sync_mapping` — and only then deletes the message. On failure the
/// message is left for SQS to retry; once `ApproximateReceiveCount` reaches the redrive limit a
/// FAILED result is published and the message redrives to `apple-commands-dlq.fifo`.
///
/// Idempotency: SQS delivers at-least-once, so command ids applied recently are remembered and
/// a duplicate delivery only re-publishes its result (never re-applies the write). Loop
/// protection: entity ids written here are registered in `LoopGuard` so the `ChangeMonitor`
/// does not re-emit them back to `sync-events.fifo`.
actor SQSConsumer {
    /// Redrive limit of apple-commands.fifo (maxReceiveCount in the queue's redrive policy).
    private static let maxReceiveCount = 3
    /// How long an applied command id is remembered for duplicate suppression.
    private static let dedupWindow: TimeInterval = 24 * 60 * 60

    private let client: SQSClient
    private let queueURL: String
    private let resultsQueueURL: String
    private let eventKit: any EventKitOperations
    private let loopGuard: LoopGuard
    private let decoder = JSONCoding.makeDecoder()
    private let encoder = JSONCoding.makeEncoder()
    private let logger: Logger
    private var task: Task<Void, Never>?
    /// Applied command ids → (resulting entity id, when applied). Pruned by `dedupWindow`.
    private var appliedCommands: [UUID: (entityId: String, appliedAt: Date)] = [:]

    init(
        region: String,
        queueURL: String,
        resultsQueueURL: String,
        eventKit: any EventKitOperations,
        loopGuard: LoopGuard,
        logger: Logger
    ) async throws {
        self.client = SQSClient(config: try await SQSClient.SQSClientConfig(region: region))
        self.queueURL = queueURL
        self.resultsQueueURL = resultsQueueURL
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
            let input = ReceiveMessageInput(
                maxNumberOfMessages: 10,
                messageSystemAttributeNames: [.approximatereceivecount],
                queueUrl: queueURL,
                waitTimeSeconds: 20
            )
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
        let command: WriteCommand
        do {
            command = try decoder.decode(WriteCommand.self, from: Data(body.utf8))
        } catch {
            // Malformed command: nothing to apply or report; leave it to redrive to the DLQ.
            logger.error("undecodable write command (left for DLQ): \(error)")
            return
        }

        if let known = appliedCommands[command.commandId] {
            logger.info("duplicate command \(command.commandId) — re-publishing result only")
            await finish(command: command, entityId: known.entityId, receiptHandle: receiptHandle)
            return
        }

        do {
            let entityId = try await eventKit.apply(command: command)
            await loopGuard.suppress(entityId)
            rememberApplied(command.commandId, entityId: entityId)
            await finish(command: command, entityId: entityId, receiptHandle: receiptHandle)
            logger.info("applied \(command.commandType.rawValue) \(command.operation.rawValue) -> \(entityId)")
        } catch {
            logger.error("failed to apply write command \(command.commandId): \(error)")
            let receiveCount = Int(message.attributes?["ApproximateReceiveCount"] ?? "") ?? 1
            if receiveCount >= Self.maxReceiveCount {
                // Last attempt before redrive: report the terminal failure to the Core (CA-20).
                await publishResult(WriteCommandResult(
                    commandId: command.commandId,
                    status: .failed,
                    operation: command.operation,
                    entityId: command.entityId,
                    error: String(describing: error)
                ))
            }
        }
    }

    /// Publishes the APPLIED result and deletes the message. If publishing fails, the message is
    /// kept so the next delivery retries the result (the applied-commands memo prevents a
    /// double write to EventKit).
    private func finish(command: WriteCommand, entityId: String, receiptHandle: String) async {
        let published = await publishResult(WriteCommandResult(
            commandId: command.commandId,
            status: .applied,
            operation: command.operation,
            entityId: entityId
        ))
        guard published else { return }
        do {
            try await deleteMessage(receiptHandle)
        } catch {
            logger.error("failed to delete applied command \(command.commandId): \(error)")
        }
    }

    @discardableResult
    private func publishResult(_ result: WriteCommandResult) async -> Bool {
        do {
            let body = String(decoding: try encoder.encode(result), as: UTF8.self)
            let dedupSuffix = result.status == .failed ? "-FAILED" : ""
            let input = SendMessageInput(
                messageBody: body,
                messageDeduplicationId: result.commandId.uuidString + dedupSuffix,
                messageGroupId: result.commandId.uuidString,
                queueUrl: resultsQueueURL
            )
            _ = try await client.sendMessage(input: input)
            return true
        } catch {
            logger.error("failed to publish WriteCommandResult \(result.commandId): \(error)")
            return false
        }
    }

    private func rememberApplied(_ commandId: UUID, entityId: String) {
        let now = Date()
        appliedCommands[commandId] = (entityId, now)
        appliedCommands = appliedCommands.filter { now.timeIntervalSince($0.value.appliedAt) < Self.dedupWindow }
    }

    private func deleteMessage(_ receiptHandle: String) async throws {
        _ = try await client.deleteMessage(input: DeleteMessageInput(queueUrl: queueURL, receiptHandle: receiptHandle))
    }
}
