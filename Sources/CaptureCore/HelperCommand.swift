import Foundation

/// What Hotline asks the helper app to do, read from its arguments:
///
/// - `<address> <app>...` starts capture of the apps, with Hotline's proxy
///   port at the address. The caller (Hotline) is always added as a skip
///   rule, so its own calls to vendors are never captured.
/// - `--stop` switches capture off.
public enum HelperCommand: Equatable {
    case start(address: CaptureAddress, apps: [String])
    case stop

    public enum UsageError: Error, Equatable {
        case usage
        case noApps
    }

    /// The key of the app list in the proxy setting the extension reads.
    static let appsKey = "apps"

    public init(arguments: [String], callerPID: Int32) throws {
        guard let first = arguments.first else { throw UsageError.usage }
        if first == "--stop" {
            guard arguments.count == 1 else { throw UsageError.usage }
            self = .stop
            return
        }
        let address = try CaptureAddress(parsing: first)
        let apps = arguments.dropFirst().filter { SpecAction($0) != nil }
        guard !apps.isEmpty else { throw UsageError.noApps }
        self = .start(address: address, apps: apps + ["!\(callerPID)"])
    }

    /// The app list as it is kept in the proxy setting.
    public static func setting(apps: [String]) -> [String: Any] {
        [appsKey: apps]
    }

    /// The app list from the proxy setting; none when it is missing or not a list.
    public static func apps(fromSetting setting: [String: Any]?) -> [String] {
        setting?[appsKey] as? [String] ?? []
    }
}
