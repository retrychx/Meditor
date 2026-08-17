import XCTest
@testable import MEditor

// MARK: - MockURLSession

/// 可注入预设响应的 URLSession mock，用于测试 complete() 路径。
final class MockURLSession: URLSessionDataProtocol, @unchecked Sendable {

    /// 下次 data(for:) 返回的响应。
    var stubbedData: Data = Data()
    var stubbedResponse: URLResponse = HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!
    var stubbedError: Error?

    /// 记录所有发出的请求，供断言使用。
    private(set) var capturedRequests: [URLRequest] = []

    /// 持有 bytes(for:) 创建的临时 session，防止流未读完就被释放。
    private var byteSessions: [URLSession] = []

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        capturedRequests.append(request)
        if let error = stubbedError { throw error }
        return (stubbedData, stubbedResponse)
    }

    // URLSession.AsyncBytes 无公开构造器，用一次性 URLProtocol 回放 stub 数据来生成真实 AsyncBytes
    func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        capturedRequests.append(request)
        if let error = stubbedError { throw error }
        MockURLProtocol.stub = (stubbedData, stubbedResponse)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        byteSessions.append(session)
        return try await session.bytes(for: request)
    }
}

// MARK: - MockURLProtocol

/// 回放 MockURLSession 预置响应的 URLProtocol，仅供 bytes(for:) 路径构造 AsyncBytes。
private final class MockURLProtocol: URLProtocol {
    static var stub: (data: Data, response: URLResponse)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let stub = Self.stub, let client else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        client.urlProtocol(self, didReceive: stub.response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: stub.data)
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Helpers

private func makeConfig(
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

// MARK: - RestAgentBackendTests

final class RestAgentBackendTests: XCTestCase {

    // MARK: OpenAI complete() — 正常文本响应

    func test_completeOpenAI_parsesTextResponse() async throws {
        let mock = MockURLSession()
        let json: [String: Any] = [
            "choices": [[
                "message": ["content": "Hello, world!", "role": "assistant"],
                "finish_reason": "stop"
            ]]
        ]
        mock.stubbedData = try JSONSerialization.data(withJSONObject: json)

        let backend = RestAgentBackend(config: makeConfig(), wire: .openAI, session: mock)
        let response = try await backend.complete(messages: [
            AgentMessage(role: .user, content: "Hi")
        ], tools: [])

        XCTAssertEqual(response.text, "Hello, world!")
        XCTAssertEqual(response.finishReason, "stop")
        XCTAssertTrue(response.toolCalls.isEmpty)
    }

    // MARK: OpenAI complete() — tool_calls 响应

    func test_completeOpenAI_parsesToolCallResponse() async throws {
        let mock = MockURLSession()
        let json: [String: Any] = [
            "choices": [[
                "message": [
                    "content": NSNull(),
                    "role": "assistant",
                    "tool_calls": [[
                        "id": "call_abc123",
                        "type": "function",
                        "function": [
                            "name": "get_weather",
                            "arguments": "{\"city\":\"Shanghai\"}"
                        ]
                    ]]
                ],
                "finish_reason": "tool_calls"
            ]]
        ]
        mock.stubbedData = try JSONSerialization.data(withJSONObject: json)

        let backend = RestAgentBackend(config: makeConfig(), wire: .openAI, session: mock)
        let response = try await backend.complete(messages: [
            AgentMessage(role: .user, content: "What's the weather?")
        ], tools: [])

        XCTAssertEqual(response.finishReason, "tool_calls")
        XCTAssertEqual(response.toolCalls.count, 1)
        XCTAssertEqual(response.toolCalls[0].id, "call_abc123")
        XCTAssertEqual(response.toolCalls[0].name, "get_weather")
        XCTAssertEqual(response.toolCalls[0].arguments["city"], .string("Shanghai"))
    }

    // MARK: OpenAI complete() — HTTP 错误

    func test_completeOpenAI_throwsOnHTTPError() async throws {
        let mock = MockURLSession()
        mock.stubbedData = Data("Unauthorized".utf8)
        mock.stubbedResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/chat/completions")!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        )!

        let backend = RestAgentBackend(config: makeConfig(), wire: .openAI, session: mock)
        do {
            _ = try await backend.complete(messages: [AgentMessage(role: .user, content: "Hi")], tools: [])
            XCTFail("Expected an error to be thrown")
        } catch AIError.server(let code, _) {
            XCTAssertEqual(code, 401)
        }
    }

    // MARK: OpenAI complete() — 请求构造（URL、headers、body）

    func test_completeOpenAI_buildsCorrectRequest() async throws {
        let mock = MockURLSession()
        let json: [String: Any] = [
            "choices": [["message": ["content": "ok", "role": "assistant"], "finish_reason": "stop"]]
        ]
        mock.stubbedData = try JSONSerialization.data(withJSONObject: json)

        let config = makeConfig(baseURL: "https://api.openai.com/v1", apiKey: "sk-test", model: "gpt-4o-mini")
        let backend = RestAgentBackend(config: config, wire: .openAI, session: mock)
        _ = try await backend.complete(messages: [AgentMessage(role: .user, content: "Ping")], tools: [])

        let req = try XCTUnwrap(mock.capturedRequests.first)
        XCTAssertEqual(req.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(req.httpBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["model"] as? String, "gpt-4o-mini")
        XCTAssertEqual(payload["stream"] as? Bool, false)
    }

    // MARK: Anthropic complete() — 正常文本响应

    func test_completeAnthropic_parsesTextResponse() async throws {
        let mock = MockURLSession()
        let json: [String: Any] = [
            "content": [
                ["type": "text", "text": "Bonjour!"]
            ],
            "stop_reason": "end_turn"
        ]
        mock.stubbedData = try JSONSerialization.data(withJSONObject: json)

        let config = makeConfig(kind: .anthropic, baseURL: "https://api.anthropic.com/v1", apiKey: "ant-key", model: "claude-3-5-sonnet-20241022")
        let backend = RestAgentBackend(config: config, wire: .anthropic, session: mock)
        let response = try await backend.complete(messages: [
            AgentMessage(role: .user, content: "Hello")
        ], tools: [])

        XCTAssertEqual(response.text, "Bonjour!")
        XCTAssertEqual(response.finishReason, "stop")
        XCTAssertTrue(response.toolCalls.isEmpty)
    }

    // MARK: Anthropic complete() — tool_use 响应

    func test_completeAnthropic_parsesToolUseResponse() async throws {
        let mock = MockURLSession()
        let toolInput: [String: Any] = ["city": "Beijing"]
        let json: [String: Any] = [
            "content": [
                ["type": "tool_use", "id": "toolu_01XY", "name": "get_weather", "input": toolInput]
            ],
            "stop_reason": "tool_use"
        ]
        mock.stubbedData = try JSONSerialization.data(withJSONObject: json)

        let config = makeConfig(kind: .anthropic, baseURL: "https://api.anthropic.com/v1", apiKey: "ant-key", model: "claude-3-5-sonnet-20241022")
        let backend = RestAgentBackend(config: config, wire: .anthropic, session: mock)
        let response = try await backend.complete(messages: [
            AgentMessage(role: .user, content: "Weather in Beijing?")
        ], tools: [])

        XCTAssertEqual(response.finishReason, "tool_calls")
        XCTAssertEqual(response.toolCalls.count, 1)
        XCTAssertEqual(response.toolCalls[0].id, "toolu_01XY")
        XCTAssertEqual(response.toolCalls[0].name, "get_weather")

        // argumentsJSON 应该是合法 JSON
        // arguments 已解析为 [String: AnySendableValue]
        let city = response.toolCalls[0].arguments["city"]
        XCTAssertEqual(city, .string("Beijing"))
    }

    // MARK: Anthropic complete() — 混合文字+工具响应

    func test_completeAnthropic_parsesMixedTextAndToolUse() async throws {
        let mock = MockURLSession()
        let json: [String: Any] = [
            "content": [
                ["type": "text", "text": "Let me check that for you."],
                ["type": "tool_use", "id": "toolu_02AB", "name": "search", "input": ["q": "Swift"]]
            ],
            "stop_reason": "tool_use"
        ]
        mock.stubbedData = try JSONSerialization.data(withJSONObject: json)

        let config = makeConfig(kind: .anthropic, baseURL: "https://api.anthropic.com/v1", apiKey: "ant-key", model: "claude-3-5-sonnet-20241022")
        let backend = RestAgentBackend(config: config, wire: .anthropic, session: mock)
        let response = try await backend.complete(messages: [
            AgentMessage(role: .user, content: "Search Swift")
        ], tools: [])

        XCTAssertEqual(response.text, "Let me check that for you.")
        XCTAssertEqual(response.toolCalls.count, 1)
        XCTAssertEqual(response.toolCalls[0].name, "search")
    }

    // MARK: Anthropic complete() — 请求头校验

    func test_completeAnthropic_buildsCorrectRequest() async throws {
        let mock = MockURLSession()
        let json: [String: Any] = ["content": [["type": "text", "text": "ok"]], "stop_reason": "end_turn"]
        mock.stubbedData = try JSONSerialization.data(withJSONObject: json)

        let config = makeConfig(kind: .anthropic, baseURL: "https://api.anthropic.com/v1", apiKey: "ant-key-123", model: "claude-3-haiku-20240307")
        let backend = RestAgentBackend(config: config, wire: .anthropic, session: mock)
        _ = try await backend.complete(messages: [AgentMessage(role: .user, content: "Hi")], tools: [])

        let req = try XCTUnwrap(mock.capturedRequests.first)
        XCTAssertEqual(req.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "ant-key-123")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
    }

    // MARK: Anthropic complete() — HTTP 错误

    func test_completeAnthropic_throwsOnHTTPError() async throws {
        let mock = MockURLSession()
        mock.stubbedData = Data("{\"error\":\"rate_limit\"}".utf8)
        mock.stubbedResponse = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: nil
        )!

        let config = makeConfig(kind: .anthropic, baseURL: "https://api.anthropic.com/v1", apiKey: "ant-key", model: "claude-3-5-sonnet-20241022")
        let backend = RestAgentBackend(config: config, wire: .anthropic, session: mock, retryBaseDelayNs: 1_000_000)
        do {
            _ = try await backend.complete(messages: [AgentMessage(role: .user, content: "Hi")], tools: [])
            XCTFail("Expected server error")
        } catch AIError.server(let code, _) {
            XCTAssertEqual(code, 429)
        }
    }

    // MARK: notConfigured 错误

    func test_complete_throwsWhenNotConfigured() async throws {
        let mock = MockURLSession()
        // kind=.disabled は常に isConfigured == false
        let config = makeConfig(kind: .disabled, baseURL: "", apiKey: "", model: "")

        let backend = RestAgentBackend(config: config, wire: .openAI, session: mock)
        do {
            _ = try await backend.complete(messages: [], tools: [])
            XCTFail("Expected notConfigured error")
        } catch AIError.notConfigured {
            // pass
        }
        // Mock 不应被调用
        XCTAssertTrue(mock.capturedRequests.isEmpty)
    }

    // MARK: 429 重试耗尽 — 抛最后一次的真实错误（含响应体），不得换成 "retrying" 占位文案

    func test_complete_retriesExhausted_throwsLastRealErrorWithBody() async throws {
        let mock = MockURLSession()
        mock.stubbedData = Data(#"{"error":{"message":"slow down"}}"#.utf8)
        mock.stubbedResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/chat/completions")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: nil
        )!

        let backend = RestAgentBackend(config: makeConfig(), wire: .openAI, session: mock, retryBaseDelayNs: 1_000_000)
        do {
            _ = try await backend.complete(messages: [AgentMessage(role: .user, content: "Hi")], tools: [])
            XCTFail("重试耗尽必须抛错")
        } catch AIError.server(let code, let body) {
            XCTAssertEqual(code, 429)
            XCTAssertTrue(body.contains("slow down"),
                          "耗尽后必须保留 429 的真实响应体，而非 \"retrying (attempt N)\" 占位文案")
        }
        XCTAssertEqual(mock.capturedRequests.count, 3, "默认 1 + 2 次重试，共 3 次尝试")
    }

    // MARK: Anthropic 请求 — 连续同角色消息合并（Anthropic 要求 user/assistant 严格交替）

    func test_completeAnthropic_consecutiveUserMessages_mergedIntoOne() async throws {
        let mock = MockURLSession()
        let json: [String: Any] = ["content": [["type": "text", "text": "ok"]], "stop_reason": "end_turn"]
        mock.stubbedData = try JSONSerialization.data(withJSONObject: json)

        let config = makeConfig(kind: .anthropic, baseURL: "https://api.anthropic.com/v1", apiKey: "ant-key", model: "claude-3-5-sonnet-20241022")
        let backend = RestAgentBackend(config: config, wire: .anthropic, session: mock)
        // fallback 重建历史时可能出现 user-user 相邻
        _ = try await backend.complete(messages: [
            AgentMessage(role: .user, content: "第一问"),
            AgentMessage(role: .user, content: "第二问"),
        ], tools: [])

        let body = try XCTUnwrap(mock.capturedRequests.first?.httpBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let msgs = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        XCTAssertEqual(msgs.count, 1, "连续 user 消息必须合并为一条")
        XCTAssertEqual(msgs[0]["role"] as? String, "user")
        let blocks = try XCTUnwrap(msgs[0]["content"] as? [[String: Any]],
                                   "合并后 content 必须升级为文本块数组")
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0]["text"] as? String, "第一问")
        XCTAssertEqual(blocks[1]["text"] as? String, "第二问")
    }

    func test_completeAnthropic_consecutiveAssistantMessages_mergedIntoOne() async throws {
        let mock = MockURLSession()
        let json: [String: Any] = ["content": [["type": "text", "text": "ok"]], "stop_reason": "end_turn"]
        mock.stubbedData = try JSONSerialization.data(withJSONObject: json)

        let config = makeConfig(kind: .anthropic, baseURL: "https://api.anthropic.com/v1", apiKey: "ant-key", model: "claude-3-5-sonnet-20241022")
        let backend = RestAgentBackend(config: config, wire: .anthropic, session: mock)
        // 截断提示条紧邻上一轮回复时会出现 assistant-assistant 相邻（均为纯文本）
        _ = try await backend.complete(messages: [
            AgentMessage(role: .user, content: "问"),
            AgentMessage(role: .assistant, content: "答一"),
            AgentMessage(role: .assistant, content: "答二"),
        ], tools: [])

        let body = try XCTUnwrap(mock.capturedRequests.first?.httpBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let msgs = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        XCTAssertEqual(msgs.count, 2, "连续纯文本 assistant 必须合并，保持严格交替")
        XCTAssertEqual(msgs[0]["role"] as? String, "user")
        XCTAssertEqual(msgs[0]["content"] as? String, "问", "单条 user 不触发合并，content 保持字符串")
        XCTAssertEqual(msgs[1]["role"] as? String, "assistant")
        let blocks = try XCTUnwrap(msgs[1]["content"] as? [[String: Any]])
        XCTAssertEqual(blocks.map { $0["text"] as? String }, ["答一", "答二"])
    }
}
