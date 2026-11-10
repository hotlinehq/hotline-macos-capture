import Foundation

/// Version of the messages to Hotline. Raise it when a message changes.
/// A message with a different version is refused.
public let captureProtocolVersion = 1

public enum Transport: String, Codable, Equatable {
    case tcp
    case udp
}

public enum Role: String, Codable, Equatable {
    /// The one long-lived connection on which Hotline sends the app list.
    case control
    /// A new connection for every captured connection.
    case flow
}

/// First message from the extension on every connection it opens.
public struct ClientHello: Codable, Equatable {
    public var version: Int
    public var role: Role
    // The fields below are set for role == .flow only.
    public var transport: Transport?
    public var host: String?
    public var port: UInt16?
    public var pid: UInt32?
    public var processName: String?

    public static func control() -> ClientHello {
        ClientHello(version: captureProtocolVersion, role: .control)
    }

    public static func flow(
        transport: Transport, host: String, port: UInt16, pid: UInt32, processName: String?
    ) -> ClientHello {
        ClientHello(
            version: captureProtocolVersion, role: .flow, transport: transport,
            host: host, port: port, pid: pid, processName: processName)
    }

    public init(
        version: Int, role: Role, transport: Transport? = nil, host: String? = nil,
        port: UInt16? = nil, pid: UInt32? = nil, processName: String? = nil
    ) {
        self.version = version
        self.role = role
        self.transport = transport
        self.host = host
        self.port = port
        self.pid = pid
        self.processName = processName
    }
}

/// Sent by Hotline on the control connection whenever the app list changes.
public struct SpecUpdate: Codable, Equatable {
    public var version: Int
    public var entries: [String]

    public init(entries: [String]) {
        self.version = captureProtocolVersion
        self.entries = entries
    }
}

public protocol Versioned {
    var version: Int { get }
}

extension ClientHello: Versioned {}
extension SpecUpdate: Versioned {}
