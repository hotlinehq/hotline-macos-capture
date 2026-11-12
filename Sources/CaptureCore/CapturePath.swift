import Foundation

/// The socket file Hotline listens on for captured connections (its
/// `listen.capture` setting), which the extension connects to. A socket
/// file is a connection point in the file system: only programs on this
/// Mac can reach it, and only Hotline's own user and root, as the extension
/// runs, can open it, so Hotline believes the capture headers there.
public struct CapturePath: Equatable {
    public enum ParseError: Error, Equatable {
        case notAbsolute
        case tooLong
        case controlCharacter
    }

    /// macOS keeps at most 104 bytes for the path of a socket file, the
    /// last one ending it.
    public static let maxBytes = 103

    public let text: String

    public init(parsing text: String) throws {
        guard text.hasPrefix("/") else { throw ParseError.notAbsolute }
        guard text.utf8.count <= CapturePath.maxBytes else { throw ParseError.tooLong }
        guard !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ParseError.controlCharacter
        }
        self.text = text
    }
}
