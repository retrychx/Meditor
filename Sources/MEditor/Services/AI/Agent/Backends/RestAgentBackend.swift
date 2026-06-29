import Foundation

// MARK: - Disabled Backend

struct DisabledBackend: AgentBackend {
    func complete(messages: [AgentMessage], tools: [any AgentTool]) async throws -> AgentCompletionResponse {
        AgentCompletionResponse(text: "AI 未配置，请在设置中启用", toolCalls: [], finishReason: "stop")
    }
}

// MARK: - Wire Protocol

/// HTTP 请求/响应的 wire 格式。
/// 新增 provider 只需在 AIPresets 里加条目并选择对应协议——Backend 代码不动。
enum WireProtocol: Sendable {
    case openAI     // POST /chat/completions  （覆盖 OpenAI / Ollama / OpenRouter / 各类代理）
    case anthropic  // POST /messages          （api.anthropic.com 直连 & 兼容实现）
}

// MARK: - REST Agent Backend

/// 统一 HTTP Backend，通过 WireProtocol 适配两种主流 API 格式。
/// 替代原 OpenAIBackend，同时承载 Anthropic 原生支持。
struct RestAgentBackend: AgentBackend {

    let config: AIConfig
    let wire: WireProtocol

    // MARK: - AgentBackend

    func complete(
        messages: [AgentMessage],
        tools: [any AgentTool]
    ) async throws -> AgentCompletionResponse {
        guard config.isConfigured else { throw AIError.notConfigured }

        let req = try buildRequest(messages: messages, tools: tools)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.network("Invalid response type")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(empty)"
            throw AIError.server(http.statusCode, body)
        }

