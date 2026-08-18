import XCTest
@testable import MEditor

// MARK: - AgentHistoryBudgetTests
//
// 上下文预算裁剪（AgentHistoryBudget.trim）回归测试：
//   - 预算内不裁剪（输入原样返回）；
//   - 超预算时更早历史里的长 tool 结果被占位符替换，最近 N 条完整保留；
//   - tool_call / tool_result 配对始终合法（每个 assistant toolCall 都有对应 tool result）；
//   - 占位后估算低于预算；仍超预算时整轮裁最老历史且边界不落在 tool 消息上。
// 另含一个 AgentRunner 集成测试：发给 backend 的是裁剪副本，finalMessages（持久化历史）保持完整。

final class AgentHistoryBudgetTests: XCTestCase {

    /// 一轮完整工具对话：user → assistant(toolCalls) → tool result。
    private func makeToolRound(_ i: Int, userContent: String = "question", assistantContent: String = "",
                               toolContent: String) -> [AgentMessage] {
        [
            AgentMessage(role: .user, content: "\(userContent) \(i)"),
            AgentMessage(
                role: .assistant,
                content: assistantContent,
                toolCalls: [AgentToolCall(id: "tc\(i)", name: "read_document", argumentsJSON: "{}")]
            ),
            AgentMessage(role: .tool, content: toolContent, toolCallID: "tc\(i)", toolName: "read_document"),
        ]
    }

    private func estimate(_ messages: [AgentMessage]) -> Int {
        messages.reduce(0) { $0 + AIConversation.estimateTokens($1.content) }
    }

    /// 配对合法性：每个 assistant toolCall 都有紧随其后的同 id tool result，且无孤儿 result。
    private func assertToolPairing(_ messages: [AgentMessage], file: StaticString = #filePath, line: UInt = #line) {
        let callIDs = messages.flatMap { $0.toolCalls ?? [] }.map(\.id)
        let resultIDs = messages.compactMap { $0.role == .tool ? $0.toolCallID : nil }
        XCTAssertEqual(Set(callIDs), Set(resultIDs), "tool_call 与 tool result 必须一一配对", file: file, line: line)
        for (idx, m) in messages.enumerated() where m.role == .assistant && !(m.toolCalls ?? []).isEmpty {
            guard idx + 1 < messages.count else {
                XCTFail("assistant(toolCalls) 后缺少 tool result", file: file, line: line)
                return
            }
            XCTAssertEqual(messages[idx + 1].role, .tool, "tool result 必须紧跟 assistant(toolCalls)", file: file, line: line)
            XCTAssertEqual(messages[idx + 1].toolCallID, m.toolCalls?.first?.id, file: file, line: line)
        }
    }

    // MARK: 预算内不裁剪

    func test_trim_underBudget_returnsUnchanged() {
        var history: [AgentMessage] = [AgentMessage(role: .system, content: "sys")]
        history.append(contentsOf: makeToolRound(0, toolContent: "small result"))

        let result = AgentHistoryBudget.trim(history, budgetTokens: 10_000, keepRecentMessages: 8)

        XCTAssertFalse(result.didTrim, "预算内不应裁剪")
        XCTAssertEqual(result.evictedToolResults, 0)
        XCTAssertEqual(result.droppedMessages, 0)
        XCTAssertEqual(result.messages.map(\.role), history.map(\.role))
        XCTAssertEqual(result.messages.map(\.content), history.map(\.content))
    }

    // MARK: 超预算：旧 tool 结果被占位、配对仍合法、最近 N 条不受影响

    /// 固定样本：system + 6 轮，每轮 tool result 为 3_000 个 CJK 字符（≈2_000 token）。
    private func makeSixRoundHistory() -> [AgentMessage] {
        let bigTool = String(repeating: "测", count: 3_000)
        var history: [AgentMessage] = [AgentMessage(role: .system, content: "system prompt")]
        for i in 0..<6 { history.append(contentsOf: makeToolRound(i, toolContent: bigTool)) }
        return history
    }

