import Foundation

/// Resolves the hostname the REST API binds to (RNF-09: only reachable over the tailnet).
///
/// Order: `SENTINEL_HOSTNAME` env override → first IPv4 in the Tailscale CGNAT range
/// (100.64.0.0/10) on any interface → loopback. Never 0.0.0.0: if Tailscale is down the
/// REST API degrades to loopback while the SQS pipeline keeps working.
enum BindAddress {
    static let loopback = "127.0.0.1"

    /// The resolved bind hostname and whether it is the loopback fallback (Tailscale not found).
    struct Resolution: Equatable {
        let hostname: String
        let isFallback: Bool
    }

    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        interfaceAddresses: [String]? = nil
    ) -> Resolution {
        if let override = environment["SENTINEL_HOSTNAME"], !override.isEmpty {
            return Resolution(hostname: override, isFallback: false)
        }
        let candidates = interfaceAddresses ?? systemIPv4Addresses()
        if let tailscale = candidates.first(where: isTailscaleAddress) {
            return Resolution(hostname: tailscale, isFallback: false)
        }
        return Resolution(hostname: loopback, isFallback: true)
    }

    /// True for IPv4 addresses in the Tailscale CGNAT range 100.64.0.0/10.
    static func isTailscaleAddress(_ address: String) -> Bool {
        let octets = address.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4, octets[0] == 100 else { return false }
        return (64...127).contains(octets[1])
    }

    private static func systemIPv4Addresses() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var addresses: [String] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let sa = entry.pointee.ifa_addr, sa.pointee.sa_family == sa_family_t(AF_INET) else {
                continue
            }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len),
                           &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let bytes = host.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
                addresses.append(String(decoding: bytes, as: UTF8.self))
            }
        }
        return addresses
    }
}
