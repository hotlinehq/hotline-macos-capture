import Foundation

/// The address of Hotline's proxy port, which the extension connects to.
/// Hotline passes it as "host:port". It must be a loopback address: the
/// captured calls never leave this Mac, and Hotline believes the capture
/// headers only from this Mac.
public struct CaptureAddress: Equatable {
    public enum ParseError: Error, Equatable {
        case notHostAndPort
        case badPort
        case notLoopback
    }

    public let host: String
    public let port: UInt16

    public init(parsing text: String) throws {
        let hostPart: Substring
        let portPart: Substring
        if text.hasPrefix("[") {
            // IPv6 in brackets: "[::1]:8444".
            guard let close = text.firstIndex(of: "]"),
                text.index(after: close) < text.endIndex,
                text[text.index(after: close)] == ":"
            else { throw ParseError.notHostAndPort }
            hostPart = text[text.index(after: text.startIndex)..<close]
            portPart = text[text.index(close, offsetBy: 2)...]
        } else {
            guard let colon = text.lastIndex(of: ":") else { throw ParseError.notHostAndPort }
            hostPart = text[..<colon]
            portPart = text[text.index(after: colon)...]
            // A bare IPv6 address without brackets cannot be told from a port.
            guard !hostPart.contains(":") else { throw ParseError.notHostAndPort }
        }
        guard let port = UInt16(portPart), port > 0 else { throw ParseError.badPort }
        let host = hostPart.lowercased()
        guard CaptureAddress.isLoopback(host) else { throw ParseError.notLoopback }
        self.host = host
        self.port = port
    }

    /// The address as it is passed on: IPv6 in brackets.
    public var text: String {
        host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }

    private static func isLoopback(_ host: String) -> Bool {
        if host == "localhost" || host == "::1" { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "127" else { return false }
        return parts.allSatisfy { UInt8($0) != nil }
    }
}
