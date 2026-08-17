import XCTest
@testable import MEditor

// MARK: - AgentSSEStabilityTests
//
// Agent 稳定性回归测试（eval 集）—— SSE 流式解析路径：
//   A1 畸形 data 行跳过               A5 finish_reason="length" 透传
//   A2 缺 id / 缺 name 的 tool_call 丢弃  A6 流中途网络错误抛出
//   A3 乱序/交错 index 归位           A7/A8 Anthropic wire 等价覆盖
//   A4 建连 429 → withRetry 重试成功
//
// 单响应 200 流复用 RestAgentBackendTests.swift 中的 internal MockURLSession；
// 需要「多次响应序列」或「流中途失败」的场景使用本文件私有的 session mock。

final class AgentSSEStabilityTests: XCTestCase {

    // MARK: - Helpers

    private func makeEvalConfig(
        kind: AIProviderKind = .openai,
        baseURL: String = "https://api.openai.com/v1",
        apiKey: String = "test-key",
        model: String = "gpt-4o"
    ) -> AIConfig {
        AIConfig(
            kind: kind,
            baseURL: baseURL,
            model: model,
            cliPath: "",
            cliModel: "",
            apiKey: apiKey,
            requestTimeoutSeconds: 60
        )
    }

    private func makeAnthropicConfig() -> AIConfig {
        makeEvalConfig(
            kind: .anthropic,
            baseURL: "https://api.anthropic.com/v1",
            apiKey: "ant-key",
            model: "claude-3-5-sonnet-20241022"
        )
    }

    /// 把若干 SSE 行拼成回放字节流。
    private func sseData(_ lines: [String]) -> Data {
        Data(lines.joined(separator: "\n").utf8)
    }

