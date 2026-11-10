import XCTest
@testable import CaptureCore

final class ConnectRequestTests: XCTestCase {
    private func text(_ request: ConnectRequest) -> String {
        String(decoding: request.bytes, as: UTF8.self)
    }

    func testRequestNamesTheDestinationAndTheProgram() throws {
        let request = try ConnectRequest(
            host: "93.184.215.14", port: 443, pid: 4242, program: "/usr/bin/curl")
        XCTAssertEqual(
            text(request),
            "CONNECT 93.184.215.14:443 HTTP/1.1\r\n"
                + "Host: 93.184.215.14:443\r\n"
                + "Hotline-Capture: 1\r\n"
                + "Hotline-Capture-Pid: 4242\r\n"
                + "Hotline-Capture-Program: /usr/bin/curl\r\n"
                + "\r\n")
    }

    func testIPv6DestinationIsWrittenInBrackets() throws {
        let request = try ConnectRequest(host: "2001:db8::1", port: 443, pid: 1, program: nil)
        XCTAssertTrue(
            text(request).hasPrefix("CONNECT [2001:db8::1]:443 HTTP/1.1\r\nHost: [2001:db8::1]:443\r\n"))
    }

    func testUnknownProgramLeavesOutItsHeader() throws {
        let request = try ConnectRequest(host: "a.example", port: 443, pid: 7, program: nil)
        XCTAssertFalse(text(request).contains("Hotline-Capture-Program"))
        XCTAssertTrue(text(request).contains("Hotline-Capture-Pid: 7\r\n"))
    }

    func testProgramPathWithSpacesAndLettersBeyondAsciiIsKept() throws {
        let path = "/Applications/Café App.app/Contents/MacOS/Café App"
        let request = try ConnectRequest(host: "a.example", port: 443, pid: 7, program: path)
        XCTAssertTrue(text(request).contains("Hotline-Capture-Program: \(path)\r\n"))
    }

    func testProgramPathThatCouldEndTheHeaderIsLeftOut() throws {
        let paths = ["/tmp/a\r\nHost: evil", "/tmp/a\nb", "/tmp/\u{7f}", String(repeating: "a", count: 4097)]
        for path in paths {
            let request = try ConnectRequest(host: "a.example", port: 443, pid: 7, program: path)
            XCTAssertFalse(text(request).contains("Hotline-Capture-Program"), path)
        }
    }

    func testDestinationThatIsNotAHostIsRefused() {
        for host in ["", "a b", "a/b", "a\r\nb", "a@b", String(repeating: "a", count: 254)] {
            XCTAssertThrowsError(try ConnectRequest(host: host, port: 443, pid: 1, program: nil), host) {
                XCTAssertEqual($0 as? ConnectRequest.RequestError, .badHost, host)
            }
        }
    }

    func testPortZeroIsRefused() {
        XCTAssertThrowsError(try ConnectRequest(host: "a.example", port: 0, pid: 1, program: nil)) {
            XCTAssertEqual($0 as? ConnectRequest.RequestError, .badPort)
        }
    }
}

final class ConnectReplyTests: XCTestCase {
    func testOkReplyGivesTheBytesThatCameAfterIt() throws {
        var reply = ConnectReply()
        XCTAssertNil(try reply.append(Data("HTTP/1.1 200 Connection established\r\n".utf8)))
        let rest = try reply.append(Data("Via: hotline\r\n\r\nTLS".utf8))
        XCTAssertEqual(rest, Data("TLS".utf8))
    }

    func testOkReplyWithNothingAfterItGivesNoBytes() throws {
        var reply = ConnectReply()
        XCTAssertEqual(try reply.append(Data("HTTP/1.0 200 OK\r\n\r\n".utf8)), Data())
    }

    func testRefusalIsReportedWithItsStatus() {
        var reply = ConnectReply()
        XCTAssertThrowsError(try reply.append(Data("HTTP/1.1 403 Forbidden\r\n\r\n".utf8))) {
            XCTAssertEqual($0 as? ConnectReply.ReplyError, .refused(status: 403))
        }
    }

    func testReplyThatIsNotHTTPIsRefused() {
        for text in ["SSH-2.0-OpenSSH\r\n\r\n", "HTTP/1.1 OK\r\n\r\n", "HTTP/2 200\r\n\r\n", "\r\n\r\n"] {
            var reply = ConnectReply()
            XCTAssertThrowsError(try reply.append(Data(text.utf8)), text) {
                XCTAssertEqual($0 as? ConnectReply.ReplyError, .notHTTP, text)
            }
        }
    }

    func testOversizedReplyIsRefusedBeforeItEnds() {
        var reply = ConnectReply()
        let long = Data(("HTTP/1.1 200 OK\r\n" + String(repeating: "a", count: ConnectReply.maxSize)).utf8)
        XCTAssertThrowsError(try reply.append(long)) {
            XCTAssertEqual($0 as? ConnectReply.ReplyError, .tooLarge)
        }
    }
}
