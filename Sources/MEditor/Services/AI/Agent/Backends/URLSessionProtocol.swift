import Foundation

/// URLSession 请求的可测试抽象。
/// 覆盖 `data(for:)`（complete()）与 `bytes(for:)`（completeStreaming()）两条路径。
/// mock 侧 `bytes(for:)` 无法直接构造 URLSession.AsyncBytes，
/// 需借助一次性 URLProtocol 回放预置数据（见 RestAgentBackendTests.MockURLSession）。
protocol URLSessionDataProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse)
}

extension URLSession: URLSessionDataProtocol {
    // SDK 只给 data(for:) 提供了省略 delegate 的精确签名，bytes(for:) 没有，
    // 无法直接作为协议见证，这里显式转发。
    public func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        try await bytes(for: request, delegate: nil)
    }
}