    /// 200 OK 响应（URL 不重要，流式解析只看 statusCode）。
    private func okResponse() -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
    }

    /// 收集 onTextChunk 回调的线程安全容器。
    private final class ChunkBox: @unchecked Sendable {
        private(set) var chunks: [String] = []
        private let lock = NSLock()
        func append(_ s: String) { lock.lock(); chunks.append(s); lock.unlock() }
        var joined: String { lock.lock(); defer { lock.unlock() }; return chunks.joined() }
    }

    private func makeOpenAIBackend(_ mock: MockURLSession) -> RestAgentBackend {
        RestAgentBackend(config: makeEvalConfig(), wire: .openAI, session: mock)
    }

    // MARK: - A1 流中间夹一行畸形 data → 跳过，其余内容正常拼出

    func test_streamOpenAI_malformedDataLineSkipped_textAssembled() async throws {
        let mock = MockURLSession()
        mock.stubbedData = sseData([
            #"data: {"choices":[{"delta":{"content":"你好"},"finish_reason":null}]}"#,
            "data: {this-is-not-json",
            #"data: {"choices":[]}"#,   // choices 为空同样按畸形行跳过
            ": ping",                   // 非 data 行直接忽略
            #"data: {"choices":[{"delta":{"content":"，世界"},"finish_reason":null}]}"#,
            #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#,
            "data: [DONE]",
        ])

        let chunks = ChunkBox()
        let response = try await makeOpenAIBackend(mock).completeStreaming(
            messages: [AgentMessage(role: .user, content: "hi")],
            tools: [],
            onTextChunk: { chunks.append($0) }
        )

        XCTAssertEqual(response.text, "你好，世界")
        XCTAssertEqual(chunks.joined, "你好，世界")
        XCTAssertEqual(response.finishReason, "stop")
        XCTAssertTrue(response.toolCalls.isEmpty)
    }

    // MARK: - A2 tool_call 分块缺 id 或缺 name → 最终 toolCalls 不含它

    func test_streamOpenAI_toolCallMissingIDOrName_dropped() async throws {
        let mock = MockURLSession()
        mock.stubbedData = sseData([
            // index 0：有 name 但自始至终没有 id → 丢弃
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"get_weather","arguments":"{\"city\":"}}]}}]}"#,
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"SH\"}"}}]}}]}"#,
            // index 1：有 id 但没有 name → 丢弃
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":1,"id":"call_no_name","function":{"arguments":"{}"}}]}}]}"#,
            // index 2：id + name 齐全 → 保留
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":2,"id":"call_ok","function":{"name":"read_document","arguments":"{}"}}]}}]}"#,
            #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
            "data: [DONE]",
        ])

        let response = try await makeOpenAIBackend(mock).completeStreaming(
            messages: [AgentMessage(role: .user, content: "hi")],
            tools: [],
            onTextChunk: { _ in }
        )

        XCTAssertEqual(response.toolCalls.count, 1, "缺 id / 缺 name 的 tool_call 必须被丢弃")
        XCTAssertEqual(response.toolCalls[0].id, "call_ok")
        XCTAssertEqual(response.toolCalls[0].name, "read_document")
        XCTAssertEqual(response.finishReason, "tool_calls")
    }

    // MARK: - A3 多个 tool_call 交错/乱序 index 到达 → 按 index 归位、参数完整

    func test_streamOpenAI_interleavedToolCallChunks_reassembledByIndex() async throws {
        let mock = MockURLSession()
        mock.stubbedData = sseData([
            // index 1 的块先到，index 0 后到，参数分两片交错到达
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":1,"id":"call_2","function":{"name":"write_document","arguments":"{\"content\":"}}]}}]}"#,
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"read_document","arguments":"{\"file\":"}}]}}]}"#,
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":1,"function":{"arguments":"\"v2\"}"}}]}}]}"#,
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"a.md\"}"}}]}}]}"#,
            #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
            "data: [DONE]",
        ])

        let response = try await makeOpenAIBackend(mock).completeStreaming(
            messages: [AgentMessage(role: .user, content: "hi")],
            tools: [],
            onTextChunk: { _ in }
        )

        XCTAssertEqual(response.toolCalls.map(\.id), ["call_1", "call_2"], "应按 index 升序归位")
        XCTAssertEqual(response.toolCalls[0].name, "read_document")
        XCTAssertEqual(response.toolCalls[0].arguments["file"], .string("a.md"))
        XCTAssertEqual(response.toolCalls[1].name, "write_document")
        XCTAssertEqual(response.toolCalls[1].arguments["content"], .string("v2"))
    }

    // MARK: - A4 建连返回 429 再成功 → withRetry 生效（注入 1ms 退避，避免真实 ~1s sleep）

    func test_streamOpenAI_connect429ThenSuccess_retriesAndCompletes() async throws {
        let rateLimited = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/chat/completions")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: nil
        )!
        let session = SequencedStreamSession(stubs: [
            (Data(#"{"error":"rate limited"}"#.utf8), rateLimited),
            (sseData([
                #"data: {"choices":[{"delta":{"content":"ok"},"finish_reason":null}]}"#,
                #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#,
                "data: [DONE]",
            ]), okResponse()),
        ])

        let backend = RestAgentBackend(config: makeEvalConfig(), wire: .openAI, session: session, retryBaseDelayNs: 1_000_000)
        let response = try await backend.completeStreaming(
            messages: [AgentMessage(role: .user, content: "hi")],
            tools: [],
            onTextChunk: { _ in }
        )

        XCTAssertGreaterThanOrEqual(session.capturedRequests.count, 2, "429 应触发重试")
        XCTAssertEqual(response.text, "ok")
        XCTAssertEqual(response.finishReason, "stop")
    }

    // MARK: - A5 finish_reason="length" → 透传

    func test_streamOpenAI_finishReasonLength_passedThrough() async throws {
        let mock = MockURLSession()
        mock.stubbedData = sseData([
            #"data: {"choices":[{"delta":{"content":"被截断的输出"},"finish_reason":null}]}"#,
            #"data: {"choices":[{"delta":{},"finish_reason":"length"}]}"#,
            "data: [DONE]",
        ])

        let response = try await makeOpenAIBackend(mock).completeStreaming(
            messages: [AgentMessage(role: .user, content: "hi")],
            tools: [],
            onTextChunk: { _ in }
        )

        XCTAssertEqual(response.finishReason, "length")
        XCTAssertEqual(response.text, "被截断的输出")
    }

    // MARK: - A6 流中途网络错误 → 抛出错误
    // MockURLSession 只支持整段回放，中途断流由私有 MidStreamFailSession 注入。

    func test_streamOpenAI_networkFailureMidStream_throws() async throws {
        let session = MidStreamFailSession(
            partialData: sseData([
                #"data: {"choices":[{"delta":{"content":"partial"},"finish_reason":null}]}"#,
            ]),
            failure: URLError(.networkConnectionLost)
        )

        let backend = RestAgentBackend(config: makeEvalConfig(), wire: .openAI, session: session)
        do {
            _ = try await backend.completeStreaming(
                messages: [AgentMessage(role: .user, content: "hi")],
                tools: [],
                onTextChunk: { _ in }
            )
            XCTFail("流中途网络错误必须抛出，不能静默截断为成功")
        } catch {
            // 期望抛出（URLError 或包装后的错误均可，关键是不能返回成功响应）
        }
    }

    // MARK: - A7 Anthropic：畸形 data 行跳过 + 文本拼接

    func test_streamAnthropic_malformedDataLineSkipped_textAssembled() async throws {
        let mock = MockURLSession()
        mock.stubbedData = sseData([
            "event: message_start",
            #"data: {"type":"message_start","message":{"id":"msg_1"}}"#,
            "event: content_block_start",
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            "data: not-json-at-all",   // 畸形行 → 跳过
            "event: content_block_delta",
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"你好"}}"#,
            "event: message_delta",
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#,
        ])

        let backend = RestAgentBackend(config: makeAnthropicConfig(), wire: .anthropic, session: mock)
        let response = try await backend.completeStreaming(
            messages: [AgentMessage(role: .user, content: "hi")],
            tools: [],
            onTextChunk: { _ in }
        )

        XCTAssertEqual(response.text, "你好")
        XCTAssertEqual(response.finishReason, "stop")
        XCTAssertTrue(response.toolCalls.isEmpty)
    }

    // MARK: - A8 Anthropic：乱序 content_block index + input_json_delta 拼接

    func test_streamAnthropic_interleavedToolUseBlocks_reassembledByIndex() async throws {
        let mock = MockURLSession()
        mock.stubbedData = sseData([
            // index 1 的 tool_use 先开始，index 0 后开始，partial_json 交错到达
            #"data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_B","name":"write_document"}}"#,
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_A","name":"read_document"}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"content\":"}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"city\":\"北京\"}"}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\"v2\"}"}}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"tool_use"}}"#,
        ])

        let backend = RestAgentBackend(config: makeAnthropicConfig(), wire: .anthropic, session: mock)
        let response = try await backend.completeStreaming(
            messages: [AgentMessage(role: .user, content: "hi")],
            tools: [],
            onTextChunk: { _ in }
        )

        XCTAssertEqual(response.finishReason, "tool_calls")
        XCTAssertEqual(response.toolCalls.map(\.id), ["toolu_A", "toolu_B"], "应按 content_block index 升序归位")
        XCTAssertEqual(response.toolCalls[0].name, "read_document")
        XCTAssertEqual(response.toolCalls[0].arguments["city"], .string("北京"))
        XCTAssertEqual(response.toolCalls[1].name, "write_document")
        XCTAssertEqual(response.toolCalls[1].arguments["content"], .string("v2"))
    }

    // MARK: - A9 Anthropic：流中途 error 事件 → 解析 message 抛出（不得当畸形行静默跳过）

    func test_streamAnthropic_errorEventMidStream_throwsWithMessage() async throws {
        let mock = MockURLSession()
        mock.stubbedData = sseData([
            "event: message_start",
            #"data: {"type":"message_start","message":{"id":"msg_1"}}"#,
            "event: content_block_delta",
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"partial"}}"#,
            "event: error",
            #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#,
        ])

        let backend = RestAgentBackend(config: makeAnthropicConfig(), wire: .anthropic, session: mock)
        do {
            _ = try await backend.completeStreaming(
                messages: [AgentMessage(role: .user, content: "hi")],
                tools: [],
                onTextChunk: { _ in }
            )
            XCTFail("流中途 error 事件必须抛出，不能静默跳过")
        } catch AIError.server(_, let message) {
            XCTAssertEqual(message, "Overloaded", "error 事件的 message 必须用户可见")
        }
    }

    // MARK: - A10 Anthropic：ping 保活帧忽略，流正常完成

    func test_streamAnthropic_pingEventIgnored_streamCompletes() async throws {
        let mock = MockURLSession()
        mock.stubbedData = sseData([
            "event: message_start",
            #"data: {"type":"message_start","message":{"id":"msg_1"}}"#,
            "event: ping",
            #"data: {"type":"ping"}"#,   // 保活帧 → 忽略
            "event: content_block_delta",
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"你好"}}"#,
            "event: message_delta",
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#,
        ])

        let backend = RestAgentBackend(config: makeAnthropicConfig(), wire: .anthropic, session: mock)
        let response = try await backend.completeStreaming(
            messages: [AgentMessage(role: .user, content: "hi")],
            tools: [],
            onTextChunk: { _ in }
        )

        XCTAssertEqual(response.text, "你好")
        XCTAssertEqual(response.finishReason, "stop")
    }
}

