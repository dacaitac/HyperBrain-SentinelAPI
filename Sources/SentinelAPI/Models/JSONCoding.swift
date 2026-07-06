import Foundation

/// Thread-safe ISO-8601 coder. `ISO8601DateFormatter` is documented thread-safe, but is not
/// `Sendable`; the lock makes concurrent use explicit so it can be captured by the `@Sendable`
/// date strategy closures. Encodes with the local UTC offset; decodes offset or `Z` (UTC).
private final class ISO8601Coder: @unchecked Sendable {
    private let offset = ISO8601DateFormatter()
    private let utc = ISO8601DateFormatter()
    private let lock = NSLock()

    init() {
        offset.formatOptions = [.withInternetDateTime]
        offset.timeZone = .current
        utc.formatOptions = [.withInternetDateTime]
    }

    func string(from date: Date) -> String {
        lock.lock(); defer { lock.unlock() }
        return offset.string(from: date)
    }

    func date(from string: String) -> Date? {
        lock.lock(); defer { lock.unlock() }
        return offset.date(from: string) ?? utc.date(from: string)
    }
}

/// Shared JSON coders for the SentinelAPI wire contract: `snake_case` keys and ISO-8601
/// timestamps *with* timezone offset. Used for SQS message bodies and, via `ContentConfiguration`,
/// for the Vapor REST layer so both stay byte-compatible.
enum JSONCoding {
    private static let iso8601 = ISO8601Coder()

    static func makeEncoder() -> JSONEncoder {
        let coder = iso8601
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(coder.string(from: date))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let coder = iso8601
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = coder.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO-8601 date: \(string)"
                )
            }
            return date
        }
        return decoder
    }
}
