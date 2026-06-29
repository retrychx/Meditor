import Foundation
import Observation

// MARK: - AgentRunner

/// Manages the multi-turn agent loop: AI decides → calls tools → gets results → continues.
/// Observable so views can bind to its state.
/// Backend is injected via factory closure — easy to mock in tests.
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

    private let maxSteps: Int
    /// Backend factory，默认从 AIConfig 创建；测试时可注入 mock
    private let backendFactory: @Sendable (AIConfig) -> any AgentBackend
    private var runTask: Task<Void, Never>? = nil

    /// 总执行超时（秒），0 = 不限。默认 5 分钟。
    var timeoutSeconds: TimeInterval = 300

    /// lastThinkingIndex 缓存，O(1) 更新/删除 thinking step
    private var lastThinkingIndex: Int? = nil

    init(
        maxSteps: Int = 30,
        backendFactory: @escaping @Sendable (AIConfig) -> any AgentBackend = AgentBackendFactory.make
    ) {
        self.maxSteps = maxSteps
        self.backendFactory = backendFactory
    }

    // MARK: - Run

    func run(
        systemPrompt: String,
        userMessage: String,
        tools: [any AgentTool],
        config: AIConfig,
        context: any AgentContextProtocol
    ) {
        let messages: [AgentMessage] = [
            AgentMessage(role: .system, content: systemPrompt),
            AgentMessage(role: .user,   content: userMessage)
        ]
        runMessages(messages, tools: tools, config: config, context: context)
    }

    /// 带已有历史消息继续运行（多轮对话）
    func run(
        messages: [AgentMessage],
        tools: [any AgentTool],
        config: AIConfig,
        context: any AgentContextProtocol
    ) {
        runMessages(messages, tools: tools, config: config, context: context)
    }

    private func runMessages(
        _ messages: [AgentMessage],
        tools: [any AgentTool],
        config: AIConfig,
        context: any AgentContextProtocol
    ) {
        guard !isRunning else { return }

        steps              = []
        finalText          = ""
        error              = nil
        lastThinkingIndex  = nil
        isRunning          = true

        runTask = Task { [weak self] in
            guard let self else { return }
            guard self.timeoutSeconds > 0 else {
                await self._run(messages: messages, tools: tools, config: config, context: context)
                return
            }
            // 两个 Task 赛跑：_run 和超时计时器，任一完成则 cancel 另一个
            await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    await self._run(messages: messages, tools: tools, config: config, context: context)
                    return false   // 正常完成
                }
                group.addTask {
                    do {
                        try await Task.sleep(for: .seconds(self.timeoutSeconds))
                    } catch {
                        return false   // 被 cancel：主任务已完成，不触发超时
                    }
                    return true   // 超时
                }
                if let timedOut = await group.next(), timedOut, self.isRunning {
                    self.error     = "操作超时（\(Int(self.timeoutSeconds))s），请重试或简化任务"
                    self.isRunning = false
                    self.runTask   = nil
                    // onComplete 不在此处调用 —— _run 的 cleanup 必然执行并统一触发
                    // (group.cancelAll 后 withTaskGroup 会等待 _run 响应取消并结束)
                }
                group.cancelAll()
            }
        }
    }

    func cancel() {
        runTask?.cancel()
        runTask = nil
        if finalText.isEmpty && error == nil {
            error = "已取消"
        }
    }

    // MARK: - Core loop

    private func _run(
        messages initialMessages: [AgentMessage],
        tools: [any AgentTool],
        config: AIConfig,
        context: any AgentContextProtocol
    ) async {
        let backend = backendFactory(config)  // nonisolated factory, safe to call from task
        var messages = initialMessages

        addThinking(label: "AI 思考中…")

        var stepCount = 0

        while stepCount < maxSteps {
            stepCount += 1
            guard !Task.isCancelled else { break }

            do {
                let response = try await backend.complete(messages: messages, tools: tools)

                if !response.toolCalls.isEmpty {
                    removeLastThinking()

                    messages.append(AgentMessage(
                        role: .assistant,
                        content: response.text,
                        toolCalls: response.toolCalls
                    ))

                    var cancelled = false
                    for call in response.toolCalls {
                        guard !Task.isCancelled else { cancelled = true; break }
                        addToolCall(id: call.id, name: call.name, args: prettyArgs(call.arguments))

                        var result: AgentToolResult
                        if call.name == "_parse_error" {
                            // ClaudeCLIBackend 注入的占位工具：JSON 解析失败，让 AI 看到错误后重试
                            let args     = call.arguments
                            let original = args["original_tool"]?.stringValue ?? "unknown"
                            let rawArgs  = args["raw_arguments"]?.stringValue ?? ""
                            result = AgentToolResult(
                                toolCallID: call.id,
                                toolName:   original,
                                content: "❌ Tool call '\(original)' failed: arguments JSON could not be parsed.\nRaw: \(rawArgs.prefix(200))\nPlease retry with properly formatted JSON arguments.",
                                isError: true
                            )
                        } else if let tool = tools.first(where: { $0.spec.name == call.name }) {
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

                        markToolCallDone(id: call.id, result: result)

                        messages.append(AgentMessage(
                            role: .tool,
                            content: result.content,
                            toolCallID: result.toolCallID,
                            toolName: result.toolName
                        ))
                    }

                    if cancelled { break }

                    addThinking(label: "AI 处理结果…")
                    continue

                } else {
                    removeLastThinking()
                    finalText = response.text
                    onChunk?(response.text)
                    messages.append(AgentMessage(role: .assistant, content: response.text))
                    break
                }
            } catch is CancellationError {
                break
            } catch {
                removeLastThinking()
                self.error = error.localizedDescription
                break
            }
        }

        if stepCount >= maxSteps {
            self.error = "Agent 执行超过最大步数（\(maxSteps)）"
        }

        isRunning         = false
        lastThinkingIndex = nil
        runTask           = nil
        onComplete?()
    }

    // MARK: - Step management（O(1) thinking 操作）

    private func addThinking(label: String) {
        let step = AgentRunnerStep.thinking(label: label)
        lastThinkingIndex = steps.count
        steps.append(step)
    }

    private func removeLastThinking() {
        guard let idx = lastThinkingIndex, idx < steps.count else { return }
        if case .thinking = steps[idx] {
            steps.remove(at: idx)
            // 移除后，后续 toolCall 的 index 不变（thinking 总在末尾追加）
        }
        lastThinkingIndex = nil
    }

    private func addToolCall(id: String, name: String, args: String) {
        steps.append(.toolCall(id: id, name: name, args: args))
    }

    private func markToolCallDone(id: String, result: AgentToolResult) {
        // toolCall 在 steps 末尾，从末尾往前找，通常 O(1)
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

    private func prettyArgs(_ args: [String: AnySendableValue]) -> String {
        guard !args.isEmpty else { return "{}" }
        // 将 AnySendableValue 还原为 Any 用于 JSON 序列化
        let raw = args.reduce(into: [String: Any]()) { dict, pair in
            dict[pair.key] = unwrapValue(pair.value)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: raw, options: .prettyPrinted),
              let str = String(data: data, encoding: .utf8)
        else { return "{}" }
        return str.count > 200 ? String(str.prefix(200)) + "…" : str
    }

    private func unwrapValue(_ v: AnySendableValue) -> Any {
        switch v {
        case .string(let s):  return s
        case .bool(let b):    return b
        case .int(let i):     return i
        case .double(let d):  return d
        case .null:           return NSNull()
        case .array(let arr): return arr.map { unwrapValue($0) }
        case .dict(let d):    return d.reduce(into: [String: Any]()) { $0[$1.key] = unwrapValue($1.value) }
        }
    }
}