// MARK: - 私有 SSE 回放 URLProtocol

/// 与 RestAgentBackendTests 的 MockURLProtocol 同思路，但支持两种计划：
/// 整段回放（可换响应码）或发完部分数据后中途失败（模拟断流）。
private final class SSEReplayProtocol: URLProtocol {
    enum Plan {
        case replay(Data, URLResponse)
        case failAfter(Data, URLResponse, Error)
    }

    static var plan: Plan?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let plan = Self.plan, let client else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        switch plan {
        case .replay(let data, let response):
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: data)
            client.urlProtocolDidFinishLoading(self)
        case .failAfter(let data, let response, let error):
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: data)
            client.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - 有序响应序列 session（A4：429 → 200）

/// 每次 data(for:)/bytes(for:) 依次弹出下一条预设响应，用于验证 withRetry。
private final class SequencedStreamSession: URLSessionDataProtocol, @unchecked Sendable {
    private var stubs: [(Data, URLResponse)]
    private(set) var capturedRequests: [URLRequest] = []
    private var heldSessions: [URLSession] = []
    private let lock = NSLock()

    init(stubs: [(Data, URLResponse)]) { self.stubs = stubs }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.lock(); capturedRequests.append(request); lock.unlock()
        return nextStub()
    }

    func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        lock.lock(); capturedRequests.append(request); lock.unlock()
        let stub = nextStub()
        SSEReplayProtocol.plan = .replay(stub.0, stub.1)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SSEReplayProtocol.self]
        let session = URLSession(configuration: config)
        lock.lock(); heldSessions.append(session); lock.unlock()
        return try await session.bytes(for: request)
    }

    private func nextStub() -> (Data, URLResponse) {
        lock.lock(); defer { lock.unlock() }
        if stubs.isEmpty {
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }
        return stubs.removeFirst()
    }
}

// MARK: - 中途失败 session（A6：流式响应发到一半断流）

private final class MidStreamFailSession: URLSessionDataProtocol, @unchecked Sendable {
    let partialData: Data
    let failure: Error
    private var heldSessions: [URLSession] = []
    private let lock = NSLock()

    init(partialData: Data, failure: Error) {
        self.partialData = partialData
        self.failure = failure
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        throw failure
    }

    func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        SSEReplayProtocol.plan = .failAfter(partialData, response, failure)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SSEReplayProtocol.self]
        let session = URLSession(configuration: config)
        lock.lock(); heldSessions.append(session); lock.unlock()
        return try await session.bytes(for: request)
    }
}