        return try parseResponse(data: data)
    }

    // MARK: - Request Building

    private func buildRequest(messages: [AgentMessage], tools: [any AgentTool]) throws -> URLRequest {
        switch wire {
        case .openAI:    return try openAIRequest(messages: messages, tools: tools)
        case .anthropic: return try anthropicRequest(messages: messages, tools: tools)
        }
    }

    // ── OpenAI ────────────────────────────────────────────────────────────────

    private func openAIRequest(messages: [AgentMessage], tools: [any AgentTool]) throws -> URLRequest {
        let base     = config.baseURL.hasSuffix("/") ? config.baseURL : config.baseURL + "/"
        let endpoint = base + "chat/completions"
        guard let url = URL(string: endpoint) else { throw AIError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod    = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        var payload: [String: Any] = [
            "model":    config.model,
            "stream":   false,
            "messages": messages.map { $0.openAIDict }
        ]
        if !tools.isEmpty {
            payload["tools"]        = tools.map { $0.spec.openAIDict }
            payload["tool_choice"]  = "auto"
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return req
    }

    // ── Anthropic ─────────────────────────────────────────────────────────────

    private func anthropicRequest(messages: [AgentMessage], tools: [any AgentTool]) throws -> URLRequest {
        let base     = config.baseURL.isEmpty ? "https://api.anthropic.com/v1" : config.baseURL
        let norm     = base.hasSuffix("/") ? base : base + "/"
        let endpoint = norm + "messages"
        guard let url = URL(string: endpoint) else { throw AIError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod    = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        req.setValue(config.apiKey,       forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01",        forHTTPHeaderField: "anthropic-version")

        // system 单独提取，其余按 Anthropic 多轮格式组装
        let system = messages.first(where: { $0.role == .system })?.content ?? ""
        let convo  = buildAnthropicMessages(from: messages)

        var payload: [String: Any] = [
            "model":      config.model,
            "max_tokens": 8096,
            "messages":   convo
        ]
        if !system.isEmpty { payload["system"] = system }
        if !tools.isEmpty  { payload["tools"]  = tools.map { $0.spec.anthropicDict } }

        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return req
    }

    /// AgentMessage 数组 → Anthropic 多轮消息格式。
    ///
    /// Anthropic 约束：
    ///   - user / assistant 必须严格交替
    ///   - 工具结果以 tool_result 内容块写入 **user** 消息
    ///   - 同一个 user 轮次的多条工具结果合并到同一个 content 数组
    private func buildAnthropicMessages(from messages: [AgentMessage]) -> [[String: Any]] {
        var result: [[String: Any]] = []

        for msg in messages where msg.role != .system {
            switch msg.role {

            case .system: break   // 已在外层提取

            case .user:
                result.append(["role": "user", "content": msg.content])

            case .assistant:
                if let calls = msg.toolCalls, !calls.isEmpty {
                    // 有工具调用时 content 是数组：先文字（可选）、再 tool_use 块
                    var content: [[String: Any]] = []
                    if !msg.content.isEmpty {
                        content.append(["type": "text", "text": msg.content])
                    }
                    for call in calls {
                        content.append([
                            "type":  "tool_use",
                            "id":    call.id,
                            "name":  call.name,
                            "input": call.argumentsDict
                        ] as [String: Any])
                    }
                    result.append(["role": "assistant", "content": content])
                } else {
                    result.append(["role": "assistant", "content": msg.content])
                }

            case .tool:
                // tool_result 块归入 user 消息；若末尾已有 user 轮次则合并，否则新建
                let block: [String: Any] = [
                    "type":        "tool_result",
                    "tool_use_id": msg.toolCallID ?? "",
                    "content":     msg.content
                ]
                if var last = result.last, (last["role"] as? String) == "user" {
                    // 将上一条 user 消息的 content 升级为数组并追加
                    var blocks: [[String: Any]]
                    if let arr = last["content"] as? [[String: Any]] {
                        blocks = arr
                    } else if let str = last["content"] as? String, !str.isEmpty {
                        blocks = [["type": "text", "text": str]]
                    } else {
                        blocks = []
                    }
                    blocks.append(block)
                    last["content"] = blocks
                    result[result.count - 1] = last
                } else {
                    result.append(["role": "user", "content": [block]])
                }
            }
        }
        return result
    }

    // MARK: - Response Parsing

    private func parseResponse(data: Data) throws -> AgentCompletionResponse {
        switch wire {
        case .openAI:    return try parseOpenAI(data: data)
        case .anthropic: return try parseAnthropic(data: data)
        }
    }

    // ── OpenAI response ───────────────────────────────────────────────────────

    private func parseOpenAI(data: Data) throws -> AgentCompletionResponse {
        guard let json     = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices  = json["choices"] as? [[String: Any]],
              let choice   = choices.first,
              let message  = choice["message"] as? [String: Any]
        else { throw AgentError.parseError("无法解析 OpenAI 响应") }

        let text         = message["content"] as? String ?? ""
        let finishReason = choice["finish_reason"] as? String ?? "stop"

        let toolCalls: [AgentToolCall] = (message["tool_calls"] as? [[String: Any]] ?? [])
            .compactMap { raw in
                guard let id   = raw["id"] as? String,
                      let fn   = raw["function"] as? [String: Any],
                      let name = fn["name"] as? String,
                      let args = fn["arguments"] as? String
                else { return nil }
                return AgentToolCall(id: id, name: name, argumentsJSON: args)
            }

        return AgentCompletionResponse(text: text, toolCalls: toolCalls, finishReason: finishReason)
    }

    // ── Anthropic response ────────────────────────────────────────────────────

    private func parseAnthropic(data: Data) throws -> AgentCompletionResponse {
        guard let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]]
        else { throw AgentError.parseError("无法解析 Anthropic 响应") }

        let stopReason = json["stop_reason"] as? String ?? "end_turn"

        var text      = ""
        var toolCalls = [AgentToolCall]()

        for block in content {
            switch block["type"] as? String {
            case "text":
                text += block["text"] as? String ?? ""
            case "tool_use":
                guard let id    = block["id"] as? String,
                      let name  = block["name"] as? String,
                      let input = block["input"] as? [String: Any]
                else { continue }
                let argsJSON = (try? JSONSerialization.data(withJSONObject: input))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                toolCalls.append(AgentToolCall(id: id, name: name, argumentsJSON: argsJSON))
            default:
                break
            }
        }

        let finishReason = stopReason == "tool_use" ? "tool_calls" : "stop"
        return AgentCompletionResponse(text: text, toolCalls: toolCalls, finishReason: finishReason)
    }
}
