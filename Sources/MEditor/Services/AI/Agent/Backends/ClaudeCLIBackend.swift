import Foundation

// MARK: - Claude CLI Backend（XML 模拟工具调用）

struct ClaudeCLIBackend: AgentBackend {
    let config: AIConfig

    // MARK: - Intent

    private enum Intent {
        case readOnly, editing, fileManage, command, mixed
    }

    /// 根据最后一条用户消息推断意图
    private func inferIntent(from messages: [AgentMessage]) -> Intent {
        let text = messages.last(where: { $0.role == .user })?.content.lowercased() ?? ""
        if text.contains("run") || text.contains("execute") || text.contains("命令") || text.contains("运行") { return .command }
        if text.contains("create") || text.contains("新建") || text.contains("mkdir") || text.contains("创建") { return .fileManage }
        if text.contains("read") || text.contains("list") || text.contains("show")
           || text.contains("查看") || text.contains("列出") || text.contains("显示") { return .readOnly }
        if text.contains("edit") || text.contains("patch") || text.contains("write")
           || text.contains("replace") || text.contains("修改") || text.contains("替换") || text.contains("编辑") { return .editing }
        return .mixed
    }

    /// 按意图过滤工具，减少 system prompt token 占用
    private func selectTools(_ tools: [any AgentTool], intent: Intent) -> [any AgentTool] {
        switch intent {
        case .readOnly:
            let names: Set<String> = ["read_document", "list_files", "search_workspace", "search_document"]
            return tools.filter { names.contains($0.spec.name) }
        case .editing:
            let excluded: Set<String> = ["create_file", "create_directory", "run_command"]
            return tools.filter { !excluded.contains($0.spec.name) }
        case .fileManage:
            let names: Set<String> = ["create_file", "write_file", "list_files", "create_directory", "open_file", "read_document"]
            return tools.filter { names.contains($0.spec.name) }
        case .command:
            let names: Set<String> = ["run_command", "read_document", "list_files"]
            return tools.filter { names.contains($0.spec.name) }
        case .mixed:
            return tools
        }
    }

    // MARK: - complete

    func complete(
        messages: [AgentMessage],
        tools: [any AgentTool]
    ) async throws -> AgentCompletionResponse {
        var systemPrompt = messages.first(where: { $0.role == .system })?.content ?? ""

        if !tools.isEmpty {
            let intent   = inferIntent(from: messages)
            let selected = selectTools(tools, intent: intent)

            systemPrompt += """


---

## Available Tools

To call a tool, output EXACTLY this XML block on its own line:

<tool_call>
<name>TOOL_NAME</name>
<arguments>{"key": "value"}</arguments>
</tool_call>

Rules: arguments MUST be valid JSON • wait for result before continuing • never refuse a tool call.

### Tools (name(required: type, optional?: type) → description):

"""
            systemPrompt += selected.map { $0.spec.compactCLIDescription }.joined(separator: "\n")
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

            // 验证 arguments 是合法 JSON
            guard let argsData = argsStr.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: argsData)) != nil
            else {
                // 尝试一种明确修复：trim + 补充外层 {}
                let trimmed = argsStr.trimmingCharacters(in: .whitespacesAndNewlines)
                let repairCandidates = [trimmed, "{\(trimmed)}"]
                if let repaired = repairCandidates.first(where: {
                    guard let d = $0.data(using: .utf8) else { return false }
                    return (try? JSONSerialization.jsonObject(with: d)) != nil
                }) {
                    let id = "claude-\(calls.count)-\(name)"
                    calls.append(AgentToolCall(id: id, name: name, argumentsJSON: repaired))
                    continue
                }
                // 修复彻底失败 → 注入 _parse_error，让 AI 看到错误并重试
                let errID = "parse-err-\(calls.count)-\(name)"
                let safeRaw = String(argsStr.prefix(300))
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n")
                    .replacingOccurrences(of: "\r", with: "\\r")
                let errJSON = "{\"original_tool\": \"\(name)\", \"raw_arguments\": \"\(safeRaw)\", \"error\": \"Arguments JSON is malformed — please retry with valid JSON\"}"
                calls.append(AgentToolCall(id: errID, name: "_parse_error", argumentsJSON: errJSON))
                continue
            }
            // JSON 合法
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

}
