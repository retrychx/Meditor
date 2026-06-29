import Foundation

// MARK: - Disabled Backend

struct DisabledBackend: AgentBackend {
    func complete(messages: [AgentMessage], tools: [any AgentTool]) async throws -> AgentCompletionResponse {
        AgentCompletionResponse(text: "AI 未配置，请在设置中启用", toolCalls: [], finishReason: "stop")
    }
}

// MARK: - OpenAI Backend（兼容所有 OpenAI-compatible API）

struct OpenAIBackend: AgentBackend {
    let config: AIConfig

    func complete(
        messages: [AgentMessage],
        tools: [any AgentTool]
    ) async throws -> AgentCompletionResponse {
        guard config.isConfigured else { throw AIError.notConfigured }

        let endpoint = config.baseURL.hasSuffix("/")
            ? config.baseURL + "chat/completions"
            : config.baseURL + "/chat/completions"
        guard let url = URL(string: endpoint) else { throw AIError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.timeoutInterval = 120

        var payload: [String: Any] = [
            "model": config.model,
            "stream": false,
            "messages": messages.map { $0.openAIDict }
        ]
        if !tools.isEmpty {
            payload["tools"] = tools.map { $0.spec.openAIDict }
            payload["tool_choice"] = "auto"
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.network("Invalid response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AIError.server(http.statusCode, body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let choice = choices.first,
              let message = choice["message"] as? [String: Any]
        else {
            throw AgentError.parseError("无法解析响应")
        }

        let text = message["content"] as? String ?? ""
        let finishReason = choice["finish_reason"] as? String ?? "stop"

        var toolCalls: [AgentToolCall] = []
        if let rawCalls = message["tool_calls"] as? [[String: Any]] {
            for raw in rawCalls {
                guard let id   = raw["id"] as? String,
                      let fn   = raw["function"] as? [String: Any],
                      let name = fn["name"] as? String,
                      let args = fn["arguments"] as? String
                else { continue }
                toolCalls.append(AgentToolCall(id: id, name: name, argumentsJSON: args))
            }
        }

        return AgentCompletionResponse(text: text, toolCalls: toolCalls, finishReason: finishReason)
    }
}
