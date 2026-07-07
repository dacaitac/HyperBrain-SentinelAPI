import Foundation
import Logging
import Testing
@testable import SentinelAPI

@Suite("BindAddress resolution (RNF-09)")
struct BindAddressTests {
    @Test("SENTINEL_HOSTNAME overrides any interface detection")
    func environmentOverrideWins() {
        let resolution = BindAddress.resolve(
            environment: ["SENTINEL_HOSTNAME": "100.99.1.2"],
            interfaceAddresses: ["192.168.1.10"]
        )
        #expect(resolution == .init(hostname: "100.99.1.2", isFallback: false))
    }

    @Test("The first Tailscale CGNAT address is selected among the interfaces")
    func tailscaleAddressIsSelected() {
        let resolution = BindAddress.resolve(
            environment: [:],
            interfaceAddresses: ["127.0.0.1", "192.168.1.10", "100.74.180.105"]
        )
        #expect(resolution == .init(hostname: "100.74.180.105", isFallback: false))
    }

    @Test("Without a Tailscale interface the API degrades to loopback, never 0.0.0.0")
    func loopbackFallback() {
        let resolution = BindAddress.resolve(environment: [:], interfaceAddresses: ["192.168.1.10"])
        #expect(resolution == .init(hostname: "127.0.0.1", isFallback: true))
    }

    @Test("CGNAT range check covers exactly 100.64.0.0/10")
    func cgnatRangeBoundaries() {
        #expect(BindAddress.isTailscaleAddress("100.64.0.0"))
        #expect(BindAddress.isTailscaleAddress("100.127.255.255"))
        #expect(!BindAddress.isTailscaleAddress("100.63.255.255"))
        #expect(!BindAddress.isTailscaleAddress("100.128.0.0"))
        #expect(!BindAddress.isTailscaleAddress("10.64.0.1"))
        #expect(!BindAddress.isTailscaleAddress("not-an-ip"))
    }
}

@Suite("TimestampLogHandler format")
struct TimestampLogHandlerTests {
    @Test("Lines carry an ISO-8601 timestamp, the level and the metadata")
    func renderedLineFormat() {
        let timestamp = Date(timeIntervalSince1970: 1_780_000_000)
        let line = TimestampLogHandler.render(
            timestamp: timestamp, level: .warning, message: "poll failed",
            metadata: ["queue": "apple-commands"]
        )
        #expect(line == "2026-05-28T20:26:40Z [ WARNING ] poll failed [queue: apple-commands]\n")
    }

    @Test("Metadata-free lines have no trailing bracket block")
    func renderedLineWithoutMetadata() {
        let line = TimestampLogHandler.render(
            timestamp: Date(timeIntervalSince1970: 0), level: .info, message: "started", metadata: [:]
        )
        #expect(line == "1970-01-01T00:00:00Z [ INFO ] started\n")
    }
}
