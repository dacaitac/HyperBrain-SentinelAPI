import Foundation
import Security

/// Minimal read-only wrapper over the macOS keychain (`Security.framework`).
///
/// AWS credentials are stored as generic-password items under the service
/// `com.hyperbrain.sentinelapi` and never written to disk in plaintext.
/// Import them once with, e.g.:
///
///     security add-generic-password -a AWS_ACCESS_KEY_ID -s com.hyperbrain.sentinelapi -w "<key>"
///     security add-generic-password -a AWS_SECRET_ACCESS_KEY -s com.hyperbrain.sentinelapi -w "<secret>"
enum Keychain {
    static let service = "com.hyperbrain.sentinelapi"

    enum KeychainError: Error, CustomStringConvertible {
        case notFound(account: String)
        case unexpectedStatus(OSStatus)

        var description: String {
            switch self {
            case .notFound(let account):
                return "Keychain item not found for account '\(account)' (service '\(service)')"
            case .unexpectedStatus(let status):
                return "Keychain access failed with OSStatus \(status)"
            }
        }
    }

    /// Reads a generic-password value for `account` under the SentinelAPI service.
    static func readString(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
                throw KeychainError.notFound(account: account)
            }
            return value
        case errSecItemNotFound:
            throw KeychainError.notFound(account: account)
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
