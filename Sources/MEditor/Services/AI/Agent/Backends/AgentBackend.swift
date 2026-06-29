import Foundation

// MARK: - AgentBackend Protocol

/// 每种 AI 后端实现此协议，AgentRunner 通过协议调用，不感知具体后端。
/// 新增后端（Gemini、Anthropic API、本地 LLM）只需实现此协议，无需改 Runner。
protocol AgentBackend: Sendable {
    func complete(
        messages: [AgentMessage],
        tools: [any AgentTool]
    ) async throws -> AgentCompletionResponse
}

// MARK: - Agent completion response

struct AgentCompletionResponse: Sendable {
    var text: String
    var toolCalls: [AgentToolCall]
    var finishReason: String  // "stop" | "tool_calls" | "length"
}

// MARK: - Agent AI Message (extended with tool roles)

struct AgentMessage: Sendable {
    enum Role: String, Sendable {
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
            assertionFailure("asAIMessage called on tool-role message — use openAIDict instead")
            return AIMessage(role: .user, content: content)
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
                    // Re-serialize arguments back to JSON for wire format
                    let argsDict = call.arguments.reduce(into: [String: Any]()) { $0[$1.key] = unwrap($1.value) }
                    let argsData = (try? JSONSerialization.data(withJSONObject: argsDict)) ?? Data()
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

    private func unwrap(_ v: AnySendableValue) -> Any {
        switch v {
        case .string(let s):  return s
        case .bool(let b):    return b
        case .int(let i):     return i
        case .double(let d):  return d
        case .null:           return NSNull()
        case .array(let arr): return arr.map { unwrap($0) }
        case .dict(let d):    return d.reduce(into: [String: Any]()) { $0[$1.key] = unwrap($1.value) }
        }
    }
}

// MARK: - Factory

/// 根据 AIConfig 创建对应 backend，外部只需调用这一个入口
enum AgentBackendFactory {
    static func make(config: AIConfig) -> any AgentBackend {
        switch config.kind {
        case .disabled:   return DisabledBackend()
        case .openai:     return OpenAIBackend(config: config)
        case .claudeCLI:  return ClaudeCLIBackend(config: config)
        }
    }
}
