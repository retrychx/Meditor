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

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        capturedRequests.append(request)
        if let error = stubbedError { throw error }
        return (stubbedData, stubbedResponse)
    }

    // bytes(for:) 无法真正 mock AsyncBytes，抛 unimplemented 错误即可
    func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        fatalError("bytes(for:) not supported in MockURLSession; test the complete() path instead")
    }
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
        let backend = RestAgentBackend(config: config, wire: .anthropic, session: mock)
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
}
