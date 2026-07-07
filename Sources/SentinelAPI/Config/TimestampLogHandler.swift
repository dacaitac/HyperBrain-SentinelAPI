import Foundation
import Vapor

/// `LogHandler` that prefixes every line with an ISO-8601 UTC timestamp so the LaunchAgent
/// stdout log can be correlated with the Core's logs (the stock Vapor console handler emits
/// no timestamps, which makes production forensics blind).
///
/// Lines are written with a single unbuffered `write(2)` so LaunchAgent file redirection
/// never lags behind the event.
struct TimestampLogHandler: LogHandler {
    let label: String
    var logLevel: Logger.Level = .info
    var metadata: Logger.Metadata = [:]

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(event: LogEvent) {
        emit(level: event.level, message: event.message, explicit: event.metadata)
    }

    func log(level: Logger.Level, message: Logger.Message, metadata explicit: Logger.Metadata?,
             source: String, file: String, function: String, line: UInt) {
        emit(level: level, message: message, explicit: explicit)
    }

    private func emit(level: Logger.Level, message: Logger.Message, explicit: Logger.Metadata?) {
        let merged = self.metadata.merging(explicit ?? [:]) { _, new in new }
        let entry = Self.render(timestamp: Date(), level: level, message: "\(message)", metadata: merged)
        let bytes = Array(entry.utf8)
        bytes.withUnsafeBytes { _ = write(STDOUT_FILENO, $0.baseAddress, $0.count) }
    }

    /// Renders one log line; extracted so the format is unit-testable.
    static func render(timestamp: Date, level: Logger.Level, message: String,
                       metadata: Logger.Metadata) -> String {
        let suffix = metadata.isEmpty
            ? ""
            : " [" + metadata.sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ") + "]"
        let time = timestamp.formatted(.iso8601)
        return "\(time) [ \(level.rawValue.uppercased()) ] \(message)\(suffix)\n"
    }
}
