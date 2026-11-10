import Darwin
import Foundation
import CaptureCore

/// Finds which program made a connection, from the token macOS attaches to it.
enum ProcessLookup {
    // An audit token is eight 32-bit numbers. The sixth one (index 5) is the process number.
    private static let tokenSize = 8 * MemoryLayout<UInt32>.size
    private static let pidOffset = 5 * MemoryLayout<UInt32>.size

    private static var cache: [Data: ProcessIdentity] = [:]
    private static let lock = NSLock()

    static func identity(fromAuditToken token: Data?) -> ProcessIdentity? {
        guard let token = token, token.count == tokenSize else { return nil }

        lock.lock()
        defer { lock.unlock() }
        if let known = cache[token] { return known }

        let pid: UInt32 = token.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: pidOffset, as: UInt32.self)
        }

        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(Int32(pid), &buffer, UInt32(buffer.count))
        let path = length > 0 ? String(cString: buffer) : nil

        let identity = ProcessIdentity(pid: pid, path: path)
        cache[token] = identity
        return identity
    }
}