    func test_trim_overBudget_evictsOldToolResultsWithPlaceholder() {
        let history = makeSixRoundHistory()
        // keepRecent=3 → 最近一轮（round5）完整保护，rounds 0..4 的 tool 结果可淘汰
        let result = AgentHistoryBudget.trim(history, budgetTokens: 3_000, keepRecentMessages: 3)

        XCTAssertTrue(result.didTrim)
        XCTAssertEqual(result.evictedToolResults, 5, "rounds 0..4 的 5 条长 tool 结果应被占位")
        XCTAssertEqual(result.droppedMessages, 0, "占位后已低于预算，不应再整轮裁剪")
        XCTAssertEqual(result.messages.count, history.count, "占位替换不改变消息条数")

        let tools = result.messages.filter { $0.role == .tool }
        for i in 0..<5 {
            XCTAssertEqual(tools[i].content, AgentHistoryBudget.toolResultPlaceholder,
                           "round\(i) 的旧 tool 结果应被占位符替换")
            XCTAssertEqual(tools[i].toolCallID, "tc\(i)", "占位只改 content，配对字段保持")
        }
        XCTAssertEqual(tools[5].content.count, 3_000, "最近一轮的 tool 结果应原样保留")
    }

    func test_trim_overBudget_keepsToolCallResultPairingIntact() {
        let result = AgentHistoryBudget.trim(makeSixRoundHistory(), budgetTokens: 3_000, keepRecentMessages: 3)
        assertToolPairing(result.messages)
        XCTAssertEqual(result.messages.first?.role, .system, "system 应固定在头部")
    }

    func test_trim_recentMessagesUntouched() {
        let history = makeSixRoundHistory()
        let result = AgentHistoryBudget.trim(history, budgetTokens: 3_000, keepRecentMessages: 3)
        let recentIn = history.suffix(3), recentOut = result.messages.suffix(3)
        XCTAssertEqual(recentOut.map(\.content), recentIn.map(\.content), "最近 N 条内容不应被修改")
    }

    func test_trim_afterEviction_estimateBelowBudget() {
        let result = AgentHistoryBudget.trim(makeSixRoundHistory(), budgetTokens: 3_000, keepRecentMessages: 3)
        XCTAssertLessThanOrEqual(estimate(result.messages), 3_000, "占位后估算应低于预算")
    }

    // MARK: 仍超预算：整轮裁最老历史，边界不落 tool 消息

    func test_trim_stillOverBudget_dropsOldestRoundsKeepingBoundary() {
        // user / assistant 也很大（各 ≈1_000 token），仅占位 tool 结果不足以降到预算内
        let bigUser = String(repeating: "问", count: 1_500)
        let bigAsst = String(repeating: "答", count: 1_500)
        let bigTool = String(repeating: "测", count: 3_000)
        var history: [AgentMessage] = [AgentMessage(role: .system, content: "system prompt")]
        for i in 0..<6 {
            history.append(contentsOf: makeToolRound(i, userContent: bigUser,
                                                     assistantContent: bigAsst, toolContent: bigTool))
        }

        let result = AgentHistoryBudget.trim(history, budgetTokens: 9_000, keepRecentMessages: 3)

        XCTAssertTrue(result.didTrim)
        XCTAssertGreaterThan(result.droppedMessages, 0, "占位仍超预算时应整轮裁最老历史")
        XCTAssertEqual(result.messages.first?.role, .system)
        XCTAssertNotEqual(result.messages.dropFirst().first?.role, .tool,
                          "裁剪边界不能落在 tool_calls/tool result 配对之间")
        assertToolPairing(result.messages)
        XCTAssertLessThanOrEqual(estimate(result.messages), 9_000, "整轮裁剪后估算应低于预算")
        // 确定性边界：每轮 ≈4_000 token，裁掉最老 3 轮后（rounds 3、4 已占位 + round5 完整）低于预算
        XCTAssertEqual(result.droppedMessages, 9)
        XCTAssertEqual(result.evictedToolResults, 2, "被淘汰又遭整轮裁掉的占位不计入提示数")
    }

    // MARK: 保护尾部不可牺牲

