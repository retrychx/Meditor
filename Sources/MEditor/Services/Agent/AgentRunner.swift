import Foundation
import Observation

// MARK: - AgentRunner

/// Manages the multi-turn agent loop: AI decides → calls tools → gets results → continues.
/// Observable so views can bind to its state.
@MainActor
@Observable
final class AgentRunner {

    // MARK: - State

    var steps: [AgentRunnerStep] = []
    var isRunning: Bool = false
    var finalText: String = ""
    var error: String? = nil

    /// 流式 chunk 回调（主线程，可选）
    var onChunk: (@MainActor (String) -> Void)? = nil
    /// 完成回调（主线程，isRunning 已设为 false）
    var onComplete: (@MainActor () -> Void)? = nil

    // MARK: - Config

    private let maxSteps = 12
    private var runTask: Task<Void, Never>? = nil

    // MARK: - Run

    func run(
        systemPrompt: String,
        userMessage: String,
        tools: [any AgentTool],
        config: AIConfig,
        context: AgentContext
    ) {
        guard !isRunning else { return }

        // Reset
        steps = []
        finalText = ""
        error = nil
        isRunning = true

        runTask = Task { [weak self] in
            guard let self else { return }
            await self._run(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                tools: tools,
                config: config,
                context: context
            )
        }
    }

    func cancel() {
        runTask?.cancel()
        runTask = nil
        isRunning = false
        if finalText.isEmpty && error == nil {
            error = "已取消"
        }
    }

    // MARK: - Core loop

    private func _run(
        systemPrompt: String,
        userMessage: String,
        tools: [any AgentTool],
        config: AIConfig,
        context: AgentContext
    ) async {
        let client = AgentAIClient(config: config)
        var messages: [AgentMessage] = [
            AgentMessage(role: .system, content: systemPrompt),
            AgentMessage(role: .user,   content: userMessage)
        ]

        addStep(.thinking(label: "AI 思考中…"))

        var stepCount = 0

        while stepCount < maxSteps {
            stepCount += 1
            guard !Task.isCancelled else { break }

            do {
                let response = try await client.complete(messages: messages, tools: tools)

                if !response.toolCalls.isEmpty {
                    // AI wants to call tools
                    updateLastThinking(to: nil)

                    // Record assistant message with tool calls
                    messages.append(AgentMessage(
                        role: .assistant,
                        content: response.text,
                        toolCalls: response.toolCalls
                    ))

                    // Execute each tool
                    for call in response.toolCalls {
                        guard !Task.isCancelled else { break }
                        addStep(.toolCall(id: call.id, name: call.name, args: prettyArgs(call.arguments)))

                        var result: AgentToolResult
                        if let tool = tools.first(where: { $0.spec.name == call.name }) {
                            do {
                                let output = try await tool.execute(arguments: call.arguments, context: context)
                                result = AgentToolResult(toolCallID: call.id, toolName: call.name, content: output)
                            } catch {
                                result = AgentToolResult(
                                    toolCallID: call.id, toolName: call.name,
                                    content: "错误：\(error.localizedDescription)", isError: true
                                )
                            }
                        } else {
                            result = AgentToolResult(
                                toolCallID: call.id, toolName: call.name,
                                content: "未找到工具：\(call.name)", isError: true
                            )
                        }

                        updateLastToolCall(id: call.id, result: result)

                        messages.append(AgentMessage(
                            role: .tool,
                            content: result.content,
                            toolCallID: result.toolCallID,
                            toolName: result.toolName
                        ))
                    }

                    if response.finishReason == "tool_calls" || !response.toolCalls.isEmpty {
                        addStep(.thinking(label: "AI 处理结果…"))
                        continue   // Loop: let AI see tool results and decide next step
                    }
                } else {
                    // AI is done
                    updateLastThinking(to: nil)
                    finalText = response.text
                    await onChunk?(response.text)

                    messages.append(AgentMessage(role: .assistant, content: response.text))
                    addStep(.text(response.text))
                    break
                }
            } catch is CancellationError {
                break
            } catch {
                updateLastThinking(to: nil)
                self.error = error.localizedDescription
                break
            }
        }

        if stepCount >= maxSteps {
            self.error = "Agent 执行超过最大步数（\(maxSteps)）"
        }

        isRunning = false
        runTask = nil
    }

    // MARK: - Step management

    private func addStep(_ step: AgentRunnerStep) {
        steps.append(step)
    }

    private func updateLastThinking(to newLabel: String?) {
        guard let idx = steps.indices.last(where: {
            if case .thinking = steps[$0] { return true }
            return false
        }) else { return }
        if let label = newLabel {
            steps[idx] = .thinking(label: label)
        } else {
            steps.remove(at: idx)
        }
    }

    private func updateLastToolCall(id: String, result: AgentToolResult) {
        guard let idx = steps.indices.last(where: {
            if case .toolCall(let cid, _, _) = steps[$0], cid == id { return true }
            return false
        }) else { return }
        steps[idx] = .toolCallDone(
            id: id,
            name: result.toolName,
            args: "",
            result: result.content,
            isError: result.isError
        )
    }

    // MARK: - Helpers

    private func prettyArgs(_ args: [String: Any]) -> String {
        guard !args.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: args, options: .prettyPrinted),
              let str = String(data: data, encoding: .utf8)
        else { return "{}" }
        // Truncate long values
        if str.count > 200 {
            return String(str.prefix(200)) + "…"
        }
        return str
    }
}

// MARK: - Step model

enum AgentRunnerStep: Identifiable {
    case thinking(label: String)
    case toolCall(id: String, name: String, args: String)
    case toolCallDone(id: String, name: String, args: String, result: String, isError: Bool)
    case text(String)

    var id: String {
        switch self {
        case .thinking(let l):                       return "thinking-\(l)"
        case .toolCall(let id, _, _):               return "call-\(id)"
        case .toolCallDone(let id, _, _, _, _):     return "done-\(id)"
        case .text(let t):                           return "text-\(t.prefix(20))"
        }
    }
}
