import Foundation
import Observation

// MARK: - AgentRunner

/// Manages the multi-turn agent loop: AI decides → calls tools → gets results → continues.
/// Observable so views can bind to its state.
/// Backend is injected via factory closure — easy to mock in tests.
@MainActor
@Observable
final class AgentRunner {

    // MARK: - Owned run state

    /// 该次运行的可观测状态。生命周期独立于 Runner：Runner 完成后外层可保留它展示历史步骤。
    let state: AgentRunState

    // MARK: - State (forwarded to state)

    var steps: [AgentRunnerStep] {
        get { state.steps }
        set { state.steps = newValue }
    }
    var isRunning: Bool {
        get { state.isRunning }
        set { state.isRunning = newValue }
    }
    var finalText: String {
        get { state.finalText }
        set { state.finalText = newValue }
    }
    var error: String? {
        get { state.error }
        set { state.error = newValue }
    }
    var wasTruncated: Bool {
        get { state.wasTruncated }
        set { state.wasTruncated = newValue }
    }
    /// 运行完成后暴露的完整 AgentMessage 列表（含工具调用上下文）
    private(set) var finalMessages: [AgentMessage] = []

    /// 当前 step 的流式累积文本；onChunk 始终回调「累积全文」而非增量 delta，
    /// 让 UI 侧可直接赋值显示（无需自行拼接）。
    private var streamAccumulated = ""

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
        self.state = AgentRunState()
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
        wasTruncated       = false
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
        // 立即置为未运行：工具可能卡在用户确认对话框（continuation 不响应 Task 取消），
        // 不把状态复位会导致 UI 一直停在"运行中"。确认由调用方（AIConversation）负责 dismiss，
        // 之后 _run 的 cleanup 会再次幂等地走一遍收尾流程。
        isRunning = false
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
                streamAccumulated = ""   // 每个 step 重置，reply 只显示当前轮累积文本
                let response = try await backend.completeStreaming(
                    messages: messages,
                    tools: tools,
                    onTextChunk: { [weak self] chunk in
                        // 用 DispatchQueue.main.async 而非 Task { @MainActor }：
                        // main queue 严格 FIFO，chunk 按到达顺序应用；
                        // Task 调度顺序不保证，高速流式下累积文本可能乱序。
                        DispatchQueue.main.async { [weak self] in
                            // guard 必须与本闭包的 [weak self] 同层：
                            // 在嵌套 @Sendable 闭包里解包外层 weak 捕获，
                            // 新版编译器会报 captured var 硬错误。
                            guard let self else { return }
                            MainActor.assumeIsolated {
                                self.streamAccumulated += chunk          // 累积 delta
                                self.onChunk?(self.streamAccumulated)     // 回调累积全文
                            }
                        }
                    }
                )

                // 输出被 max_tokens 截断：置位标记由 UI 提示，不自动续跑（避免死循环）
                if response.finishReason == "length" || response.finishReason == "max_tokens" {
                    wasTruncated = true
                }

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
                        if let parseError = call.argumentsParseError {
                            // 参数 JSON 非法（对所有后端生效，同 ClaudeCLIBackend 的 _parse_error）：
                            // 跳过执行，直接回灌错误，让模型重新生成合法 JSON
                            let raw = call.rawArgumentsJSON ?? ""
                            result = AgentToolResult(
                                toolCallID: call.id,
                                toolName:   call.name,
                                content: "工具 '\(call.name)' 的参数 JSON 解析失败（\(parseError)），未执行。\n原始参数：\(raw.prefix(200))\n请重新生成合法的 JSON 参数后再调用该工具。",
                                isError: true
                            )
                        } else if call.name == "_parse_error" {
                            // ClaudeCLIBackend 注入的占位工具：JSON 解析失败，让 AI 看到错误后重试
                            let args     = call.arguments
                            let original = args["original_tool"]?.stringValue ?? "unknown"
                            let rawArgs  = args["raw_arguments"]?.stringValue ?? ""
                            result = AgentToolResult(
                                toolCallID: call.id,
                                toolName:   original,
                                content: "[X] Tool call '\(original)' failed: arguments JSON could not be parsed.\nRaw: \(rawArgs.prefix(200))\nPlease retry with properly formatted JSON arguments.",
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
                self.error = classifyError(error)
                break
            }
        }

        // 仅当循环耗尽且既无最终答案也无更具体错误时才报步数超限：
        // 最终答案恰好在第 maxSteps 轮拿到时不应误报错误
        if stepCount >= maxSteps && finalText.isEmpty && error == nil {
            self.error = "Agent 执行超过最大步数（\(maxSteps)）"
        }

        // 异常结束（cancel/timeout/error）时，为未应答的 tool call 补合成 error tool result，
        // 保证 tool_calls 与 tool result 严格配对，避免坏历史下一轮被 API 400 拒绝
        messages = reconcileToolResults(messages)

        finalMessages     = messages
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

    /// 将后端错误分类为统一的中文可操作文案；未识别的错误保留原始信息
    private func classifyError(_ error: Error) -> String {
        if let aiError = error as? AIError, case .server(let code, _) = aiError {
            switch code {
            case 401, 403: return "鉴权失败（HTTP \(code)），请检查 API Key 是否正确"
            case 429:      return "请求过于频繁或额度不足（HTTP 429），请稍后重试"
            default:       break
            }
        }
        if let urlError = error as? URLError {
            if urlError.code == .timedOut {
                return "请求超时，请检查网络连接后重试"
            }
            return "网络连接失败：\(urlError.localizedDescription)"
        }
        return error.localizedDescription
    }

    /// 为没有对应 tool result 的 tool call 追加合成的中断结果（紧跟其 assistant 消息之后），
    /// 保证持久化历史中 tool_calls 与 tool result 严格配对
    private func reconcileToolResults(_ messages: [AgentMessage]) -> [AgentMessage] {
        let answered = Set(messages.compactMap { $0.role == .tool ? $0.toolCallID : nil })
        var result: [AgentMessage] = []
        for message in messages {
            result.append(message)
            guard message.role == .assistant, let calls = message.toolCalls else { continue }
            for call in calls where !answered.contains(call.id) {
                result.append(AgentMessage(
                    role: .tool,
                    content: "错误：运行被中断，该工具调用未执行。",
                    toolCallID: call.id,
                    toolName: call.name
                ))
            }
        }
        return result
    }

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
