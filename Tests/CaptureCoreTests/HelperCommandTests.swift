import XCTest
@testable import CaptureCore

final class HelperCommandTests: XCTestCase {
    func testAddressAndAppsStartCaptureWithTheCallerSkipped() throws {
        let command = try HelperCommand(arguments: ["127.0.0.1:8080", "curl", "firefox"], callerPID: 55)
        XCTAssertEqual(
            command,
            .start(address: try CaptureAddress(parsing: "127.0.0.1:8080"), apps: ["curl", "firefox", "!55"]))
    }

    func testStopNeedsNothingElse() throws {
        XCTAssertEqual(try HelperCommand(arguments: ["--stop"], callerPID: 55), .stop)
    }

    func testStopWithMoreArgumentsIsRefused() {
        XCTAssertThrowsError(try HelperCommand(arguments: ["--stop", "curl"], callerPID: 55)) {
            XCTAssertEqual($0 as? HelperCommand.UsageError, .usage)
        }
    }

    func testAddressWithoutAppsIsRefused() {
        XCTAssertThrowsError(try HelperCommand(arguments: ["127.0.0.1:8080"], callerPID: 55)) {
            XCTAssertEqual($0 as? HelperCommand.UsageError, .noApps)
        }
    }

    func testBlankAppsCountAsNone() {
        XCTAssertThrowsError(try HelperCommand(arguments: ["127.0.0.1:8080", " ", "!"], callerPID: 55)) {
            XCTAssertEqual($0 as? HelperCommand.UsageError, .noApps)
        }
    }

    func testNoArgumentsIsRefused() {
        XCTAssertThrowsError(try HelperCommand(arguments: [], callerPID: 55)) {
            XCTAssertEqual($0 as? HelperCommand.UsageError, .usage)
        }
    }

    func testAddressOffThisMacIsRefused() {
        XCTAssertThrowsError(try HelperCommand(arguments: ["10.0.0.1:8080", "curl"], callerPID: 55)) {
            XCTAssertEqual($0 as? CaptureAddress.ParseError, .notLoopback)
        }
    }

    func testAppListIsReadBackFromTheProxySetting() {
        let setting = HelperCommand.setting(apps: ["curl", "!55"])
        XCTAssertEqual(HelperCommand.apps(fromSetting: setting), ["curl", "!55"])
    }

    func testProxySettingWithoutAListGivesNoApps() {
        XCTAssertEqual(HelperCommand.apps(fromSetting: nil), [])
        XCTAssertEqual(HelperCommand.apps(fromSetting: ["apps": "curl"]), [])
    }
}
