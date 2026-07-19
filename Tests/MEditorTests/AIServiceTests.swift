import XCTest
@testable import MEditor

/// AIService 的纯逻辑测试：AIConfig.isConfigured 各 provider 分支、AIConfig.current 的
/// 场景模型回退、AIPresets 一致性、AIError 映射、AIAPIKeyStore。
/// 网络层（SSE / RestAgentBackend）已由 RestAgentBackendTests 覆盖，这里不重复。
@MainActor
final class AIServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeConfig(
        kind: AIProviderKind,
        baseURL: String = "https://api.example.com/v1",
        model: String = "test-model",
        cliPath: String = "/usr/local/bin/claude",
        apiKey: String = ""
    ) -> AIConfig {
        AIConfig(
            kind: kind, baseURL: baseURL, model: model,
            cliPath: cliPath, cliModel: "", apiKey: apiKey,
            requestTimeoutSeconds: 300
        )
    }

    // MARK: - AIConfig.isConfigured：disabled

    func testIsConfigured_disabled_alwaysFalse() {
        let cfg = makeConfig(kind: .disabled, model: "gpt-4o", apiKey: "sk-x")
        XCTAssertFalse(cfg.isConfigured, "disabled 下无论其他字段如何都未配置")
    }

    // MARK: - AIConfig.isConfigured：openai（OpenAI 兼容 provider）

    func testIsConfigured_openai_requiresBaseURLAndModel() {
        XCTAssertTrue(makeConfig(kind: .openai).isConfigured)
        XCTAssertFalse(makeConfig(kind: .openai, baseURL: "").isConfigured, "缺 baseURL")
        XCTAssertFalse(makeConfig(kind: .openai, model: "").isConfigured, "缺 model")
    }

    func testIsConfigured_openai_apiKeyNotRequired() {
        // Ollama 等本地 OpenAI 兼容服务无需 API Key
        let cfg = makeConfig(kind: .openai, baseURL: "http://localhost:11434/v1", apiKey: "")
        XCTAssertTrue(cfg.isConfigured)
    }

    // MARK: - AIConfig.isConfigured：anthropic

    func testIsConfigured_anthropic_requiresApiKeyAndModel() {
        XCTAssertTrue(makeConfig(kind: .anthropic, apiKey: "sk-ant").isConfigured)
        XCTAssertFalse(makeConfig(kind: .anthropic, apiKey: "").isConfigured, "缺 apiKey")
        XCTAssertFalse(makeConfig(kind: .anthropic, model: "", apiKey: "sk-ant").isConfigured, "缺 model")
    }

    func testIsConfigured_anthropic_baseURLNotRequired() {
        // Anthropic 直连有默认端点，baseURL 为空不影响配置判定
        let cfg = makeConfig(kind: .anthropic, baseURL: "", apiKey: "sk-ant")
        XCTAssertTrue(cfg.isConfigured)
    }

    // MARK: - AIConfig.isConfigured：claudeCLI

    func testIsConfigured_claudeCLI_requiresCLIPathOnly() {
        XCTAssertTrue(makeConfig(kind: .claudeCLI).isConfigured)
        XCTAssertFalse(makeConfig(kind: .claudeCLI, cliPath: "").isConfigured)
    }

    func testIsConfigured_claudeCLI_modelAndKeyIrrelevant() {
        let cfg = makeConfig(kind: .claudeCLI, baseURL: "", model: "", apiKey: "")
        XCTAssertTrue(cfg.isConfigured, "CLI 只看 cliPath")
    }

    // MARK: - AIConfig.current：场景模型回退

    /// AppSettings init 是 private 且写死 UserDefaults.standard，无法构造隔离实例——
    /// 只能改 shared 单例。以下用例严格 save/restore，避免污染其他测试与真实偏好。

    private func withAISettings<T>(
        provider: String = "openai",
        baseURL: String = "https://api.openai.com/v1",
        model: String = "base-model",
        agentModel: String = "",
        inlineModel: String = "",
        cliPath: String = "/usr/local/bin/claude",
        _ body: (AppSettings) throws -> T
    ) rethrows -> T {
        let s = AppSettings.shared
        let saved = (s.aiProvider, s.aiBaseURL, s.aiModel, s.aiAgentModel, s.aiInlineModel, s.aiCLIPath)
        defer {
            s.aiProvider = saved.0; s.aiBaseURL = saved.1; s.aiModel = saved.2
            s.aiAgentModel = saved.3; s.aiInlineModel = saved.4; s.aiCLIPath = saved.5
        }
        s.aiProvider = provider; s.aiBaseURL = baseURL; s.aiModel = model
        s.aiAgentModel = agentModel; s.aiInlineModel = inlineModel; s.aiCLIPath = cliPath
        return try body(s)
    }

    func testCurrent_chatScene_usesBaseModel() {
        withAISettings(model: "gpt-4o", agentModel: "agent-x", inlineModel: "inline-x") { s in
            XCTAssertEqual(AIConfig.current(s, scene: .chat).model, "gpt-4o")
        }
    }

    func testCurrent_agentScene_prefersAgentModel() {
        withAISettings(model: "base", agentModel: "agent-x") { s in
            XCTAssertEqual(AIConfig.current(s, scene: .agent).model, "agent-x")
        }
    }

    func testCurrent_agentScene_emptyAgentModel_fallsBackToBase() {
        withAISettings(model: "base", agentModel: "   ") { s in
            XCTAssertEqual(AIConfig.current(s, scene: .agent).model, "base",
                           "空白 agent 模型应回退到主模型")
        }
    }

    func testCurrent_inlineScene_prefersInlineModel() {
        withAISettings(model: "base", inlineModel: "inline-x") { s in
            XCTAssertEqual(AIConfig.current(s, scene: .inline).model, "inline-x")
        }
    }

    func testCurrent_inlineScene_emptyInlineModel_fallsBackToBase() {
        withAISettings(model: "base", inlineModel: "") { s in
            XCTAssertEqual(AIConfig.current(s, scene: .inline).model, "base")
        }
    }

    func testCurrent_beautifyScene_usesBaseModel() {
        withAISettings(model: "base", agentModel: "agent-x", inlineModel: "inline-x") { s in
            XCTAssertEqual(AIConfig.current(s, scene: .beautify).model, "base")
        }
    }

    func testCurrent_mapsProviderKindAndTrimsWhitespace() {
        withAISettings(provider: "anthropic", baseURL: "  https://api.anthropic.com/v1  ") { s in
            let cfg = AIConfig.current(s)
            XCTAssertEqual(cfg.kind, .anthropic)
            XCTAssertEqual(cfg.baseURL, "https://api.anthropic.com/v1", "baseURL 应去空白")
        }
    }

    func testCurrent_unknownProviderRawValue_mapsToDisabled() {
        withAISettings(provider: "bogus-provider") { s in
            XCTAssertEqual(AIConfig.current(s).kind, .disabled)
        }
    }

    // MARK: - AIPresets 一致性

    func testPresets_idsUnique() {
        let ids = AIPresets.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "preset id 不得重复")
    }

    func testPresets_baseURLsValidHTTPSOrLocalhost() {
        for p in AIPresets.all {
            let url = URL(string: p.baseURL)
            XCTAssertNotNil(url, "\(p.id) baseURL 非法：\(p.baseURL)")
            let scheme = url?.scheme ?? ""
            XCTAssertTrue(scheme == "https" || p.baseURL.hasPrefix("http://localhost"),
                          "\(p.id) 应使用 https（本地 Ollama 除外），实际：\(p.baseURL)")
        }
    }

    func testPresets_modelsNonEmpty() {
        for p in AIPresets.all {
            XCTAssertFalse(p.models.isEmpty, "\(p.id) 应提供内置模型清单")
            XCTAssertFalse(p.models.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty },
                           "\(p.id) 含空白模型名")
        }
    }

    func testPresets_anthropicPresetUsesAnthropicKind() {
        let anthropic = AIPresets.all.first { $0.id == "anthropic" }
        XCTAssertEqual(anthropic?.kind, .anthropic)
        XCTAssertTrue(AIPresets.all.filter { $0.kind == .anthropic }.count == 1,
                      "只有 Anthropic 官方 preset 应使用 anthropic kind")
    }

    func testPresets_match_exactBaseURL() {
        let m = AIPresets.match("https://api.openai.com/v1")
        XCTAssertEqual(m?.id, "openai")
    }

    func testPresets_match_trimsSurroundingWhitespace() {
        let m = AIPresets.match("  https://api.deepseek.com/v1  ")
        XCTAssertEqual(m?.id, "deepseek")
    }

    func testPresets_match_unknownURL_returnsNil() {
        XCTAssertNil(AIPresets.match("https://example.com/v1"))
        XCTAssertNil(AIPresets.match(""))
    }

    func testPresets_match_coversEveryPreset() {
        // 每个 preset 的 baseURL 都应能被 match 回自己（无 baseURL 撞车）
        for p in AIPresets.all {
            XCTAssertEqual(AIPresets.match(p.baseURL)?.id, p.id,
                           "\(p.id) 的 baseURL 与其他 preset 撞车")
        }
    }

    // MARK: - AIProviderKind

    func testProviderKind_rawValueRoundtrip() {
        for kind in AIProviderKind.allCases {
            XCTAssertEqual(AIProviderKind(rawValue: kind.rawValue), kind)
        }
    }

    func testProviderKind_labelKeysNonEmptyAndDistinct() {
        let keys = AIProviderKind.allCases.map(\.labelKey)
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertTrue(keys.allSatisfy { $0.hasPrefix("ai.provider.") })
    }

    // MARK: - AIError 映射

    func testAIError_descriptionsNonEmpty() {
        let errors: [AIError] = [
            .notConfigured, .badURL, .server(429, "rate limited"),
            .cliNotFound("/usr/local/bin/claude"), .cliFailed("boom"), .network("offline")
        ]
        for e in errors {
            XCTAssertFalse((e.errorDescription ?? "").isEmpty, "\(e) 缺错误描述")
        }
    }

    func testAIError_serverDescription_containsCodeAndMessage() {
        let desc = AIError.server(503, "overloaded").errorDescription ?? ""
        XCTAssertTrue(desc.contains("503"), "应包含状态码，实际：\(desc)")
        XCTAssertTrue(desc.contains("overloaded"), "应包含服务端消息，实际：\(desc)")
    }

    func testAIError_cliNotFoundDescription_containsPath() {
        let desc = AIError.cliNotFound("/opt/claude").errorDescription ?? ""
        XCTAssertTrue(desc.contains("/opt/claude"), "实际：\(desc)")
    }

    func testAIError_networkDescription_wrapsUnderlyingMessage() {
        let desc = AIError.network("connection lost").errorDescription ?? ""
        XCTAssertTrue(desc.contains("connection lost"), "实际：\(desc)")
    }

    // MARK: - AIAPIKeyStore（UserDefaults 明文存储，save/load/clear 闭环）

    func testAPIKeyStore_saveLoadClearRoundtrip() {
        let original = AIAPIKeyStore.load()
        defer {
            if let original { AIAPIKeyStore.save(original) } else { AIAPIKeyStore.clear() }
        }

        AIAPIKeyStore.save("sk-test-123")
        XCTAssertEqual(AIAPIKeyStore.load(), "sk-test-123")
        XCTAssertTrue(AIAPIKeyStore.hasKey)

        AIAPIKeyStore.clear()
        XCTAssertNil(AIAPIKeyStore.load())
        XCTAssertFalse(AIAPIKeyStore.hasKey)
    }

    func testAPIKeyStore_saveTrimsWhitespace() {
        let original = AIAPIKeyStore.load()
        defer {
            if let original { AIAPIKeyStore.save(original) } else { AIAPIKeyStore.clear() }
        }

        AIAPIKeyStore.save("  sk-padded\n")
        XCTAssertEqual(AIAPIKeyStore.load(), "sk-padded")
    }

    func testAPIKeyStore_saveEmpty_clearsKey() {
        let original = AIAPIKeyStore.load()
        defer {
            if let original { AIAPIKeyStore.save(original) } else { AIAPIKeyStore.clear() }
        }

        AIAPIKeyStore.save("sk-temp")
        AIAPIKeyStore.save("   ")
        XCTAssertNil(AIAPIKeyStore.load(), "保存空白应清除已存的 key")
    }

    // MARK: - AIMessage

    func testAIMessage_rolesDistinct() {
        let sys = AIMessage(role: .system, content: "s")
        let usr = AIMessage(role: .user, content: "u")
        XCTAssertNotEqual(sys.role.rawValue, usr.role.rawValue)
        XCTAssertEqual(AIMessage.Role.assistant.rawValue, "assistant")
    }
}
