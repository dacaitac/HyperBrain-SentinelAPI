import AWSSQS
import Foundation
import Logging

/// Sink for user commands triggered from the REST layer (HU-01b). The production sink is
/// `CommandPublisher` (SQS); `LoggingUserCommandPublisher` is the dependency-free local-test sink,
/// mirroring the `EventPublisher` / `LoggingEventPublisher` pattern.
protocol UserCommandPublisher: Sendable {
    func publish(_ command: UserCommand) async throws
}

/// Publishes `UserCommand`s to `user-commands.fifo` (SentinelAPI → Core).
///
/// FIFO parameters per contract: `MessageGroupId = "user-commands"` (single global ordering
/// group — user commands are low-volume and strictly ordered), `MessageDeduplicationId =
/// command_id` (fresh UUID per request, `ContentBasedDeduplication=false`).
actor CommandPublisher: UserCommandPublisher {
    static let messageGroupId = "user-commands"

    private let client: SQSClient
    private let queueURL: String
    private let encoder = JSONCoding.makeEncoder()

    init(region: String, queueURL: String) async throws {
        self.client = SQSClient(config: try await SQSClient.SQSClientConfig(region: region))
        self.queueURL = queueURL
    }

    func publish(_ command: UserCommand) async throws {
        let body = String(decoding: try encoder.encode(command), as: UTF8.self)
        let input = SendMessageInput(
            messageBody: body,
            messageDeduplicationId: command.commandId.uuidString,
            messageGroupId: Self.messageGroupId,
            queueUrl: queueURL
        )
        _ = try await client.sendMessage(input: input)
    }
}

/// Local-test sink: logs the user command as contract JSON instead of sending it to SQS.
struct LoggingUserCommandPublisher: UserCommandPublisher {
    private let logger: Logger
    private let encoder = JSONCoding.makeEncoder()

    init(logger: Logger) {
        self.logger = logger
    }

    func publish(_ command: UserCommand) async throws {
        let json = String(decoding: try encoder.encode(command), as: UTF8.self)
        logger.info("LOCAL TEST — would publish to user-commands.fifo: \(json)")
    }
}
