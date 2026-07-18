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

    /// 可注入的 URLSession（测试用）。nil 时使用进程级共享 session（复用连接池）。
    let sessionOverride: (any URLSessionDataProtocol)?

    init(config: AIConfig, wire: WireProtocol, session: (any URLSessionDataProtocol)? = nil) {
        self.config = config
        self.wire = wire
        self.sessionOverride = session
    }

    /// 进程级共享 session：复用连接池（HTTP/2 多路复用），避免每次请求新建
    /// URLSession 的线程/缓存开销。细粒度超时在各 request 的 timeoutInterval 上设置。
    private static let sharedSession: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForResource = 3600   // 兜底上限；请求级超时由 URLRequest 控制
        return URLSession(configuration: c)
    }()

    /// 返回实际使用的 session：有注入时用注入的，否则用共享 session。
    var resolvedSession: any URLSessionDataProtocol { sessionOverride ?? Self.sharedSession }

    // MARK: - AgentBackend

    func complete(
        messages: [AgentMessage],
        tools: [any AgentTool]
    ) async throws -> AgentCompletionResponse {
        guard config.isConfigured else { throw AIError.notConfigured }
        let req = try buildRequest(messages: messages, tools: tools)
        return try await withRetry {
            let (data, response) = try await resolvedSession.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw AIError.network("Invalid response type")
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "(empty)"
                throw AIError.server(http.statusCode, body)
            }
            return try self.parseResponse(data: data)
        }
    }

    // MARK: - Retry helper（429 / 503 指数退避，最多重试 2 次）

    private func withRetry<T: Sendable>(
        maxAttempts: Int = 3,
        _ block: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        var delayNs: UInt64 = 1_000_000_000  // 1s
        for attempt in 1...maxAttempts {
            do {
                return try await block()
            } catch AIError.server(let code, _) where (code == 429 || code == 503) && attempt < maxAttempts {
                lastError = AIError.server(code, "retrying (attempt \(attempt))")
                try? await Task.sleep(nanoseconds: delayNs)
                delayNs *= 2
            } catch {
                throw error
            }
        }
        throw lastError ?? AIError.network("retry exhausted")
    }

    // MARK: - Streaming

    func completeStreaming(
        messages: [AgentMessage],
        tools: [any AgentTool],
        onTextChunk: @escaping @Sendable (String) -> Void
    ) async throws -> AgentCompletionResponse {
        guard config.isConfigured else { throw AIError.notConfigured }
        switch wire {
        case .openAI:    return try await streamOpenAI(messages: messages, tools: tools, onTextChunk: onTextChunk)
        case .anthropic: return try await streamAnthropic(messages: messages, tools: tools, onTextChunk: onTextChunk)
        }
    }

    private func streamOpenAI(
        messages: [AgentMessage],
        tools: [any AgentTool],
        onTextChunk: @escaping @Sendable (String) -> Void
    ) async throws -> AgentCompletionResponse {
        let req = try openAIRequest(messages: messages, tools: tools, stream: true)
        let (bytes, response) = try await Self.sharedSession.bytes(for: req)
        guard let http = response as? HTTPURLResponse else { throw AIError.network("invalid response") }
        guard (200..<300).contains(http.statusCode) else {
            var body = ""
            for try await line in bytes.lines { body += line; if body.count > 500 { break } }
            throw AIError.server(http.statusCode, body)
        }

        struct ToolCallAcc { var id = ""; var name = ""; var args = "" }
        var accText = ""
        var toolByIndex: [Int: ToolCallAcc] = [:]
        var finishReason = "stop"

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let choice = choices.first else { continue }

            if let fr = choice["finish_reason"] as? String, fr != "null", !fr.isEmpty {
                finishReason = fr
            }
            guard let delta = choice["delta"] as? [String: Any] else { continue }

            if let content = delta["content"] as? String, !content.isEmpty {
                accText += content
                onTextChunk(content)
            }
            if let tcs = delta["tool_calls"] as? [[String: Any]] {
                for tc in tcs {
                    guard let index = tc["index"] as? Int else { continue }
                    var acc = toolByIndex[index] ?? ToolCallAcc()
                    if let id = tc["id"] as? String { acc.id = id }
                    if let fn = tc["function"] as? [String: Any] {
                        if let name = fn["name"] as? String { acc.name = name }
                        if let args = fn["arguments"] as? String { acc.args += args }
                    }
                    toolByIndex[index] = acc
                }
            }
        }

        let toolCalls = toolByIndex.sorted { $0.key < $1.key }.compactMap { _, acc -> AgentToolCall? in
            guard !acc.id.isEmpty, !acc.name.isEmpty else { return nil }
            return AgentToolCall(id: acc.id, name: acc.name, argumentsJSON: acc.args.isEmpty ? "{}" : acc.args)
        }
        return AgentCompletionResponse(text: accText, toolCalls: toolCalls, finishReason: finishReason)
    }

    private func streamAnthropic(
        messages: [AgentMessage],
        tools: [any AgentTool],
        onTextChunk: @escaping @Sendable (String) -> Void
    ) async throws -> AgentCompletionResponse {
        let req = try anthropicRequest(messages: messages, tools: tools, stream: true)
        let (bytes, response) = try await Self.sharedSession.bytes(for: req)
        guard let http = response as? HTTPURLResponse else { throw AIError.network("invalid response") }
        guard (200..<300).contains(http.statusCode) else {
            var body = ""
            for try await line in bytes.lines { body += line; if body.count > 500 { break } }
            throw AIError.server(http.statusCode, body)
        }

        struct ToolUseAcc { var id = ""; var name = ""; var inputJSON = "" }
        var accText = ""
        var toolByIndex: [Int: ToolUseAcc] = [:]
        var stopReason = "end_turn"

        for try await line in bytes.lines {
            // Anthropic SSE: ignore event lines, only parse data lines
            guard line.hasPrefix("data:") else { continue }
            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = obj["type"] as? String else { continue }

            switch type {
            case "content_block_start":
                guard let index = obj["index"] as? Int,
                      let block = obj["content_block"] as? [String: Any],
                      let blockType = block["type"] as? String,
                      blockType == "tool_use" else { continue }
                var acc = ToolUseAcc()
                acc.id   = block["id"]   as? String ?? ""
                acc.name = block["name"] as? String ?? ""
                toolByIndex[index] = acc

            case "content_block_delta":
                guard let index = obj["index"] as? Int,
                      let delta = obj["delta"] as? [String: Any],
                      let deltaType = delta["type"] as? String else { continue }
                if deltaType == "text_delta", let text = delta["text"] as? String {
                    accText += text
                    onTextChunk(text)
                } else if deltaType == "input_json_delta",
                          let partial = delta["partial_json"] as? String {
                    toolByIndex[index]?.inputJSON += partial
                }

            case "message_delta":
                if let delta = obj["delta"] as? [String: Any],
                   let sr = delta["stop_reason"] as? String {
                    stopReason = sr
                }

            default: break
            }
        }

        let toolCalls = toolByIndex.sorted { $0.key < $1.key }.compactMap { _, acc -> AgentToolCall? in
            guard !acc.id.isEmpty, !acc.name.isEmpty else { return nil }
            return AgentToolCall(id: acc.id, name: acc.name, argumentsJSON: acc.inputJSON.isEmpty ? "{}" : acc.inputJSON)
        }
        let finishReason = stopReason == "tool_use" ? "tool_calls" : "stop"
        return AgentCompletionResponse(text: accText, toolCalls: toolCalls, finishReason: finishReason)
    }

    // MARK: - Request Building

    private func buildRequest(messages: [AgentMessage], tools: [any AgentTool]) throws -> URLRequest {
        switch wire {
        case .openAI:    return try openAIRequest(messages: messages, tools: tools)
        case .anthropic: return try anthropicRequest(messages: messages, tools: tools)
        }
    }

    // ── OpenAI ────────────────────────────────────────────────────────────────

    private func openAIRequest(messages: [AgentMessage], tools: [any AgentTool], stream: Bool = false) throws -> URLRequest {
        let base     = config.baseURL.hasSuffix("/") ? config.baseURL : config.baseURL + "/"
        let endpoint = base + "chat/completions"
        guard let url = URL(string: endpoint) else { throw AIError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod    = "POST"
        req.timeoutInterval = config.requestTimeoutSeconds
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if stream { req.setValue("text/event-stream", forHTTPHeaderField: "Accept") }
        if !config.apiKey.isEmpty {
            req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        var payload: [String: Any] = [
            "model":    config.model,
            "stream":   stream,
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

    private func anthropicRequest(messages: [AgentMessage], tools: [any AgentTool], stream: Bool = false) throws -> URLRequest {
        let base     = config.baseURL.isEmpty ? "https://api.anthropic.com/v1" : config.baseURL
        let norm     = base.hasSuffix("/") ? base : base + "/"
        let endpoint = norm + "messages"
        guard let url = URL(string: endpoint) else { throw AIError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod    = "POST"
        req.timeoutInterval = config.requestTimeoutSeconds
        req.setValue("application/json",  forHTTPHeaderField: "Content-Type")
        if stream { req.setValue("text/event-stream", forHTTPHeaderField: "Accept") }
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
        if stream       { payload["stream"] = true }
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
