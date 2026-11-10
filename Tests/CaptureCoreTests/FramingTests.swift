import XCTest
@testable import CaptureCore

final class FramingTests: XCTestCase {
    func testFlowHelloRoundTrip() throws {
        let hello = ClientHello.flow(
            transport: .tcp, host: "api.example.com", port: 443, pid: 42, processName: "/usr/bin/curl")
        var decoder = FrameDecoder()
        decoder.append(try Framing.encode(hello))
        XCTAssertEqual(try decoder.next(ClientHello.self), hello)
    }

    func testControlHelloRoundTrip() throws {
        var decoder = FrameDecoder()
        decoder.append(try Framing.encode(ClientHello.control()))
        let decoded = try decoder.next(ClientHello.self)
        XCTAssertEqual(decoded?.role, .control)
        XCTAssertNil(decoded?.host)
    }

    func testSpecUpdateRoundTrip() throws {
        let update = SpecUpdate(entries: ["curl", "!300"])
        var decoder = FrameDecoder()
        decoder.append(try Framing.encode(update))
        XCTAssertEqual(try decoder.next(SpecUpdate.self), update)
    }

    func testHalfAMessageWaitsForMoreBytes() throws {
        let frame = try Framing.encode(ClientHello.control())
        var decoder = FrameDecoder()
        decoder.append(frame.prefix(frame.count - 1))
        XCTAssertNil(try decoder.next(ClientHello.self))
        decoder.append(frame.suffix(1))
        XCTAssertNotNil(try decoder.next(ClientHello.self))
    }

    func testBytesAfterTheMessageStayAsRemainder() throws {
        var decoder = FrameDecoder()
        decoder.append(try Framing.encode(ClientHello.control()) + Data("GET /".utf8))
        _ = try decoder.next(ClientHello.self)
        XCTAssertEqual(decoder.remainder, Data("GET /".utf8))
    }

    func testOversizedAnnouncementIsRefusedBeforeReadingTheBody() {
        var decoder = FrameDecoder()
        decoder.append(Data([0x7F, 0xFF, 0xFF, 0xFF]))
        XCTAssertThrowsError(try decoder.next(ClientHello.self)) { error in
            guard case FrameError.tooLarge = error else { return XCTFail("wrong error: \(error)") }
        }
    }

    func testGarbageBodyIsMalformed() {
        var decoder = FrameDecoder()
        decoder.append(Data([0, 0, 0, 3]) + Data("abc".utf8))
        XCTAssertThrowsError(try decoder.next(ClientHello.self)) { error in
            XCTAssertEqual(error as? FrameError, .malformed)
        }
    }

    func testUnknownVersionIsRefused() throws {
        var hello = ClientHello.control()
        hello.version = captureProtocolVersion + 1
        var decoder = FrameDecoder()
        decoder.append(try Framing.encode(hello))
        XCTAssertThrowsError(try decoder.next(ClientHello.self)) { error in
            XCTAssertEqual(error as? FrameError, .unsupportedVersion(captureProtocolVersion + 1))
        }
    }

    func testTwoMessagesInOneChunk() throws {
        var decoder = FrameDecoder()
        decoder.append(try Framing.encode(SpecUpdate(entries: ["a"])) + Framing.encode(SpecUpdate(entries: ["b"])))
        XCTAssertEqual(try decoder.next(SpecUpdate.self)?.entries, ["a"])
        XCTAssertEqual(try decoder.next(SpecUpdate.self)?.entries, ["b"])
        XCTAssertNil(try decoder.next(SpecUpdate.self))
    }
}