    func test_trim_protectedTailNeverDropped() {
        // 全部消息都在保护尾部内：即使超预算也不裁、不替换
        let history = makeSixRoundHistory()
        let result = AgentHistoryBudget.trim(history, budgetTokens: 100, keepRecentMessages: 100)

        XCTAssertFalse(result.didTrim)
        XCTAssertEqual(result.messages.map(\.content), history.map(\.content))
    }

    // MARK: 保护边界不劈开 tool 配对

    func test_trim_protectedBoundaryNeverSplitsToolPair() {
        // keepRecent=1 时朴素边界（count-1）正好落在 tool result 上：若第二级裁掉
        // 其 assistant(toolCalls) 会留下孤儿 result。边界应前移让整对进入保护尾部。
        let big = String(repeating: "测", count: 3_000)
        let history: [AgentMessage] = [
            AgentMessage(role: .user, content: big),
            AgentMessage(role: .assistant, content: "",
                         toolCalls: [AgentToolCall(id: "tc0", name: "read_document", argumentsJSON: "{}")]),
            AgentMessage(role: .tool, content: big, toolCallID: "tc0", toolName: "read_document"),
        ]

        let result = AgentHistoryBudget.trim(history, budgetTokens: 100, keepRecentMessages: 1)

        assertToolPairing(result.messages)
        XCTAssertEqual(result.messages.first?.role, .assistant,
                       "只能裁掉最老的 user，assistant/tool 配对必须整体保留")
        XCTAssertEqual(result.droppedMessages, 1)
    }

    // MARK: toolCalls 参数计入预算 + 对称占位淘汰

    /// assistant 的 toolCalls 参数（write_document 全量写入）必须计入 token 估算：
    /// 以下样本 content 总量远低于预算，仅靠参数体积触发裁剪。
    private func makeBigArgsHistory(rounds: Int = 6) -> [AgentMessage] {
        let bigArgs = #"{"name":"doc.md","content":""# + String(repeating: "文", count: 3_000) + #""}"#
        var history: [AgentMessage] = [AgentMessage(role: .system, content: "system prompt")]
        for i in 0..<rounds {
            history.append(AgentMessage(role: .user, content: "write \(i)"))
            history.append(AgentMessage(
                role: .assistant,
                content: "",
                toolCalls: [AgentToolCall(id: "tc\(i)", name: "write_document", argumentsJSON: bigArgs)]
            ))
            history.append(AgentMessage(role: .tool, content: "ok", toolCallID: "tc\(i)", toolName: "write_document"))
        }
        return history
    }

    func test_trim_toolCallArgsCountedAndEvicted() {
        let history = makeBigArgsHistory()
        // content 总量极小（≈几十 token），若不计参数（每轮 ≈2_000 token）永远不会超预算
        let result = AgentHistoryBudget.trim(history, budgetTokens: 3_000, keepRecentMessages: 3)

        XCTAssertTrue(result.didTrim, "参数体积应计入预算并触发裁剪")
        XCTAssertEqual(result.evictedToolCallArgs, 5, "rounds 0..4 的大参数应被占位")
        XCTAssertEqual(result.droppedMessages, 0, "参数占位后已低于预算，不应整轮裁剪")
        XCTAssertEqual(result.messages.count, history.count, "占位替换不改变消息条数")

        for i in 0..<5 {
            let call = result.messages.flatMap { $0.toolCalls ?? [] }.first { $0.id == "tc\(i)" }
            XCTAssertEqual(call?.rawArgumentsJSON, AgentHistoryBudget.toolCallArgsPlaceholder,
                           "round\(i) 的参数 JSON 应被占位")
            XCTAssertEqual(call?.name, "write_document", "占位不动 name/id 配对字段")
            XCTAssertEqual(call?.id, "tc\(i)")
        }
        // 保护尾部的最近一轮参数原样保留
        let lastCall = result.messages.flatMap { $0.toolCalls ?? [] }.first { $0.id == "tc5" }
        XCTAssertTrue(lastCall?.rawArgumentsJSON?.contains("文文文") == true,
                      "最近一轮的参数应原样保留")
        assertToolPairing(result.messages)
    }

