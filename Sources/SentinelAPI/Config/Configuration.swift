import Foundation

/// Runtime configuration for SentinelAPI. Non-secret values come from environment
/// variables (set in the LaunchAgent plist); AWS credentials come from the macOS keychain.
///
/// SentinelAPI always targets **real AWS SQS** — there is no LocalStack path (ADR-001).
struct AppConfiguration: Sendable {
    let awsRegion: String
    /// `sync-events.fifo` — outbound Apple → Core change events.
    let syncEventsQueueURL: String
    /// `apple-commands.fifo` — inbound Core → Apple write commands.
    let appleCommandsQueueURL: String
    /// `apple-commands-results.fifo` — outbound write-command results (ADR-010).
    let appleCommandsResultsQueueURL: String
    /// `user-commands.fifo` — outbound user commands, iOS Shortcut → Core (HU-01b).
    let userCommandsQueueURL: String
    /// Tailscale hostname base URL the Core uses to reach the REST API (never a raw IP).
    let baseURL: String
    let credentials: AWSCredentials

    /// True when `SENTINEL_LOCAL_TEST=true`: detected changes are logged instead of published to
    /// SQS, the command consumer is disabled, and no AWS credentials or queue URLs are required.
    /// For verifying EventKit detection on a dev machine.
    static func isLocalTest(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["SENTINEL_LOCAL_TEST"] == "true"
    }

    /// False when `SENTINEL_CONSUMER_ENABLED=false`: publish to real SQS but do not consume
    /// `apple-commands.fifo`. Used to run the outbound half alone (e.g. before that queue exists).
    static func isConsumerEnabled(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["SENTINEL_CONSUMER_ENABLED"] != "false"
    }

    struct AWSCredentials: Sendable {
        let accessKeyID: String
        let secretAccessKey: String
    }

    enum ConfigurationError: Error, CustomStringConvertible {
        case missingEnv(String)

        var description: String {
            switch self {
            case .missingEnv(let key):
                return "Missing required environment variable '\(key)'"
            }
        }
    }

    /// Builds configuration from the process environment + keychain.
    /// Credentials fall back to `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` env vars only when
    /// the keychain item is absent (local bootstrap); production reads exclusively from the keychain.
    /// `readKeychain` is injectable so unit tests never touch the real keychain (on a dev machine
    /// `SecItemCopyMatching` can block on an authorization prompt for the unsigned test binary).
    static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        readKeychain: (String) throws -> String = Keychain.readString(account:)
    ) throws -> AppConfiguration {
        func require(_ key: String) throws -> String {
            guard let value = environment[key], !value.isEmpty else {
                throw ConfigurationError.missingEnv(key)
            }
            return value
        }

        let accessKeyID = (try? readKeychain("AWS_ACCESS_KEY_ID"))
            ?? environment["AWS_ACCESS_KEY_ID"]
        let secretAccessKey = (try? readKeychain("AWS_SECRET_ACCESS_KEY"))
            ?? environment["AWS_SECRET_ACCESS_KEY"]

        guard let accessKeyID, !accessKeyID.isEmpty else {
            throw ConfigurationError.missingEnv("AWS_ACCESS_KEY_ID (keychain or env)")
        }
        guard let secretAccessKey, !secretAccessKey.isEmpty else {
            throw ConfigurationError.missingEnv("AWS_SECRET_ACCESS_KEY (keychain or env)")
        }

        // The command queues are only needed when the command consumer runs.
        let appleCommandsQueueURL = isConsumerEnabled(environment)
            ? try require("APPLE_COMMANDS_QUEUE_URL")
            : (environment["APPLE_COMMANDS_QUEUE_URL"] ?? "")
        let appleCommandsResultsQueueURL = isConsumerEnabled(environment)
            ? try require("APPLE_COMMANDS_RESULTS_QUEUE_URL")
            : (environment["APPLE_COMMANDS_RESULTS_QUEUE_URL"] ?? "")

        // Required to publish user commands (HU-01b); optional only in local-test mode,
        // where LoggingUserCommandPublisher replaces the SQS publisher.
        let userCommandsQueueURL = isLocalTest(environment)
            ? (environment["USER_COMMANDS_QUEUE_URL"] ?? "")
            : try require("USER_COMMANDS_QUEUE_URL")

        return AppConfiguration(
            awsRegion: (environment["AWS_REGION"]).flatMap { $0.isEmpty ? nil : $0 } ?? "us-east-1",
            syncEventsQueueURL: try require("SYNC_EVENTS_QUEUE_URL"),
            appleCommandsQueueURL: appleCommandsQueueURL,
            appleCommandsResultsQueueURL: appleCommandsResultsQueueURL,
            userCommandsQueueURL: userCommandsQueueURL,
            baseURL: (environment["SENTINEL_API_BASE_URL"]).flatMap { $0.isEmpty ? nil : $0 } ?? "http://localhost:8080",
            credentials: AWSCredentials(accessKeyID: accessKeyID, secretAccessKey: secretAccessKey)
        )
    }
}
