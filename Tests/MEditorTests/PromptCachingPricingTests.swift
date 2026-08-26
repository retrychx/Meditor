import XCTest
@testable import MEditor

/// Prompt 缓存（cache_control 注入 / usage 缓存字段解析）与成本估算的测试。
/// mock 方式复用 RestAgentBackendTests 的 MockURLSession（记录请求 + 回放响应）。
final class PromptCachingPricingTests: XCTestCase {

    // MARK: - Helpers

    private struct DummyTool: AgentTool {
        let spec: AgentToolSpec
        init(_ name: String) { spec = AgentToolSpec(name: name, description: "test tool \(name)") }
        func execute(arguments: [String: AnySendableValue], context: any AgentContextProtocol) async throws -> String { "ok" }
    }

    private func makeAnthropicConfig() -> AIConfig {
        AIConfig(kind: .anthropic, baseURL: "https://api.anthropic.com/v1", model: "claude-sonnet-4-5",
                 cliPath: "", cliModel: "", apiKey: "ant-key", requestTimeoutSeconds: 60)
    }

    private func makeOpenAIConfig() -> AIConfig {
        AIConfig(kind: .openai, baseURL: "https://api.openai.com/v1", model: "gpt-4o",
                 cliPath: "", cliModel: "", apiKey: "sk-test", requestTimeoutSeconds: 60)
    }

    private func stubAnthropicOK(_ mock: MockURLSession) throws {
        mock.stubbedData = try JSONSerialization.data(withJSONObject: [
            "content": [["type": "text", "text": "ok"]],
            "stop_reason": "end_turn"
        ])
    }

    private func bodyJSON(_ mock: MockURLSession) throws -> [String: Any] {
        let body = try XCTUnwrap(mock.capturedRequests.first?.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    // MARK: - A1. Anthropic 请求 cache_control 注入

    func test_anthropicRequest_injectsCacheControlOnToolsSystemAndLastMessage() async throws {
        let mock = MockURLSession()
        try stubAnthropicOK(mock)
        let backend = RestAgentBackend(config: makeAnthropicConfig(), wire: .anthropic, session: mock)
        _ = try await backend.complete(messages: [
            AgentMessage(role: .system, content: "You are helpful."),
            AgentMessage(role: .user, content: "Hi")
        ], tools: [DummyTool("read_document"), DummyTool("write_document")])

        let payload = try bodyJSON(mock)

        // ① system 升级为块数组并在块上打断点
        let system = try XCTUnwrap(payload["system"] as? [[String: Any]])
        XCTAssertEqual(system.first?["type"] as? String, "text")
        let sysCache = system.first?["cache_control"] as? [String: Any]
        XCTAssertEqual(sysCache?["type"] as? String, "ephemeral")

        // ② 仅最后一个工具定义带断点
        let tools = try XCTUnwrap(payload["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 2)
        XCTAssertNil(tools[0]["cache_control"])
        let lastToolCache = try XCTUnwrap(tools[1]["cache_control"] as? [String: Any])
        XCTAssertEqual(lastToolCache["type"] as? String, "ephemeral")

        // ③ 最后一条消息（字符串 content 升级为块数组）带断点
        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        let lastMsg = try XCTUnwrap(messages.last)
        let blocks = try XCTUnwrap(lastMsg["content"] as? [[String: Any]],
                                   "打 cache 断点后 content 必须是块数组")
        let lastBlockCache = try XCTUnwrap(blocks.last?["cache_control"] as? [String: Any])
        XCTAssertEqual(lastBlockCache["type"] as? String, "ephemeral")
        XCTAssertEqual(blocks.last?["text"] as? String, "Hi")
    }

    func test_anthropicRequest_noSystemNoTools_stillMarksLastMessage() async throws {
        let mock = MockURLSession()
        try stubAnthropicOK(mock)
        let backend = RestAgentBackend(config: makeAnthropicConfig(), wire: .anthropic, session: mock)
        _ = try await backend.complete(messages: [
            AgentMessage(role: .user, content: "Hi")
        ], tools: [])

        let payload = try bodyJSON(mock)
        XCTAssertNil(payload["system"])
        XCTAssertNil(payload["tools"])
        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        let blocks = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        XCTAssertEqual((blocks.last?["cache_control"] as? [String: Any])?["type"] as? String, "ephemeral")
    }

    func test_openAIRequest_doesNotInjectCacheControl() async throws {
        let mock = MockURLSession()
        mock.stubbedData = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": "ok", "role": "assistant"], "finish_reason": "stop"]]
        ])
        let backend = RestAgentBackend(config: makeOpenAIConfig(), wire: .openAI, session: mock)
        _ = try await backend.complete(messages: [
            AgentMessage(role: .system, content: "sys"),
            AgentMessage(role: .user, content: "Hi")
        ], tools: [DummyTool("read_document")])

        // OpenAI 兼容端点的 prompt caching 是服务端自动的：payload 里不得出现 cache_control
        let body = try XCTUnwrap(mock.capturedRequests.first?.httpBody)
        let raw = String(decoding: body, as: UTF8.self)
        XCTAssertFalse(raw.contains("cache_control"))
    }

    // MARK: - A2. usage 缓存字段解析 — 非流式

    func test_completeAnthropic_parsesCacheUsage() async throws {
        let mock = MockURLSession()
        mock.stubbedData = try JSONSerialization.data(withJSONObject: [
            "content": [["type": "text", "text": "ok"]],
            "stop_reason": "end_turn",
            "usage": [
                "input_tokens": 200,
                "output_tokens": 60,
                "cache_read_input_tokens": 8_100,
                "cache_creation_input_tokens": 500
            ]
        ])
        let backend = RestAgentBackend(config: makeAnthropicConfig(), wire: .anthropic, session: mock)
        let response = try await backend.complete(messages: [AgentMessage(role: .user, content: "Hi")], tools: [])

        let usage = try XCTUnwrap(response.usage)
        // promptTokens 归一为「全部输入」：input + cache_read + cache_creation
        XCTAssertEqual(usage.promptTokens, 8_800)
        XCTAssertEqual(usage.completionTokens, 60)
        XCTAssertEqual(usage.cacheReadTokens, 8_100)
        XCTAssertEqual(usage.cacheWriteTokens, 500)
    }

    func test_completeOpenAI_parsesCachedTokens() async throws {
        let mock = MockURLSession()
        mock.stubbedData = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": "ok", "role": "assistant"], "finish_reason": "stop"]],
            "usage": [
                "prompt_tokens": 1_500,
                "completion_tokens": 45,
                "prompt_tokens_details": ["cached_tokens": 1_024]
            ]
        ])
        let backend = RestAgentBackend(config: makeOpenAIConfig(), wire: .openAI, session: mock)
        let response = try await backend.complete(messages: [AgentMessage(role: .user, content: "Hi")], tools: [])

        let usage = try XCTUnwrap(response.usage)
        // OpenAI 的 prompt_tokens 本身含 cached 部分，不加回
        XCTAssertEqual(usage.promptTokens, 1_500)
        XCTAssertEqual(usage.cacheReadTokens, 1_024)
        XCTAssertEqual(usage.cacheWriteTokens, 0)
    }

