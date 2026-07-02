import Foundation

/// URLSession 非流式请求的可测试抽象。
/// 仅覆盖 `data(for:)` 路径（complete()），流式 SSE 路径（bytes(for:)）
/// 因为 URLSession.AsyncBytes 无法实现 Sendable 协议而无法直接 mock，
/// 流式测试通过 ChunkingBackend（mock AgentBackend 层）覆盖。
protocol URLSessionDataProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionDataProtocol {}
