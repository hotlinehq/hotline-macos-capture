import Foundation

public enum FrameError: Error, Equatable {
    /// The announced size is over the limit. Treated as hostile: close the connection.
    case tooLarge(Int)
    /// The bytes are not a valid message.
    case malformed
    /// The message has a version this build does not know.
    case unsupportedVersion(Int)
}

/// Messages travel as: 4 bytes of size (big endian), then that many bytes of JSON.
public enum Framing {
    /// Messages are tiny. Anything bigger is refused (requirement 16).
    public static let maxFrameSize = 16 * 1024

    public static func encode<T: Encodable>(_ message: T) throws -> Data {
        let body = try JSONEncoder().encode(message)
        guard body.count <= maxFrameSize else { throw FrameError.tooLarge(body.count) }
        var size = UInt32(body.count).bigEndian
        var frame = Data(bytes: &size, count: 4)
        frame.append(body)
        return frame
    }
}

/// Collects bytes as they arrive and hands out whole messages.
public struct FrameDecoder {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) {
        buffer.append(data)
    }

    /// Bytes received but not yet used by a message. After the first message
    /// on a flow connection, these belong to the connection's own content.
    public var remainder: Data { buffer }

    /// Returns the next whole message, or nil when more bytes are needed.
    public mutating func next<T: Decodable & Versioned>(_ type: T.Type) throws -> T? {
        guard buffer.count >= 4 else { return nil }
        let size = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        guard size <= Framing.maxFrameSize else { throw FrameError.tooLarge(size) }
        guard buffer.count >= 4 + size else { return nil }
        let start = buffer.startIndex + 4
        let body = buffer[start..<(start + size)]
        buffer = Data(buffer[(start + size)...])
        let message: T
        do {
            message = try JSONDecoder().decode(T.self, from: body)
        } catch {
            throw FrameError.malformed
        }
        guard message.version == captureProtocolVersion else {
            throw FrameError.unsupportedVersion(message.version)
        }
        return message
    }
}