    // MARK: - A2. usage 缓存字段解析 — 流式

    func test_streamAnthropic_parsesCacheUsageFromMessageStart() async throws {
        let mock = MockURLSession()
        let sse = """
        data: {"type":"message_start","message":{"usage":{"input_tokens":120,"output_tokens":1,"cache_read_input_tokens":8000,"cache_creation_input_tokens":300}}}

        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"hi"}}

        data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":12}}

        data: [DONE]

        """
        mock.stubbedData = Data(sse.utf8)
        let backend = RestAgentBackend(config: makeAnthropicConfig(), wire: .anthropic, session: mock)
        let response = try await backend.completeStreaming(
            messages: [AgentMessage(role: .user, content: "Hi")], tools: []) { _ in }

        let usage = try XCTUnwrap(response.usage)
        XCTAssertEqual(usage.promptTokens, 8_420)   // 120 + 8000 + 300
        XCTAssertEqual(usage.completionTokens, 12)
        XCTAssertEqual(usage.cacheReadTokens, 8_000)
        XCTAssertEqual(usage.cacheWriteTokens, 300)
    }

    func test_streamOpenAI_parsesCachedTokensFromFinalFrame() async throws {
        let mock = MockURLSession()
        let sse = """
        data: {"choices":[{"delta":{"content":"hi"},"finish_reason":null}]}

        data: {"choices":[],"usage":{"prompt_tokens":2000,"completion_tokens":9,"prompt_tokens_details":{"cached_tokens":1536}}}

        data: [DONE]

        """
        mock.stubbedData = Data(sse.utf8)
        let backend = RestAgentBackend(config: makeOpenAIConfig(), wire: .openAI, session: mock)
        let response = try await backend.completeStreaming(
            messages: [AgentMessage(role: .user, content: "Hi")], tools: []) { _ in }

        let usage = try XCTUnwrap(response.usage)
        XCTAssertEqual(usage.promptTokens, 2_000)
        XCTAssertEqual(usage.cacheReadTokens, 1_536)
        XCTAssertEqual(usage.completionTokens, 9)
    }

