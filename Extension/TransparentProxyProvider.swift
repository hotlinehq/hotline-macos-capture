import CaptureCore
import Foundation
import Network
import NetworkExtension
import OSLog

let log = Logger(subsystem: "io.github.petercipov.hotlinecapture", category: "extension")

enum ProviderError: Error {
    case socketPathMissing
}

/// macOS calls this class for every new outgoing connection on the Mac.
/// It only decides "capture or not" and copies bytes. It never reads or
/// changes what is inside a connection.
class TransparentProxyProvider: NETransparentProxyProvider {
    private var socketPath: String?
    private var control: NWConnection?
    private let specLock = NSLock()
    private var spec = InterceptSpec(parsing: [])  // empty: capture nothing

    // MARK: Start and stop

    override func startProxy(options: [String: Any]? = nil) async throws {
        guard let path = protocolConfiguration.serverAddress else {
            throw ProviderError.socketPathMissing
        }
        socketPath = path

        // 1. Open the control connection and say hello. Hotline answers with the app list.
        let control = NWConnection(to: .unix(path: path), using: .tcp)
        self.control = control
        try await control.establish()
        try await control.sendBytes(Framing.encode(ClientHello.control()))
        Task { await self.readSpecUpdates(from: control) }

        // 2. Ask macOS to hand us every outgoing connection. We then let go of the ones we do not want.
        let settings = NETransparentProxyNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.includedNetworkRules = [
            NENetworkRule(
                remoteNetwork: nil, remotePrefix: 0, localNetwork: nil, localPrefix: 0,
                protocol: .any, direction: .outbound)
        ]
        try await setTunnelNetworkSettings(settings)
        log.debug("capture started")
    }

    override func stopProxy(with reason: NEProviderStopReason) async {
        log.debug("capture stopped: \(String(describing: reason), privacy: .public)")
        control?.forceCancel()
    }

    private func readSpecUpdates(from control: NWConnection) async {
        var decoder = FrameDecoder()
        do {
            while let bytes = try await control.receiveBytes() {
                decoder.append(bytes)
                while let update = try decoder.next(SpecUpdate.self) {
                    specLock.lock()
                    spec = InterceptSpec(parsing: update.entries)
                    specLock.unlock()
                    log.debug("app list updated, \(update.entries.count, privacy: .public) entries")
                }
            }
            log.debug("control connection closed, stopping")
            cancelProxyWithError(nil)
        } catch {
            log.error("control connection failed: \(String(describing: error), privacy: .public)")
            control.forceCancel()
            cancelProxyWithError(error)
        }
    }

    // MARK: New connections

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        // Only secure web-style traffic over TCP for now. UDP stays with the system.
        guard let tcp = flow as? NEAppProxyTCPFlow else { return false }
        guard let process = ProcessLookup.identity(fromAuditToken: flow.metaData.sourceAppAuditToken) else {
            return false
        }

        specLock.lock()
        let wanted = spec.shouldIntercept(process)
        specLock.unlock()
        guard wanted else { return false }

        guard let remote = tcp.remoteEndpoint as? NWHostEndpoint, let port = UInt16(remote.port) else {
            return false
        }
        let hello = ClientHello.flow(
            transport: .tcp, host: remote.hostname, port: port, pid: process.pid,
            processName: process.path)

        guard let path = socketPath else { return false }
        Task {
            do {
                try await tcp.open(withLocalEndpoint: nil)
                let connection = NWConnection(to: .unix(path: path), using: .tcp)
                try await connection.establish()
                try await connection.sendBytes(Framing.encode(hello))
                Copier.run(flow: tcp, connection: connection)
            } catch {
                log.error("could not hand over a connection: \(String(describing: error), privacy: .public)")
                tcp.closeReadWithError(error)
                tcp.closeWriteWithError(error)
            }
        }
        return true
    }
}
