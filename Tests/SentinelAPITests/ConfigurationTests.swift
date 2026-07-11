import Foundation
import Testing
@testable import SentinelAPI

/// `AppConfiguration.load` coverage for the `USER_COMMANDS_QUEUE_URL` variable (HU-01b).
@Suite("AppConfiguration — user-commands queue")
struct ConfigurationTests {

    /// Stubbed keychain reader: unit tests must never hit the real keychain — on a machine where
    /// the `com.hyperbrain.sentinelapi` item exists, `SecItemCopyMatching` blocks the unsigned
    /// test binary on an authorization prompt.
    private func absentKeychain(_ account: String) throws -> String {
        throw Keychain.KeychainError.notFound(account: account)
    }

    private func load(_ environment: [String: String]) throws -> AppConfiguration {
        try AppConfiguration.load(environment: environment, readKeychain: absentKeychain)
    }

    /// Complete real-mode environment except `USER_COMMANDS_QUEUE_URL`. Credentials come from the
    /// env fallback (the keychain reader is stubbed as absent).
    private var baseEnvironment: [String: String] {
        [
            "AWS_ACCESS_KEY_ID": "test-access-key",
            "AWS_SECRET_ACCESS_KEY": "test-secret-key",
            "AWS_REGION": "us-east-1",
            "SYNC_EVENTS_QUEUE_URL": "https://sqs.us-east-1.amazonaws.com/000000000000/sync-events.fifo",
            "APPLE_COMMANDS_QUEUE_URL": "https://sqs.us-east-1.amazonaws.com/000000000000/apple-commands.fifo",
            "APPLE_COMMANDS_RESULTS_QUEUE_URL": "https://sqs.us-east-1.amazonaws.com/000000000000/apple-commands-results.fifo",
        ]
    }

    @Test("Real mode requires USER_COMMANDS_QUEUE_URL with a clear error")
    func realModeRequiresQueueURL() {
        do {
            _ = try load(baseEnvironment)
            Issue.record("expected load to fail without USER_COMMANDS_QUEUE_URL")
        } catch {
            #expect(String(describing: error).contains("USER_COMMANDS_QUEUE_URL"))
        }
    }

    @Test("Real mode loads the user-commands queue URL when present")
    func realModeLoadsQueueURL() throws {
        var environment = baseEnvironment
        let url = "https://sqs.us-east-1.amazonaws.com/000000000000/user-commands.fifo"
        environment["USER_COMMANDS_QUEUE_URL"] = url

        let config = try load(environment)
        #expect(config.userCommandsQueueURL == url)
    }

    @Test("Local-test mode does not require USER_COMMANDS_QUEUE_URL")
    func localTestModeOptional() throws {
        var environment = baseEnvironment
        environment["SENTINEL_LOCAL_TEST"] = "true"

        let config = try load(environment)
        #expect(config.userCommandsQueueURL.isEmpty)
    }
}