    // MARK: - AgentUsage 累加

    func test_agentUsage_plus_sumsCacheFields() {
        let a = AgentUsage(promptTokens: 100, completionTokens: 10, cacheReadTokens: 50, cacheWriteTokens: 5)
        let b = AgentUsage(promptTokens: 200, completionTokens: 20, cacheReadTokens: 60, cacheWriteTokens: 7)
        let sum = a + b
        XCTAssertEqual(sum.promptTokens, 300)
        XCTAssertEqual(sum.completionTokens, 30)
        XCTAssertEqual(sum.cacheReadTokens, 110)
        XCTAssertEqual(sum.cacheWriteTokens, 12)
    }

    // MARK: - B1. 价格表查询

    func test_pricingLookup_knownModels() {
        XCTAssertNotNil(ModelPricing.price(for: "claude-sonnet-4-5"))
        XCTAssertNotNil(ModelPricing.price(for: "gpt-4o"))
        XCTAssertNotNil(ModelPricing.price(for: "deepseek-v4-flash"))
        XCTAssertNotNil(ModelPricing.price(for: "kimi-k2-0711-preview"))
    }

    func test_pricingLookup_openRouterPrefixAndDateSuffix() {
        // OpenRouter 风格 vendor 前缀 + 日期后缀都应命中
        XCTAssertNotNil(ModelPricing.price(for: "anthropic/claude-3.7-sonnet"))
        XCTAssertNotNil(ModelPricing.price(for: "google/gemini-2.0-flash-001"))
        XCTAssertNotNil(ModelPricing.price(for: "claude-sonnet-4-5-20250929"))
    }

    func test_pricingLookup_longestPrefixWins() {
        // "gpt-4o-mini" 必须命中 mini 价，而不是被 "gpt-4o" 抢先
        let mini = ModelPricing.price(for: "gpt-4o-mini")
        let full = ModelPricing.price(for: "gpt-4o")
        XCTAssertNotNil(mini)
        XCTAssertNotNil(full)
        XCTAssertLessThan(mini!.input, full!.input)
    }

    func test_pricingLookup_unknownModel_returnsNil() {
        XCTAssertNil(ModelPricing.price(for: "some-local-llm-9000"))
        XCTAssertNil(ModelPricing.price(for: ""))
    }

    // MARK: - B1. 成本估算

    func test_estimateCost_knownModel() {
        // gpt-4o: input $2.5/M, cached $1.25/M, output $10/M
        let usage = AgentUsage(promptTokens: 2_000, completionTokens: 1_000,
                               cacheReadTokens: 1_000, cacheWriteTokens: 0)
        let cost = ModelPricing.estimateCost(usage: usage, model: "gpt-4o")
        // (2000-1000)*2.5 + 1000*1.25 + 1000*10 = 2500+1250+10000 每百万 → 0.01375
        XCTAssertEqual(cost ?? 0, 0.01375, accuracy: 1e-9)
    }

    func test_estimateCost_anthropicCacheWrite() {
        // claude-sonnet-4-5: input $3/M, read $0.3/M, write $3.75/M, output $15/M
        let usage = AgentUsage(promptTokens: 10_000, completionTokens: 1_000,
                               cacheReadTokens: 8_000, cacheWriteTokens: 1_000)
        let cost = ModelPricing.estimateCost(usage: usage, model: "claude-sonnet-4-5")
        // (10000-9000)*3 + 8000*0.3 + 1000*3.75 + 1000*15 = 3000+2400+3750+15000 每百万
        XCTAssertEqual(cost ?? 0, 0.02415, accuracy: 1e-9)
    }

    func test_estimateCost_unknownModel_returnsNil() {
        let usage = AgentUsage(promptTokens: 1_000, completionTokens: 100)
        XCTAssertNil(ModelPricing.estimateCost(usage: usage, model: "unknown-model-x"))
        XCTAssertNil(ModelPricing.estimateCost(usage: usage, model: nil))
    }

    // MARK: - B2. 展示格式化

    func test_compactTokens() {
        XCTAssertEqual(ModelPricing.compactTokens(999), "999")
        XCTAssertEqual(ModelPricing.compactTokens(12_345), "12.3K")
        XCTAssertEqual(ModelPricing.compactTokens(8_100), "8.1K")
        XCTAssertEqual(ModelPricing.compactTokens(2_345_678), "2.3M")
    }

    func test_formatUSD() {
        XCTAssertEqual(ModelPricing.formatUSD(0.004), "$0.0040")
        XCTAssertEqual(ModelPricing.formatUSD(1.234), "$1.23")
    }
}
