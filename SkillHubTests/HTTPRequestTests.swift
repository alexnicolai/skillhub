import XCTest
@testable import SkillHub

final class HTTPRequestTests: XCTestCase {
    func testHeadersOnlyIsCompleteWithoutBody() {
        let raw = Data("GET /skills HTTP/1.1\r\nHost: 127.0.0.1:4477\r\nAccept: */*\r\n\r\n".utf8)
        let request = HTTPServer.Request.parse(raw)!
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.path, "/skills")
        XCTAssertEqual(request.headers["host"], "127.0.0.1:4477")
        XCTAssertTrue(request.isComplete)
        XCTAssertEqual(request.contentLength, 0)
    }

    func testBodyArrivingLaterIsIncompleteUntilContentLengthMet() {
        let head = "POST /skills HTTP/1.1\r\nHost: localhost\r\nContent-Length: 11\r\nExpect: 100-continue\r\n\r\n"
        var buffer = Data(head.utf8)
        let partial = HTTPServer.Request.parse(buffer)!
        XCTAssertFalse(partial.isComplete)
        XCTAssertTrue(partial.expectsContinue)

        buffer.append(Data("{\"a\":1}".utf8))     // 7 of 11 bytes
        XCTAssertFalse(HTTPServer.Request.parse(buffer)!.isComplete)
        buffer.append(Data("    ".utf8))         // now 11
        let full = HTTPServer.Request.parse(buffer)!
        XCTAssertTrue(full.isComplete)
        XCTAssertEqual(String(decoding: full.body, as: UTF8.self), "{\"a\":1}    ")
    }

    func testNoHeaderTerminatorYieldsNil() {
        XCTAssertNil(HTTPServer.Request.parse(Data("GET / HTTP/1.1\r\nHost: x".utf8)))
    }
}
