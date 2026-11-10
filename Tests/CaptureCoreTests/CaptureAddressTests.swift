import XCTest
@testable import CaptureCore

final class CaptureAddressTests: XCTestCase {
    func testIPv4LoopbackWithPortIsAccepted() throws {
        let address = try CaptureAddress(parsing: "127.0.0.1:8444")
        XCTAssertEqual(address.host, "127.0.0.1")
        XCTAssertEqual(address.port, 8444)
    }

    func testAnotherIPv4LoopbackAddressIsAccepted() throws {
        XCTAssertEqual(try CaptureAddress(parsing: "127.5.5.5:1").host, "127.5.5.5")
    }

    func testLocalhostIsAcceptedInAnyCase() throws {
        XCTAssertEqual(try CaptureAddress(parsing: "LocalHost:9").host, "localhost")
    }

    func testIPv6LoopbackInBracketsIsAccepted() throws {
        let address = try CaptureAddress(parsing: "[::1]:8444")
        XCTAssertEqual(address.host, "::1")
        XCTAssertEqual(address.port, 8444)
    }

    func testTextIsWrittenBackWithBracketsForIPv6() throws {
        XCTAssertEqual(try CaptureAddress(parsing: "[::1]:8444").text, "[::1]:8444")
        XCTAssertEqual(try CaptureAddress(parsing: "127.0.0.1:8444").text, "127.0.0.1:8444")
    }

    func testAddressOthersCouldReachIsRefused() {
        for text in ["0.0.0.0:8444", "10.0.0.5:8444", "proxy.example.com:8444", "[::]:8444", "128.0.0.1:8444", "127.0.0.1.5:8444"] {
            XCTAssertThrowsError(try CaptureAddress(parsing: text), text) {
                XCTAssertEqual($0 as? CaptureAddress.ParseError, .notLoopback, text)
            }
        }
    }

    func testEmptyHostIsRefused() {
        XCTAssertThrowsError(try CaptureAddress(parsing: ":8444")) {
            XCTAssertEqual($0 as? CaptureAddress.ParseError, .notLoopback)
        }
    }

    func testTextThatIsNotHostAndPortIsRefused() {
        for text in ["nonsense", "", "127.0.0.1", "::1:8444", "[::1]8444", "[::1"] {
            XCTAssertThrowsError(try CaptureAddress(parsing: text), text) {
                XCTAssertEqual($0 as? CaptureAddress.ParseError, .notHostAndPort, text)
            }
        }
    }

    func testPortOutOfRangeIsRefused() {
        for text in ["127.0.0.1:0", "127.0.0.1:65536", "127.0.0.1:-1", "127.0.0.1:http"] {
            XCTAssertThrowsError(try CaptureAddress(parsing: text), text) {
                XCTAssertEqual($0 as? CaptureAddress.ParseError, .badPort, text)
            }
        }
    }
}
