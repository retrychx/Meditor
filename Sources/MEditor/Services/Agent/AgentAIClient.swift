import Foundation

// MARK: - Agent AI Message (extended with tool roles)

struct AgentMessage: Sendable {
    enum Role: String, Sendable {
        case system, user, assistant, tool
    }

    var role: Role
    var content: String
    /// For assistant messages that contained tool calls
    var toolCalls: [AgentToolCall]?
    /// For tool result messages
    var toolCallID: String?
    var toolName: String?

    // Convert to standard AIMessage (for streaming path)
    var asAIMessage: AIMessage {
        AIMessage(role: role == .user ? .user : role == .assistant ? .assistant : .system,
                  content: content)
    }

    // OpenAI wire format
    var openAIDict: [String: Any] {
        switch role {
        case .system:
            return ["role": "system", "content": content]
        case .user:
            return ["role": "user", "content": content]
        case .assistant:
            var d: [String: Any] = ["role": "assistant"]
            if let calls = toolCalls, !calls.isEmpty {
                d["content"] = content.isEmpty ? nil : content as Any
                d["tool_calls"] = calls.map { call -> [String: Any] in
                    let argsData = (try? JSONSerialization.data(withJSONObject: call.arguments)) ?? Data()
                    let argsStr = String(data: argsData, encoding: .utf8) ?? "{}"
                    return [
                        "id": call.id,
                        "type": "function",
                        "function": ["name": call.name, "arguments": argsStr] as [String: Any]
                    ]
                }
            } else {
                d["content"] = content
            }
            return d
        case .tool:
            return [
                "role": "tool",
                "tool_call_id": toolCallID ?? "",
                "content": content
            ]
        }
    }
}

// MARK: - Agent completion response

struct AgentCompletionResponse: Sendable {
    var text: String
    var toolCalls: [AgentToolCall]
    var finishReason: String  // "stop" | "tool_calls" | "length"
}

// MARK: - AgentAIClient  (wraps AIClient with function-calling support)

struct AgentAIClient: Sendable {
    let config: AIConfig

    // MARK: - Function-calling completion (non-streaming)

    func complete(
        messages: [AgentMessage],
        tools: [any AgentTool]
    ) async throws -> AgentCompletionResponse {
        switch config.kind {
        case .disabled:
            return AgentCompletionResponse(text: "AI 未配置，请在设置中启用", toolCalls: [], finishReason: "stop")
        case .openai:
            return try await openAIComplete(messages: messages, tools: tools)
        case .claudeCLI:
            return try await claudeCLIComplete(messages: messages, tools: tools)
        }
    }

    // MARK: - OpenAI function calling

    private func openAIComplete(
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

        // Parse tool calls
        var toolCalls: [AgentToolCall] = []
        if let rawCalls = message["tool_calls"] as? [[String: Any]] {
            for raw in rawCalls {
                guard let id = raw["id"] as? String,
                      let fn = raw["function"] as? [String: Any],
                      let name = fn["name"] as? String,
                      let argsStr = fn["arguments"] as? String
                else { continue }
                toolCalls.append(AgentToolCall(id: id, name: name, argumentsJSON: argsStr))
            }
        }

        return AgentCompletionResponse(text: text, toolCalls: toolCalls, finishReason: finishReason)
    }

    // MARK: - Claude CLI (XML tool simulation)

    private func claudeCLIComplete(
        messages: [AgentMessage],
        tools: [any AgentTool]
    ) async throws -> AgentCompletionResponse {
        // Build a text-based tool calling system for Claude
        // Tools are described in XML, Claude outputs <tool_call> tags

        var systemPrompt = messages.first(where: { $0.role == .system })?.content ?? ""

        if !tools.isEmpty {
            systemPrompt += """


---

## Available Tools

You have access to the following tools. To call a tool, output EXACTLY this XML block on its own line — nothing before or after on the same line:

<tool_call>
<name>TOOL_NAME</name>
<arguments>{"key": "value"}</arguments>
</tool_call>

Wait for the tool result before continuing. When finished, output your final response as normal text.

### Tools:

"""
            systemPrompt += tools.map { $0.spec.claudeXMLDescription }.joined(separator: "\n\n")
        }

        // Build conversation text for Claude CLI
        var conversationParts: [String] = []
        for msg in messages.dropFirst(where: { $0.role == .system }) {
            switch msg.role {
            case .user:
                conversationParts.append("Human: \(msg.content)")
            case .assistant:
                conversationParts.append("Assistant: \(msg.content)")
            case .tool:
                conversationParts.append("Tool Result [\(msg.toolName ?? "")]: \(msg.content)")
            default:
                break
            }
        }
        conversationParts.append("Assistant:")
        let conversationText = conversationParts.joined(separator: "\n\n")

        // Run Claude CLI
        let cliMessages = [
            AIMessage(role: .system, content: systemPrompt),
            AIMessage(role: .user, content: conversationText)
        ]

        var accumulated = ""
        for try await chunk in AIClient(config: config).stream(cliMessages) {
            accumulated += chunk
        }

        // Parse tool calls from output
        let toolCalls = parseClaudeToolCalls(from: accumulated)
        let text = removeToolCallTags(from: accumulated)
        let finishReason = toolCalls.isEmpty ? "stop" : "tool_calls"

        return AgentCompletionResponse(text: text, toolCalls: toolCalls, finishReason: finishReason)
    }

    private func parseClaudeToolCalls(from text: String) -> [AgentToolCall] {
        var calls: [AgentToolCall] = []
        let pattern = #"<tool_call>\s*<name>(.*?)</name>\s*<arguments>(.*?)</arguments>\s*</tool_call>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return calls
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            guard match.numberOfRanges == 3 else { continue }
            let name = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let argsStr = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            let id = "claude-\(calls.count)-\(name)"
            calls.append(AgentToolCall(id: id, name: name, argumentsJSON: argsStr))
        }
        return calls
    }

    private func removeToolCallTags(from text: String) -> String {
        let pattern = #"<tool_call>.*?</tool_call>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return text
        }
        let result = regex.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: ""
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Convenience: skip system messages in dropFirst

private extension Array {
    func dropFirst(where predicate: (Element) -> Bool) -> ArraySlice<Element> {
        guard let idx = firstIndex(where: predicate) else { return self[...] }
        var result = self
        result.remove(at: idx)
        return result[...]
    }
}
