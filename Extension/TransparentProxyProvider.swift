import CaptureCore
import Foundation
import Network
import NetworkExtension
import OSLog

let log = Logger(subsystem: "io.github.petercipov.hotlinecapture", category: "extension")

enum ProviderError: Error {
    case addressMissing
    case addressRefused(String)
    case noApps
}

/// macOS calls this class for every new outgoing connection on the Mac.
/// It only decides "capture or not" and copies bytes. It never reads or
/// changes what is inside a connection.
class TransparentProxyProvider: NETransparentProxyProvider {
    private var address: CaptureAddress?
    private var spec = InterceptSpec(parsing: [])  // empty: capture nothing
    private var watch: HotlineWatch?

    /// A TCP connection to Hotline's proxy port.
    /// The release version, read from the extension's own Info.plist, for the User-Agent.
    static let appVersion =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    static func connection(to address: CaptureAddress) -> NWConnection {
        NWConnection(
            host: NWEndpoint.Host(address.host), port: NWEndpoint.Port(rawValue: address.port)!,
            using: .tcp)
    }

    // MARK: Start and stop

    override func startProxy(options: [String: Any]? = nil) async throws {
        guard let configuration = protocolConfiguration as? NETunnelProviderProtocol,
            let text = configuration.serverAddress
        else {
            throw ProviderError.addressMissing
        }
        // The app already checked this; check again, since the setting could have been changed.
        let address: CaptureAddress
        do {
            address = try CaptureAddress(parsing: text)
        } catch {
            throw ProviderError.addressRefused(text)
        }
        // The app list for this run, written by the helper app. It is read only here:
        // a new list means a restart of capture.
        let spec = InterceptSpec(
            parsing: HelperCommand.apps(fromSetting: configuration.providerConfiguration))
        guard !spec.actions.isEmpty else { throw ProviderError.noApps }
        self.address = address
        self.spec = spec

        // Fail now, with a clear error for the helper app, when Hotline is not listening.
        let probe = Self.connection(to: address)
        try await probe.establish()
        probe.cancel()
        let watch = HotlineWatch(address: address)
        watch.start()
        self.watch = watch

        // Ask macOS to hand us every outgoing connection. We then let go of the ones we do not want.
        let settings = NETransparentProxyNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.includedNetworkRules = [
            NENetworkRule(
                remoteNetwork: nil, remotePrefix: 0, localNetwork: nil, localPrefix: 0,
                protocol: .any, direction: .outbound)
        ]
        // Never hand over connections to this Mac itself: that includes our own connections to
        // Hotline, which would otherwise loop when everything is captured.
        settings.excludedNetworkRules = [
            NENetworkRule(
                remoteNetwork: NWHostEndpoint(hostname: "127.0.0.0", port: "0"), remotePrefix: 8,
                localNetwork: nil, localPrefix: 0, protocol: .any, direction: .outbound),
            NENetworkRule(
                remoteNetwork: NWHostEndpoint(hostname: "::1", port: "0"), remotePrefix: 128,
                localNetwork: nil, localPrefix: 0, protocol: .any, direction: .outbound),
        ]
        try await setTunnelNetworkSettings(settings)
        log.debug("capture started, \(spec.actions.count, privacy: .public) entries in the app list")
    }

    override func stopProxy(with reason: NEProviderStopReason) async {
        log.debug("capture stopped: \(String(describing: reason), privacy: .public)")
        watch?.stop()
    }

    // MARK: New connections

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        // Only TCP for now. UDP stays with the system.
        guard let tcp = flow as? NEAppProxyTCPFlow, let address = address, let watch = watch else {
            return false
        }
        // While Hotline does not answer, every call goes out as usual instead of failing.
        guard watch.answers else { return false }
        guard let process = ProcessLookup.identity(fromAuditToken: flow.metaData.sourceAppAuditToken),
            spec.shouldIntercept(process)
        else { return false }
        guard let remote = tcp.remoteEndpoint as? NWHostEndpoint, let port = UInt16(remote.port),
            let request = try? ConnectRequest(
                host: remote.hostname, port: port, pid: process.pid, program: process.path,
                agentVersion: Self.appVersion)
        else { return false }

        Task {
            let connection = Self.connection(to: address)
            do {
                try await tcp.open(withLocalEndpoint: nil)
                try await connection.establish()
                try await connection.sendBytes(request.bytes)
                let rest = try await connection.readConnectReply()
                if !rest.isEmpty {
                    try await tcp.writeBytes(rest)
                }
                Copier.run(flow: tcp, connection: connection)
            } catch {
                log.error("could not hand over a connection: \(String(describing: error), privacy: .public)")
                connection.cancel()
                tcp.closeReadWithError(error)
                tcp.closeWriteWithError(error)
            }
        }
        return true
    }
}
