import Foundation
import Logging

/// Sink for change events detected by `ChangeMonitor`. The production sink is `SQSPublisher`;
/// `LoggingEventPublisher` is a dependency-free sink for local testing (no AWS).
protocol EventPublisher: Sendable {
    func publish(_ event: AppleEntityChangedEvent) async throws
}

extension SQSPublisher: EventPublisher {}

/// Local-test sink: logs the detected change as contract JSON instead of sending it to SQS.
/// Lets you verify EventKit detection on a dev machine with no AWS credentials or queues.
struct LoggingEventPublisher: EventPublisher {
    private let logger: Logger
    private let encoder = JSONCoding.makeEncoder()

    init(logger: Logger) {
        self.logger = logger
    }

    func publish(_ event: AppleEntityChangedEvent) async throws {
        let json = String(decoding: try encoder.encode(event), as: UTF8.self)
        logger.info("LOCAL TEST — would publish to sync-events.fifo: \(json)")
    }
}
