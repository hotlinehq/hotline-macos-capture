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

/// The saved proxy setting of this app, if there is one.
func loadManager() async throws -> NETransparentProxyManager? {
    let managers = try await NETransparentProxyManager.loadAllFromPreferences()
    return managers.first(where: {
        ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == extensionIdentifier
    })
}

/// Switches capture off and waits, up to 5 seconds, until macOS says it is off.
func stopCapture(_ manager: NETransparentProxyManager) async {
    let status = manager.connection.status
    guard status != .disconnected, status != .invalid else { return }
    manager.connection.stopVPNTunnel()
    for _ in 0..<50 where manager.connection.status != .disconnected {
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
}

/// Saves the proxy setting, with Hotline's socket file and this run's app list
/// inside it, and switches capture on. Capture that is already on is
/// switched off first, so the extension reads the new list.
func startCapture(path: CapturePath, apps: [String]) async throws {
    let manager = try await loadManager() ?? NETransparentProxyManager()
    await stopCapture(manager)

    let provider = NETunnelProviderProtocol()
    provider.providerBundleIdentifier = extensionIdentifier
    provider.serverAddress = path.text
    provider.providerConfiguration = HelperCommand.setting(apps: apps)
    manager.protocolConfiguration = provider
    manager.localizedDescription = "Hotline Capture"
    manager.isEnabled = true

    try await manager.saveToPreferences()
    try await manager.loadFromPreferences()
    try manager.connection.startVPNTunnel()

    // The extension first checks that Hotline answers, and stops if not. Wait up to
    // 10 seconds to see which way it went, so Hotline can say why capture did not start.
    // The status may still read "disconnected" for a moment after the start, so a
    // "disconnected" counts as a failure only after the first second.
    for step in 0..<100 {
        let status = manager.connection.status
        if status == .connected || (status == .disconnected && step >= 10) {
            break
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
    guard manager.connection.status == .connected else {
        throw CaptureError.notStarted(path.text)
    }
}

enum CaptureError: LocalizedError {
    case notStarted(String)

    var errorDescription: String? {
        switch self {
        case .notStarted(let path):
            return "the extension did not start. Is Hotline listening on \(path)? "
                + "Details: log show --last 1m --predicate 'subsystem == \"io.github.petercipov.hotlinecapture\"'"
        }
    }
}

/// Switches capture off and leaves the setting switched off. The extension stays installed.
func stopCapture() async throws {
    guard let manager = try await loadManager() else { return }
    await stopCapture(manager)
    manager.isEnabled = false
    try await manager.saveToPreferences()
}

// Hotline starts this helper with its socket file for captured connections and the apps
// to capture, such as "/Users/me/Library/Application Support/Hotline/capture.sock" curl
// firefox, and with --stop when it stops.
let command: HelperCommand
do {
    command = try HelperCommand(arguments: Array(CommandLine.arguments.dropFirst()), callerPID: getppid())
} catch CapturePath.ParseError.notAbsolute {
    fail("Give the full path of Hotline's socket file, starting with /, such as /tmp/capture.sock.")
} catch CapturePath.ParseError.tooLong {
    fail("The path of Hotline's socket file is longer than \(CapturePath.maxBytes) bytes.")
} catch CapturePath.ParseError.controlCharacter {
    fail("The path of Hotline's socket file holds a control character.")
} catch HelperCommand.UsageError.noApps {
    fail("Name at least one app to capture after the path, such as /tmp/capture.sock curl.")
} catch {
    fail("Give Hotline's socket file and the apps to capture, such as /tmp/capture.sock curl, or --stop.")
}

Task {
    do {
        switch command {
        case .start(let path, let apps):
            try await Installer.run()
            try await startCapture(path: path, apps: apps)
        case .stop:
            try await stopCapture()
        }
        exit(0)
    } catch {
        fail("could not \(command == .stop ? "stop" : "start") capture: \(error.localizedDescription)")
    }
}
RunLoop.main.run()