    func test_trim_underBudgetWithoutArgs_butOverWithArgs() {
        // 对照：同样的消息若参数很短，content + 参数都在预算内 → 不裁剪
        let smallArgs = #"{"name":"a.md","content":"x"}"#
        var history: [AgentMessage] = [AgentMessage(role: .system, content: "sys")]
        history.append(AgentMessage(role: .user, content: "write"))
        history.append(AgentMessage(
            role: .assistant, content: "",
            toolCalls: [AgentToolCall(id: "tc0", name: "write_document", argumentsJSON: smallArgs)]
        ))
        history.append(AgentMessage(role: .tool, content: "ok", toolCallID: "tc0", toolName: "write_document"))

        let result = AgentHistoryBudget.trim(history, budgetTokens: 3_000, keepRecentMessages: 8)
        XCTAssertFalse(result.didTrim)
        XCTAssertEqual(result.messages.flatMap { $0.toolCalls ?? [] }.first?.rawArgumentsJSON, smallArgs)
    }

    // MARK: 首条对齐：裁剪后首条（非 system）必须是 user

    func test_trim_firstMessageAfterTrim_isUser() {
        // 每条 ≈1_000 token；budget 5_500 时第二级裁掉 u1 后即达标，
        // 起点落在 assistant 上——首条对齐应继续丢到 u2。
        let big = String(repeating: "字", count: 1_500)
        let history: [AgentMessage] = [
            AgentMessage(role: .user, content: big),
            AgentMessage(role: .assistant, content: big),
            AgentMessage(role: .user, content: big),
            AgentMessage(role: .assistant, content: big),
            AgentMessage(role: .user, content: big),
            AgentMessage(role: .assistant, content: big),
        ]

        let result = AgentHistoryBudget.trim(history, budgetTokens: 5_500, keepRecentMessages: 3)

        XCTAssertEqual(result.messages.first?.role, .user,
                       "裁剪后首条（非 system）必须是 user（Anthropic 对 assistant 开头直接 400）")
        XCTAssertEqual(result.droppedMessages, 2, "u1 与落在起点的 assistant 应一起被丢弃")
        XCTAssertEqual(result.messages.count, 4)
    }

    func test_trim_firstMessageAlignment_dropsToolResultsWithTheirAssistant() {
        // 起点落在 assistant(toolCalls) 上时，其后连续的 tool 结果必须整组丢弃，
        // 不能留下孤儿 result。
        let big = String(repeating: "字", count: 1_500)
        let history: [AgentMessage] = [
            AgentMessage(role: .user, content: big),
            AgentMessage(role: .assistant, content: big,
                         toolCalls: [AgentToolCall(id: "tc0", name: "read_document", argumentsJSON: "{}")]),
            AgentMessage(role: .tool, content: big, toolCallID: "tc0", toolName: "read_document"),
            AgentMessage(role: .user, content: big),
            AgentMessage(role: .assistant, content: big),
        ]

        // 总 ≈5_000（tool 结果先被占位 ≈-1_000），budget 3_500：裁掉 u1 后 ≈3_000 达标，
        // 起点落在 assistant(toolCalls) 上 → 对齐把 assistant+tool 整组丢弃
        let result = AgentHistoryBudget.trim(history, budgetTokens: 3_500, keepRecentMessages: 2)

        XCTAssertEqual(result.messages.first?.role, .user)
        XCTAssertEqual(result.droppedMessages, 3, "assistant(toolCalls) 与其 tool 结果应整组丢弃")
        assertToolPairing(result.messages)
    }

    func test_trim_underBudget_historyStartingWithAssistant_alignedToUser() {
        // 旧版本裁剪可能留下 assistant 开头的持久化历史：即使预算内也应先对齐再发出
        var history: [AgentMessage] = [AgentMessage(role: .assistant, content: "stale answer")]
        for i in 0..<9 { history.append(AgentMessage(role: .user, content: "question \(i)")) }

        // keepRecent=8 → 保护区从 index 2 开始，stale assistant 落在可裁范围
        let result = AgentHistoryBudget.trim(history, budgetTokens: 10_000, keepRecentMessages: 8)

        XCTAssertEqual(result.messages.first?.role, .user, "assistant 开头的历史应被对齐到 user")
        // 对齐是对旧数据的静默修正，不算预算裁剪——不触发「上下文超出预算」提示
        XCTAssertFalse(result.didTrim)
        XCTAssertEqual(result.droppedMessages, 0)
    }
}

