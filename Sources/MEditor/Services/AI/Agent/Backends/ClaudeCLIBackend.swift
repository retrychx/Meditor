import Foundation

// MARK: - Claude CLI Backend（XML 模拟工具调用）

struct ClaudeCLIBackend: AgentBackend {
    let config: AIConfig

    func complete(
        messages: [AgentMessage],
        tools: [any AgentTool]
    ) async throws -> AgentCompletionResponse {
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

IMPORTANT:
- The <arguments> block MUST contain valid JSON.
- Wait for the tool result before continuing.
- When finished, output your final response as normal text.
- NEVER refuse a tool call by saying you lack permissions — use the tool directly.

### Tools:

"""
            systemPrompt += tools.map { $0.spec.claudeXMLDescription }.joined(separator: "\n\n")
        }

        // Build conversation text (skip system message, already in systemPrompt)
        var parts: [String] = []
        for msg in messages.filter({ $0.role != .system }) {
            switch msg.role {
            case .user:
                parts.append("Human: \(msg.content)")
            case .assistant:
                parts.append("Assistant: \(msg.content)")
            case .tool:
                parts.append("Tool Result [\(msg.toolName ?? "")]: \(msg.content)")
            default:
                break
            }
        }
        parts.append("Assistant:")
        let conversationText = parts.joined(separator: "\n\n")

        let cliMessages = [
            AIMessage(role: .system, content: systemPrompt),
            AIMessage(role: .user,   content: conversationText)
        ]

        var accumulated = ""
        for try await chunk in AIClient(config: config).stream(cliMessages) {
            accumulated += chunk
        }

        let toolCalls = parseToolCalls(from: accumulated)

        // 只在解析到工具调用时才清理 XML 标签，保留正常文本
        let text = toolCalls.isEmpty ? accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
                                     : removeToolCallTags(from: accumulated)
        let finishReason = toolCalls.isEmpty ? "stop" : "tool_calls"

        return AgentCompletionResponse(text: text, toolCalls: toolCalls, finishReason: finishReason)
    }

    // MARK: - XML Parsing（带容错）

    private func parseToolCalls(from text: String) -> [AgentToolCall] {
        var calls: [AgentToolCall] = []

        // 主模式：标准格式
        let pattern = #"<tool_call>\s*<name>(.*?)</name>\s*<arguments>(.*?)</arguments>\s*</tool_call>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return calls
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            guard match.numberOfRanges == 3 else { continue }
            let name    = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let argsStr = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)

            // 验证 arguments 是合法 JSON，否则跳过该工具调用
            guard let argsData = argsStr.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: argsData)) != nil
            else {
                // 尝试修复常见问题：Claude 有时省略引号
                let repaired = attemptJSONRepair(argsStr)
                let id = "claude-\(calls.count)-\(name)"
                calls.append(AgentToolCall(id: id, name: name, argumentsJSON: repaired))
                continue
            }

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
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 简单 JSON 修复：补充缺失的引号（仅处理最常见情况）
    private func attemptJSONRepair(_ raw: String) -> String {
        // 如果已经是合法 JSON 就直接返回
        if let data = raw.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return raw
        }
        // 尝试包一层 {} 大括号（有时 Claude 输出裸 key: value）
        let wrapped = "{\(raw)}"
        if let data = wrapped.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            return wrapped
        }
        return raw
    }
}
