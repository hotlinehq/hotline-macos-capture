import XCTest
@testable import CaptureCore

final class InterceptSpecTests: XCTestCase {
    private let curl = ProcessIdentity(pid: 100, path: "/usr/bin/curl")
    private let firefox = ProcessIdentity(pid: 200, path: "/Applications/Firefox.app/Contents/MacOS/firefox")
    private let hotline = ProcessIdentity(pid: 300, path: "/usr/local/bin/hotline")

    func testEmptyListCapturesNothing() {
        let spec = InterceptSpec(parsing: [])
        XCTAssertFalse(spec.shouldIntercept(curl))
    }

    func testNameCapturesOnlyThatProgram() {
        let spec = InterceptSpec(parsing: ["curl"])
        XCTAssertTrue(spec.shouldIntercept(curl))
        XCTAssertFalse(spec.shouldIntercept(firefox))
    }

    func testProcessNumberCapturesOnlyThatProcess() {
        let spec = InterceptSpec(parsing: ["200"])
        XCTAssertTrue(spec.shouldIntercept(firefox))
        XCTAssertFalse(spec.shouldIntercept(curl))
    }

    func testSeveralNames() {
        let spec = InterceptSpec(parsing: ["curl", "firefox"])
        XCTAssertTrue(spec.shouldIntercept(curl))
        XCTAssertTrue(spec.shouldIntercept(firefox))
        XCTAssertFalse(spec.shouldIntercept(hotline))
    }

    func testLeadingSkipRuleMeansCaptureEverythingElse() {
        let spec = InterceptSpec(parsing: ["!300"])
        XCTAssertTrue(spec.shouldIntercept(curl))
        XCTAssertTrue(spec.shouldIntercept(firefox))
        XCTAssertFalse(spec.shouldIntercept(hotline))
    }

    func testSkipAfterIncludeRemovesThatProgram() {
        let spec = InterceptSpec(parsing: ["firefox", "!200"])
        XCTAssertFalse(spec.shouldIntercept(firefox))
    }

    func testProcessWithoutPathMatchesOnlyByNumber() {
        let unknown = ProcessIdentity(pid: 400, path: nil)
        XCTAssertFalse(InterceptSpec(parsing: ["curl"]).shouldIntercept(unknown))
        XCTAssertTrue(InterceptSpec(parsing: ["400"]).shouldIntercept(unknown))
    }

    func testBlankAndBareBangEntriesAreIgnored() {
        let spec = InterceptSpec(parsing: ["", " ", "!", "curl"])
        XCTAssertEqual(spec.entries, ["curl"])
    }

    func testEntriesRoundTrip() {
        let entries = ["curl", "!300", "42"]
        XCTAssertEqual(InterceptSpec(parsing: entries).entries, entries)
    }
}
