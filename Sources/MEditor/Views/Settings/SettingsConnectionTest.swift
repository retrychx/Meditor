import SwiftUI

// MARK: - Connection test / model refresh

extension SettingsView {
    @MainActor
    func runConnectionTest() async {
        connectionTesting = true
        connectionTestResult = nil
        let baseURL = settings.aiBaseURL.trimmingCharacters(in: .whitespaces)
        let apiKey = AIAPIKeyStore.load() ?? ""
        let model = settings.aiModel.isEmpty ? "gpt-4o-mini" : settings.aiModel
        let isAnthropic = baseURL.lowercased().contains("anthropic")

        do {
            let resultModel = try await performConnectionTest(
                baseURL: baseURL, apiKey: apiKey, model: model, isAnthropic: isAnthropic
            )
            connectionTestOK = true
            connectionTestResult = "✓ 连接成功（model: \(resultModel)）"
        } catch {
            connectionTestOK = false
            connectionTestResult = "✗ 连接失败：\(error.localizedDescription)"
        }
        connectionTesting = false
    }

    private func performConnectionTest(
        baseURL: String, apiKey: String, model: String, isAnthropic: Bool
    ) async throws -> String {
        guard !baseURL.isEmpty else { throw URLError(.badURL) }
        // 连接测试与聊天/Agent 共用 RestAgentBackend 的请求构造（wire format 唯一来源）；
        // 仅收紧超时（10s）与负载（单条 "hi"，非流式）。
        let config = AIConfig(
            kind: isAnthropic ? .anthropic : .openai,
            baseURL: baseURL,
            model: model,
            cliPath: "",
            cliModel: "",
            apiKey: apiKey,
            requestTimeoutSeconds: 10
        )
        let backend = RestAgentBackend(config: config, wire: isAnthropic ? .anthropic : .openAI)
        _ = try await backend.complete(
            messages: [AgentMessage(role: .user, content: "hi")],
            tools: []
        )
        return model
    }

    func refreshModels() {
        aiLoadingModels = true
        let base = settings.aiBaseURL
        let key = AIAPIKeyStore.load() ?? ""
        Task {
            let models = await AIClient.fetchModels(baseURL: base, apiKey: key)
            await MainActor.run {
                aiModels = models
                aiLoadingModels = false
            }
        }
    }
}
