import Foundation

/// The request the extension sends to Hotline's proxy port for one captured
/// connection: a standard HTTP CONNECT to where the app really called, with
/// three headers of ours that say it was captured and which program made it.
/// The contract is in docs/protocol.md.
public struct ConnectRequest: Equatable {
    /// The version in the Hotline-Capture header. Raise it when the headers change.
    public static let captureVersion = 1
    /// Longer program paths are left out rather than cut, so a record never
    /// names a wrong program. Hotline has the same limit.
    public static let maxProgramLength = 4096
    private static let maxHostLength = 253

    public enum RequestError: Error, Equatable {
        case badHost
        case badPort
    }

    public let host: String
    public let port: UInt16
    public let pid: UInt32
    /// The program path, or nil when it is not known or could not be sent safely.
    public let program: String?

    public init(host: String, port: UInt16, pid: UInt32, program: String?) throws {
        guard ConnectRequest.isHost(host) else { throw RequestError.badHost }
        guard port > 0 else { throw RequestError.badPort }
        self.host = host
        self.port = port
        self.pid = pid
        self.program = program.flatMap { ConnectRequest.isSafeHeaderValue($0) ? $0 : nil }
    }

    /// The request as it goes on the wire.
    public var bytes: Data {
        let authority = host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
        var text = "CONNECT \(authority) HTTP/1.1\r\n"
        text += "Host: \(authority)\r\n"
        text += "Hotline-Capture: \(ConnectRequest.captureVersion)\r\n"
        text += "Hotline-Capture-Pid: \(pid)\r\n"
        if let program = program {
            text += "Hotline-Capture-Program: \(program)\r\n"
        }
        text += "\r\n"
        return Data(text.utf8)
    }

    /// A name or an address: letters, digits, dots, dashes, underscores, and
    /// colons for IPv6. Anything else could break the request line.
    private static func isHost(_ host: String) -> Bool {
        guard !host.isEmpty, host.utf8.count <= maxHostLength else { return false }
        return host.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII
                && (CharacterSet.alphanumerics.contains(scalar) || ".-_:".unicodeScalars.contains(scalar))
        }
    }

    /// A header value must not hold a line break or another control
    /// character, or it could end the header and start a made-up one.
    private static func isSafeHeaderValue(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= maxProgramLength else { return false }
        return value.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7f }
    }
}

/// Reads Hotline's answer to a CONNECT. Hotline answers with a status line
/// and headers, ending with an empty line; after that, the bytes belong to
/// the app's connection.
public struct ConnectReply {
    /// The most the answer may take. Hotline's answer is far smaller; a
    /// longer one is not from Hotline.
    public static let maxSize = 8 * 1024

    public enum ReplyError: Error, Equatable {
        case tooLarge
        case notHTTP
        case refused(status: Int)
    }

    private var buffer: [UInt8] = []
    private static let end: [UInt8] = Array("\r\n\r\n".utf8)

    public init() {}

    /// Adds bytes from Hotline. Returns nil while the answer is not complete,
    /// and the bytes that came after it once it is complete and says yes.
    /// Throws when the answer is too long, not HTTP, or a refusal.
    public mutating func append(_ data: Data) throws -> Data? {
        buffer.append(contentsOf: data)
        guard let endIndex = ConnectReply.find(ConnectReply.end, in: buffer) else {
            if buffer.count > ConnectReply.maxSize { throw ReplyError.tooLarge }
            return nil
        }
        let headEnd = endIndex + ConnectReply.end.count
        guard headEnd <= ConnectReply.maxSize else { throw ReplyError.tooLarge }

        let lineEnd = ConnectReply.find(Array("\r\n".utf8), in: buffer) ?? endIndex
        let statusLine = String(decoding: buffer[..<lineEnd], as: UTF8.self)
        let parts = statusLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2, parts[0] == "HTTP/1.1" || parts[0] == "HTTP/1.0",
            parts[1].count == 3, let status = Int(parts[1])
        else { throw ReplyError.notHTTP }
        // Any 2xx status means the tunnel is open (RFC 9110, CONNECT).
        guard (200...299).contains(status) else { throw ReplyError.refused(status: status) }
        return Data(buffer[headEnd...])
    }

    private static func find(_ needle: [UInt8], in haystack: [UInt8]) -> Int? {
        guard haystack.count >= needle.count else { return nil }
        for start in 0...(haystack.count - needle.count)
        where haystack[start..<(start + needle.count)].elementsEqual(needle) {
            return start
        }
        return nil
    }
}
