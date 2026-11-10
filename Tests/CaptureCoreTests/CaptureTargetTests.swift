import XCTest
@testable import CaptureCore

final class CaptureTargetTests: XCTestCase {
    private var folder: String!

    override func setUpWithError() throws {
        folder = NSTemporaryDirectory() + "capture-target-" + UUID().uuidString
        try FileManager.default.createDirectory(
            atPath: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: folder)
    }

    func testHostAndPortIsATcpTarget() throws {
        XCTAssertEqual(
            try CaptureTarget(parsing: "127.0.0.1:8444"),
            .tcp(try CaptureAddress(parsing: "127.0.0.1:8444")))
    }

    func testPathStartingWithASlashInAPrivateFolderIsASocketFile() throws {
        let path = folder + "/capture.sock"
        XCTAssertEqual(try CaptureTarget(parsing: path), .unix(path: path))
    }

    func testTextIsWrittenBackAsGiven() throws {
        let path = folder + "/capture.sock"
        XCTAssertEqual(try CaptureTarget(parsing: path).text, path)
        XCTAssertEqual(try CaptureTarget(parsing: "[::1]:9").text, "[::1]:9")
    }

    func testTcpProblemsAreReported() {
        XCTAssertThrowsError(try CaptureTarget(parsing: "0.0.0.0:8444")) {
            XCTAssertEqual($0 as? CaptureAddress.ParseError, .notLoopback)
        }
    }

    func testFolderOpenToOthersIsRefused() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder)
        XCTAssertThrowsError(try CaptureTarget(parsing: folder + "/capture.sock")) {
            XCTAssertEqual($0 as? CaptureTarget.SocketFolderError, .openToOthers)
        }
    }

    func testFolderThatIsNotThereIsRefused() {
        XCTAssertThrowsError(try CaptureTarget(parsing: folder + "/gone/capture.sock")) {
            XCTAssertEqual($0 as? CaptureTarget.SocketFolderError, .missing)
        }
    }

    func testFolderOwnedBySomeoneElseIsRefused() {
        XCTAssertThrowsError(try CaptureTarget.checkFolder(of: folder + "/capture.sock", owner: getuid() &+ 1)) {
            XCTAssertEqual($0 as? CaptureTarget.SocketFolderError, .notOwned)
        }
    }

    func testFolderOwnedByTheCurrentUserWithMode0700IsAccepted() {
        XCTAssertNoThrow(try CaptureTarget.checkFolder(of: folder + "/capture.sock", owner: getuid()))
    }
}
