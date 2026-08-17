import Foundation

// MARK: - AgentBackend Protocol

/// 每种 AI 后端实现此协议，AgentRunner 通过协议调用，不感知具体后端。
/// 新增后端（Gemini、Anthropic API、本地 LLM）只需实现此协议，无需改 Runner。
protocol AgentBackend: Sendable {
    func complete(
        messages: [AgentMessage],
        tools: [any AgentTool]
    ) async throws -> AgentCompletionResponse

    /// 流式版本：文字 chunk 边生成边回调，工具调用结束后一次性返回完整 response。
    /// 默认实现回退到 complete()，不调用 onTextChunk。
    func completeStreaming(
        messages: [AgentMessage],
        tools: [any AgentTool],
        onTextChunk: @escaping @Sendable (String) -> Void
    ) async throws -> AgentCompletionResponse
}

extension AgentBackend {
    func completeStreaming(
        messages: [AgentMessage],
        tools: [any AgentTool],
        onTextChunk: @escaping @Sendable (String) -> Void
    ) async throws -> AgentCompletionResponse {
        try await complete(messages: messages, tools: tools)
    }
}

// MARK: - Agent completion response

struct AgentCompletionResponse: Sendable {
    var text: String
    var toolCalls: [AgentToolCall]
    var finishReason: String  // "stop" | "tool_calls" | "length"
    /// 本次响应的 token 用量。ClaudeCLI 子进程不返回 usage，保持 nil（默认），
    /// Runner 累计时跳过，UI 降级不显示。
    var usage: AgentUsage? = nil
}

// MARK: - Agent AI Message (extended with tool roles)

struct AgentMessage: Sendable, Codable {
    enum Role: String, Sendable, Codable {
        case system, user, assistant, tool
    }

    var role: Role
    var content: String
    var toolCalls: [AgentToolCall]?
    var toolCallID: String?
    var toolName: String?

    // Convert to standard AIMessage (system/user/assistant only)
    var asAIMessage: AIMessage {
        switch role {
        case .system:    return AIMessage(role: .system,    content: content)
        case .user:      return AIMessage(role: .user,      content: content)
        case .assistant: return AIMessage(role: .assistant, content: content)
        case .tool:
            // tool-role 消息不应通过 asAIMessage 转换（应走 openAIDict）
            // Release 下安全降级为 user 消息，避免静默数据损坏导致 AI 行为异常
            return AIMessage(role: .user, content: "[tool result] " + content)
        }
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
                    // 优先回放后端返回的原始参数 JSON（保持历史与线上完全一致）；
                    // 缺失时（手工构造的 call）由强类型 arguments 重新序列化
                    let argsStr: String
                    if let raw = call.rawArgumentsJSON {
                        argsStr = raw
                    } else {
                        let argsDict = call.arguments.reduce(into: [String: Any]()) { $0[$1.key] = $1.value.anyValue }
                        let argsData = (try? JSONSerialization.data(withJSONObject: argsDict)) ?? Data()
                        argsStr = String(data: argsData, encoding: .utf8) ?? "{}"
                    }
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

// MARK: - Factory

/// 根据 AIConfig 创建对应 backend，外部只需调用这一个入口
enum AgentBackendFactory {
    static func make(config: AIConfig) -> any AgentBackend {
        switch config.kind {
        case .disabled:   return DisabledBackend()
        case .openai:     return RestAgentBackend(config: config, wire: .openAI)
        case .anthropic:  return RestAgentBackend(config: config, wire: .anthropic)
        case .claudeCLI:
#if os(macOS)
            return ClaudeCLIBackend(config: config)
#else
            // iOS 无 Process 子进程能力：claude CLI 后端不可用，降级为 Disabled
            return DisabledBackend()
#endif
        }
    }
}