// MARK: - AgentRunner 预算裁剪集成测试

@MainActor
final class AgentRunnerContextBudgetTests: XCTestCase {

    private var ctx: MockAgentContext!
    private var cfg: AIConfig!

    override func setUp() {
        super.setUp()
        ctx = MockAgentContext()
        cfg = AIConfig(
            kind: .disabled, baseURL: "", model: "", cliPath: "", cliModel: "", apiKey: "",
            requestTimeoutSeconds: 60
        )
    }

    /// 记录每次 complete 收到的消息列表的 backend（首轮即返回最终文本，不进工具循环）。
    private final class RecordingBackend: AgentBackend, @unchecked Sendable {
        private(set) var capturedMessages: [[AgentMessage]] = []
        private let lock = NSLock()

        func complete(messages: [AgentMessage], tools: [any AgentTool]) async throws -> AgentCompletionResponse {
            lock.lock(); capturedMessages.append(messages); lock.unlock()
            return AgentCompletionResponse(text: "done", toolCalls: [], finishReason: "stop")
        }
    }

    func test_runner_sendsTrimmedCopy_keepsFullHistoryLocally() async {
        let bigTool = String(repeating: "测", count: 3_000)
        var history: [AgentMessage] = [AgentMessage(role: .system, content: "system prompt")]
        for i in 0..<6 {
            history.append(contentsOf: [
                AgentMessage(role: .user, content: "question \(i)"),
                AgentMessage(role: .assistant, content: "",
                             toolCalls: [AgentToolCall(id: "tc\(i)", name: "read_document", argumentsJSON: "{}")]),
                AgentMessage(role: .tool, content: bigTool, toolCallID: "tc\(i)", toolName: "read_document"),
            ])
        }

        let backend = RecordingBackend()
        let runner = AgentRunner(maxSteps: 5, backendFactory: { _ in backend })
        // 调小预算覆盖裁剪路径（默认 keepRecent=8：rounds 0..2 的 tool 结果可淘汰，
        // 7_000 使得占位后即低于预算、不触发第二级整轮裁剪）
        runner.contextBudgetTokens = 7_000

        var evictions: [AgentHistoryBudget.TrimResult] = []
        runner.onContextEviction = { evictions.append($0) }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            runner.onComplete = { cont.resume() }
            runner.run(messages: history, tools: [], config: cfg, context: ctx)
        }

        // 发给 backend 的是裁剪副本：含占位符、配对完整、估算低于预算
        XCTAssertEqual(backend.capturedMessages.count, 1)
        let sent = backend.capturedMessages[0]
        XCTAssertTrue(sent.contains { $0.role == .tool && $0.content == AgentHistoryBudget.toolResultPlaceholder },
                      "发给后端的副本中早期长 tool 结果应被占位")
        let sentCallIDs = sent.flatMap { $0.toolCalls ?? [] }.map(\.id)
        let sentResultIDs = sent.compactMap { $0.role == .tool ? $0.toolCallID : nil }
        XCTAssertEqual(Set(sentCallIDs), Set(sentResultIDs), "发给后端的副本配对必须完整")
        XCTAssertLessThanOrEqual(
            sent.reduce(0) { $0 + AIConversation.estimateTokens($1.content) }, 7_000,
            "发给后端的副本估算应低于预算（占位后即达标，未触发整轮裁剪）")

        // 淘汰对用户可见：回调每次 run 恰好触发一次
        XCTAssertEqual(evictions.count, 1)
        XCTAssertTrue(evictions[0].didTrim)

        // finalMessages（写入持久化历史）保持完整：大 tool 结果原样保留，无占位符
        let final = runner.finalMessages
        XCTAssertFalse(final.contains { $0.content == AgentHistoryBudget.toolResultPlaceholder },
                       "持久化历史不应被裁剪")
        XCTAssertTrue(final.contains { $0.role == .tool && $0.content.count == 3_000 },
                      "持久化历史中的大 tool 结果应原样保留")
    }
}
