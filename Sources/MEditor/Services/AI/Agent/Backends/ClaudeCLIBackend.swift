import Foundation

// MARK: - Claude CLI Backend（XML 模拟工具调用）

struct ClaudeCLIBackend: AgentBackend {
    let config: AIConfig

    // MARK: - Intent

    private enum Intent {
        case fileManage  // 明确的文件创建/目录操作
        case command     // 明确的命令执行
        case mixed       // 其余情况（安全干默）
    }

    /// 根据最近 3 条用户消息推断意图（保守策略：宁可 mixed 也不误杀工具）
    private func inferIntent(from messages: [AgentMessage]) -> Intent {
        let text = messages
            .filter { $0.role == .user }
            .suffix(3)
            .map { $0.content.lowercased() }
            .joined(separator: " ")

        // command：要求精确词组，避免 "runtime" / "run through" 误触
        let commandPhrases = ["run command", "run script", "execute command", "bash ", "shell ",
                              "运行命令", "执行命令", "执行脚本"]
        if commandPhrases.contains(where: { text.contains($0) }) { return .command }

        // fileManage：明确的文件创建/目录操作
        let fileManagePhrases = ["create file", "new file", "mkdir", "create directory",
                                 "新建文件", "创建文件", "创建目录", "新建目录"]
        if fileManagePhrases.contains(where: { text.contains($0) }) { return .fileManage }

        // 其余情况统一 mixed，不强制分类（风险大于收益）
        return .mixed
    }

    /// 按意图过滤工具。
    /// 原则：只排除「当前意图绝对用不到」的重型工具；
    /// 核心读写工具（read/patch/write）始终保留，防止 AI 读完文件想修改时无工具可用。
    /// 过滤后为空时自动回退全量（防止自定义工具全被剔除）。
    private func selectTools(_ tools: [any AgentTool], intent: Intent) -> [any AgentTool] {
        let excluded: Set<String>
        switch intent {
        case .command:                           // 执行命令：不排除任何工具（AI 可能需要先读文件）
            return tools
        case .fileManage:                        // 文件管理：排除命令执行
            excluded = ["run_command"]
        case .mixed:                             // 混合：不排除
            return tools
        }
        let result = tools.filter { !excluded.contains($0.spec.name) }
        return result.isEmpty ? tools : result   // 空结果时回退全量
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
