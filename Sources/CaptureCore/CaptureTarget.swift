import Foundation

/// Where the extension connects to Hotline: a loopback address and port (the
/// normal way, Hotline's `listen.intercept`), or a socket file, which is for
/// testing with a stand-in listener. Written as one text: "127.0.0.1:8444",
/// or an absolute path such as "/Users/me/capture/capture.sock".
public enum CaptureTarget: Equatable {
    case tcp(CaptureAddress)
    case unix(path: String)

    public enum SocketFolderError: Error, Equatable {
        case missing
        case notOwned
        case openToOthers
    }

    public init(parsing text: String) throws {
        if text.hasPrefix("/") {
            try CaptureTarget.checkFolder(of: text, owner: getuid())
            self = .unix(path: text)
        } else {
            self = .tcp(try CaptureAddress(parsing: text))
        }
    }

    /// The target as it is passed on.
    public var text: String {
        switch self {
        case .tcp(let address): return address.text
        case .unix(let path): return path
        }
    }

    /// A socket file must sit in a folder owned by `owner` and closed to
    /// everyone else (mode 0700): otherwise other users could take its place.
    static func checkFolder(of path: String, owner: uid_t) throws {
        let folder = (path as NSString).deletingLastPathComponent
        var info = stat()
        guard stat(folder, &info) == 0 else { throw SocketFolderError.missing }
        guard info.st_uid == owner else { throw SocketFolderError.notOwned }
        guard info.st_mode & 0o077 == 0 else { throw SocketFolderError.openToOthers }
    }
}
