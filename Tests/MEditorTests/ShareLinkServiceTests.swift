import XCTest
@testable import MEditor

/// ShareLinkService 的请求构造与错误映射（传输层注入 mock，不走真实网络）。
final class ShareLinkServiceTests: XCTestCase {

    private let baseURL = "https://share.example.com"
    private let token = "test-token"
    private let title = "周报"
    private let html = "<!DOCTYPE html><html><body><h1>hi</h1></body></html>"

    /// 捕获请求并返回预制响应的 service。
    private func makeService(
        status: Int = 200,
        body: Data = Data(#"{"url":"https://share.example.com/d/abc123XYZ0"}"#.utf8),
        captured: UnsafeMutablePointer<URLRequest?>? = nil
    ) -> ShareLinkService {
        var service = ShareLinkService()
        service.transport = { request in
            captured?.pointee = request
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
            )!
            return (body, response)
        }
        return service
    }

    func testRequestBuilding() async throws {
        var request: URLRequest?
        let service = makeService(captured: &request)
        _ = try await service.publish(baseURL: baseURL, token: token, title: title, html: html)

        let req = try XCTUnwrap(request)
        XCTAssertEqual(req.url?.absoluteString, "https://share.example.com/api/share")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["title"], title)
        XCTAssertEqual(json["html"], html)
    }

    func testBaseURLTrailingSlashStripped() async throws {
        var request: URLRequest?
        let service = makeService(captured: &request)
        _ = try await service.publish(baseURL: baseURL + "/", token: token, title: title, html: html)
        XCTAssertEqual(request?.url?.absoluteString, "https://share.example.com/api/share")
    }

    func testSuccessReturnsURL() async throws {
        let service = makeService()
        let url = try await service.publish(baseURL: baseURL, token: token, title: title, html: html)
        XCTAssertEqual(url, "https://share.example.com/d/abc123XYZ0")
    }

    func testUnauthorizedMapsToInvalidToken() async {
        let service = makeService(status: 401, body: Data(#"{"error":"unauthorized"}"#.utf8))
        await assertThrows(ShareLinkError.invalidToken) {
            _ = try await service.publish(baseURL: baseURL, token: token, title: title, html: html)
        }
    }

    func testTooLargeResponseMaps() async {
        let service = makeService(status: 413, body: Data(#"{"error":"too large"}"#.utf8))
        await assertThrows(ShareLinkError.tooLarge) {
            _ = try await service.publish(baseURL: baseURL, token: token, title: title, html: html)
        }
    }

    func testServerErrorCarriesMessage() async {
        let service = makeService(status: 500, body: Data(#"{"error":"boom"}"#.utf8))
        await assertThrows(ShareLinkError.server(500, "boom")) {
            _ = try await service.publish(baseURL: baseURL, token: token, title: title, html: html)
        }
    }

    func testOversizedHTMLRejectedLocally() async {
        var called = false
        var service = ShareLinkService()
        service.transport = { _ in
            called = true
            throw URLError(.badServerResponse)
        }
        let big = String(repeating: "x", count: ShareLinkService.maxHTMLBytes + 1)
        await assertThrows(ShareLinkError.tooLarge) {
            _ = try await service.publish(baseURL: baseURL, token: token, title: title, html: big)
        }
        XCTAssertFalse(called, "超限 HTML 不应发出网络请求")
    }

    func testTransportFailureMapsToNetwork() async {
        var service = ShareLinkService()
        service.transport = { _ in throw URLError(.notConnectedToInternet) }
        await assertThrows(ShareLinkError.network) {
            _ = try await service.publish(baseURL: baseURL, token: token, title: title, html: html)
        }
    }

    // MARK: - helpers

    private func assertThrows(
        _ expected: ShareLinkError,
        file: StaticString = #filePath, line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let e as ShareLinkError {
            XCTAssertEqual(e, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected error: \(error)", file: file, line: line)
        }
    }
}

extension ShareLinkError: Equatable {
    public static func == (lhs: ShareLinkError, rhs: ShareLinkError) -> Bool {
        switch (lhs, rhs) {
        case (.notConfigured, .notConfigured), (.invalidToken, .invalidToken),
             (.tooLarge, .tooLarge), (.network, .network), (.badResponse, .badResponse),
             (.noWebView, .noWebView):
            return true
        case let (.server(a1, b1), .server(a2, b2)): return a1 == a2 && b1 == b2
        case let (.renderFailed(a), .renderFailed(b)): return a == b
        default: return false
        }
    }
}
