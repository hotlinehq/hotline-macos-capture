import XCTest
@testable import CaptureCore

final class CapturePathTests: XCTestCase {
    func testAbsolutePathIsAccepted() throws {
        let path = "/Users/peter/Library/Application Support/Hotline/capture.sock"
        XCTAssertEqual(try CapturePath(parsing: path).text, path)
    }

    func testPathOfExactlyTheLongestLengthIsAccepted() throws {
        let path = "/" + String(repeating: "a", count: CapturePath.maxBytes - 1)
        XCTAssertEqual(try CapturePath(parsing: path).text, path)
    }

    func testRelativePathIsRefused() {
        for text in ["", "capture.sock", "~/Library/capture.sock", "./capture.sock", "127.0.0.1:8080"] {
            XCTAssertThrowsError(try CapturePath(parsing: text), text) {
                XCTAssertEqual($0 as? CapturePath.ParseError, .notAbsolute, text)
            }
        }
    }

    func testPathLongerThanASocketFileCanHaveIsRefused() {
        let path = "/" + String(repeating: "a", count: CapturePath.maxBytes)
        XCTAssertThrowsError(try CapturePath(parsing: path)) {
            XCTAssertEqual($0 as? CapturePath.ParseError, .tooLong)
        }
    }

    func testLengthIsCountedInBytesNotCharacters() {
        // "é" takes two bytes, so 60 of them are 120 bytes.
        let path = "/" + String(repeating: "é", count: 60)
        XCTAssertThrowsError(try CapturePath(parsing: path)) {
            XCTAssertEqual($0 as? CapturePath.ParseError, .tooLong)
        }
    }

    func testPathWithAControlCharacterIsRefused() {
        for text in ["/tmp/a\u{0}b.sock", "/tmp/a\nb.sock", "/tmp/a\u{1b}b.sock"] {
            XCTAssertThrowsError(try CapturePath(parsing: text), text) {
                XCTAssertEqual($0 as? CapturePath.ParseError, .controlCharacter, text)
            }
        }
    }
}
