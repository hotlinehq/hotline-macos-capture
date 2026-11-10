import CaptureCore
import Foundation
import NetworkExtension
import SystemExtensions
import OSLog

let log = Logger(subsystem: "io.github.petercipov.hotlinecapture", category: "app")
let extensionIdentifier = "io.github.petercipov.hotlinecapture.extension"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Hotline Capture: \(message)\n".utf8))
    exit(1)
}

/// Installs the system extension and waits for the result. The first time, macOS asks
/// the user to approve it in System Settings.
final class Installer: NSObject, OSSystemExtensionRequestDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    static func run() async throws {
        let installer = Installer()
        try await withCheckedThrowingContinuation { continuation in
            installer.continuation = continuation
            let request = OSSystemExtensionRequest.activationRequest(
                forExtensionWithIdentifier: extensionIdentifier, queue: .main)
            request.delegate = installer
            OSSystemExtensionManager.shared.submitRequest(request)
        }
    }

    func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        log.debug("replacing extension \(existing.bundleShortVersion, privacy: .public) with \(ext.bundleShortVersion, privacy: .public)")
        return .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        FileHandle.standardError.write(
            Data("Hotline Capture: approve the extension in System Settings, Privacy & Security.\n".utf8))
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        continuation?.resume(throwing: error)
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        continuation?.resume()
    }
}

/// Saves the proxy setting, with Hotline's address inside it, and switches it on.
func startProxy(target: CaptureTarget) async throws {
    let managers = try await NETransparentProxyManager.loadAllFromPreferences()
    let manager = managers.first(where: {
        ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == extensionIdentifier
    }) ?? NETransparentProxyManager()

    let provider = NETunnelProviderProtocol()
    provider.providerBundleIdentifier = extensionIdentifier
    provider.serverAddress = target.text
    manager.protocolConfiguration = provider
    manager.localizedDescription = "Hotline Capture"
    manager.isEnabled = true

    try await manager.saveToPreferences()
    try await manager.loadFromPreferences()
    try manager.connection.startVPNTunnel()
}

// The only argument is where Hotline listens: the address of its intercept port, such as
// 127.0.0.1:8444, or a socket file for testing, as sock:// and an absolute path.
guard CommandLine.arguments.count == 2 else {
    fail("This helper is started by Hotline and cannot be run on its own.")
}
let target: CaptureTarget
do {
    target = try CaptureTarget(parsing: CommandLine.arguments[1])
} catch CaptureAddress.ParseError.notLoopback {
    fail("The address must be on this Mac only, such as 127.0.0.1:8444.")
} catch CaptureTarget.ParseError.pathNotAbsolute {
    fail("After sock:// the path of the socket file must start with a slash, as in sock:///tmp/capture/capture.sock.")
} catch is CaptureTarget.SocketFolderError {
    fail("The folder of the socket file must exist, be owned by you and be closed to other users (mode 0700).")
} catch {
    fail("The argument must be an address and a port, such as 127.0.0.1:8444, or sock:// and the path of a socket file.")
}

Task {
    do {
        try await Installer.run()
        try await startProxy(target: target)
        exit(0)
    } catch {
        fail("could not start capture: \(error.localizedDescription)")
    }
}
RunLoop.main.run()
