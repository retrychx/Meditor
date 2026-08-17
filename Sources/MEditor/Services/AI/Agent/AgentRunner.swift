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
    /// 上次 onChunk 推送时间：delta 每次都累积，但 UI 回调按 ≥50ms 合批
    /// （同 AIClient.streamTask 思路），避免高速流式时主队列洪峰。
    private var lastStreamFlush: Date = .distantPast

    /// 流式 chunk 回调（主线程，可选）
    var onChunk: (@MainActor (String) -> Void)? = nil
    /// 完成回调（主线程，isRunning 已设为 false）
    var onComplete: (@MainActor () -> Void)? = nil

    // MARK: - Config

    private let maxSteps: Int
    /// Backend factory，默认从 AIConfig 创建；测试时可注入 mock
    private let backendFactory: @Sendable (AIConfig) -> any AgentBackend
    private var runTask: Task<Void, Never>? = nil

    /// 停滞检测阈值：相同 (工具名, 参数) 的调用连续失败达到该次数即中断 run。
    /// 3 = 给模型两次换参数/换思路的机会，第三次原样失败基本可判定卡住。
    private static let stallThreshold = 3

    /// 运行代际计数：cancel() 会同步放行 isRunning，但旧 _run 可能仍卡在不可取消点
    /// （如工具确认 continuation），此时新 run() 能通过 guard 启动，两个 _run 共享
    /// state/回调。每次 runMessages 递增 generation，旧 _run 发现代际不匹配时静默
    /// 放弃收尾，避免覆盖新 run 的 finalMessages/isRunning 或触发旧 onComplete。
    private var runGeneration = 0

    /// 总执行超时（秒），0 = 不限。默认 5 分钟。
    var timeoutSeconds: TimeInterval = 300

    /// 发给后端的上下文预算（token 估算值）：超出时对线上副本做预算裁剪，
    /// 本地 messages（最终写入持久化历史）保持完整。测试可调小以覆盖裁剪路径。
    var contextBudgetTokens = AgentHistoryBudget.defaultBudgetTokens

    /// 上下文预算淘汰回调（每次 run 首次发生淘汰时触发一次）：UI 据此在 transcript
    /// 给出 subtle 提示，不让淘汰静默发生。
    var onContextEviction: (@MainActor (AgentHistoryBudget.TrimResult) -> Void)? = nil

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

        runGeneration += 1
        let generation = runGeneration

        steps              = []
        finalText          = ""
        error              = nil
        wasTruncated       = false
        state.stall        = nil
        lastThinkingIndex  = nil
        isRunning          = true

        runTask = Task { [weak self] in
            guard let self else { return }
            guard self.timeoutSeconds > 0 else {
                await self._run(messages: messages, tools: tools, config: config, context: context, generation: generation)
                return
            }
            // 两个 Task 赛跑：_run 和超时计时器，任一完成则 cancel 另一个
            await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    await self._run(messages: messages, tools: tools, config: config, context: context, generation: generation)
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
                // 代际校验：旧 run 的超时计时器晚到时，state 可能已被新 run 接管，
                // 不得把新 run 误判为超时
                if let timedOut = await group.next(), timedOut, self.isRunning,
                   self.runGeneration == generation {
                    self.error     = "操作超时（\(Int(self.timeoutSeconds))s），请重试或简化任务"
                    self.isRunning = false
                    self.runTask   = nil
                    // 拒绝挂起的命令确认：恢复工具内 withCheckedContinuation，否则确认框
                    // 弹出期间超时会让 _run 永不结束（reject 幂等，与 cancelStreaming 不冲突）
                    context.cancelPendingCommandConfirmation()
                    context.cancelPendingWriteConfirmation()
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
        context: any AgentContextProtocol,
        generation: Int
    ) async {
        let backend = backendFactory(config)  // nonisolated factory, safe to call from task
        var messages = initialMessages

        addThinking(label: "AI 思考中…")

        var stepCount = 0

        // 停滞检测状态：跟踪最近一次失败的 (工具名, 参数) 指纹及连续失败次数。
        // 模型反复用相同参数调同一个失败工具时会烧满 maxSteps 才报"超过最大步数"，
        // 这里在「相同调用连续失败达阈值」时提前中断，错误文案指出具体工具。
        // 只读工具同样适用（如反复 read 不存在的文件）。
        var lastFailureFingerprint: String? = nil
        var consecutiveFailures = 0
        var stalled = false
        /// 每次 run 只向 UI 报告一次预算淘汰（后续 step 再淘汰不再重复提示）
        var evictionNotified = false

        while stepCount < maxSteps {
            stepCount += 1
            guard !Task.isCancelled else { break }
            // 代际已易主（cancel 后新 run 启动）：直接走向收尾，收尾会静默放弃，
            // 避免旧 run 继续往共享 state 追加 step 或再发后端请求
            guard generation == runGeneration else { break }

            do {
                streamAccumulated = ""   // 每个 step 重置，reply 只显示当前轮累积文本
                lastStreamFlush = .distantPast   // 每个 step 的首个 delta 立即显示

                // 上下文预算裁剪：只作用于发给后端的线上副本，本地 messages
                //（最终写入持久化历史）保持完整。早期长 tool 结果先替换为占位符，
                // 仍超预算才整轮裁最老历史（tool_call/tool_result 配对保持，见 AgentHistoryBudget）。
                let outgoing = AgentHistoryBudget.trim(messages, budgetTokens: contextBudgetTokens)
                if outgoing.didTrim, !evictionNotified {
                    evictionNotified = true
                    onContextEviction?(outgoing)
                }

                let response = try await backend.completeStreaming(
                    messages: outgoing.messages,
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
                                // onChunk 按 ≥50ms 合批：不每个 delta 都触发一次 UI 更新
                                let now = Date()
                                if now.timeIntervalSince(self.lastStreamFlush) > 0.05 {
                                    self.lastStreamFlush = now
                                    self.onChunk?(self.streamAccumulated)     // 回调累积全文
                                }
                            }
                        }
                    }
                )

                // 冲刷节流残余：把累积全文最后推一次。与 chunk 同走 main queue（FIFO），
                // 保证在最后一批 delta 之后执行；最终回复随后还会由 onChunk?(response.text) 覆盖。
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    MainActor.assumeIsolated {
                        guard !self.streamAccumulated.isEmpty else { return }
                        self.lastStreamFlush = Date()
                        self.onChunk?(self.streamAccumulated)
                    }
                }

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
                        /// 工具实际执行耗时（仅真实执行分支有值，存入 step 供 UI/排查用）
                        var duration: TimeInterval? = nil
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
                            let startedAt = Date()
                            do {
                                let output = try await tool.execute(arguments: call.arguments, context: context)
                                result = AgentToolResult(toolCallID: call.id, toolName: call.name, content: output)
                            } catch {
                                result = AgentToolResult(
                                    toolCallID: call.id, toolName: call.name,
                                    content: "错误：\(error.localizedDescription)", isError: true
                                )
                            }
                            duration = Date().timeIntervalSince(startedAt)
                        } else {
                            result = AgentToolResult(
                                toolCallID: call.id, toolName: call.name,
                                content: "未找到工具：\(call.name)", isError: true
                            )
                        }

                        markToolCallDone(id: call.id, result: result, durationSeconds: duration)

                        messages.append(AgentMessage(
                            role: .tool,
                            content: result.content,
                            toolCallID: result.toolCallID,
                            toolName: result.toolName
                        ))

                        // 停滞检测：相同 (工具名, 参数) 指纹的失败连续出现达阈值即中断 run，
                        // 避免烧满 maxSteps 才失败。指纹用排序键的 JSON，保证参数顺序无关。
                        if result.isError {
                            let fingerprint = stallFingerprint(call)
                            if fingerprint == lastFailureFingerprint {
                                consecutiveFailures += 1
                            } else {
                                lastFailureFingerprint = fingerprint
                                consecutiveFailures = 1
                            }
                            if consecutiveFailures >= Self.stallThreshold {
                                let summary = Self.firstLine(result.content, maxLength: 120)
                                state.stall = AgentStallDiagnostic(
                                    toolName: call.name,
                                    repeatCount: consecutiveFailures,
                                    lastErrorSummary: summary
                                )
                                error = "Agent 在工具 '\(call.name)' 上停滞：相同调用已连续失败 \(consecutiveFailures) 次（最后错误：\(summary)）。已中断运行，请检查该工具的输入或换个说法重试。"
                                stalled = true
                                break
                            }
                        } else {
                            // 成功即重置：只有「连续」的相同失败才算停滞
                            lastFailureFingerprint = nil
                            consecutiveFailures = 0
                        }
                    }

                    if cancelled || stalled { break }

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

        // 代际校验（cancel/新 run 竞态修复）：本 _run 若曾在 cancel 后卡在不可取消点
        //（如工具确认 continuation），期间新 run 已启动并接管 state。旧 run 的收尾
        // 必须静默放弃——不写 finalMessages、不重置 isRunning/runTask、不触发旧
        // onComplete，否则会覆盖新 run 的运行状态。
        guard generation == runGeneration else { return }

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
        // 正常结束也拒绝挂起的命令确认（幂等），兜底防 continuation 泄漏
        context.cancelPendingCommandConfirmation()
        context.cancelPendingWriteConfirmation()
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

    private func markToolCallDone(id: String, result: AgentToolResult, durationSeconds: TimeInterval? = nil) {
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
            isError: result.isError,
            durationSeconds: durationSeconds
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

    /// 停滞检测用的调用指纹：工具名 + 排序键参数 JSON。
    /// AnySendableValue.anyValue 产出的都是 JSON 安全类型（含 NSNull），序列化不会失败；
    /// 失败时退化为「工具名|?」，仍能保证相同工具重复失败可被检测到。
    private func stallFingerprint(_ call: AgentToolCall) -> String {
        let raw = call.arguments.reduce(into: [String: Any]()) { $0[$1.key] = $1.value.anyValue }
        guard let data = try? JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else { return "\(call.name)|?" }
        return "\(call.name)|\(json)"
    }

    /// 取首行并按长度截断，供错误摘要使用（停滞诊断 / 文案）。
    private static func firstLine(_ s: String, maxLength: Int) -> String {
        let line = s.components(separatedBy: "\n").first ?? s
        return line.count > maxLength ? String(line.prefix(maxLength)) + "…" : line
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
            dict[pair.key] = pair.value.anyValue
        }
        guard let data = try? JSONSerialization.data(withJSONObject: raw, options: .prettyPrinted),
              let str = String(data: data, encoding: .utf8)
        else { return "{}" }
        return str.count > 200 ? String(str.prefix(200)) + "…" : str
    }
}
