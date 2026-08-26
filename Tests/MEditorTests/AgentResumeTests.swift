import XCTest
@testable import MEditor

// MARK: - AgentResumeTests
//
// 覆盖断点续传：
// - AgentResumeContext 续跑上下文构造（原始指令 + 已完成工具调用结果 + 续跑指令）；
// - AgentRunner 结束方式分类（completed / failed / cancelled）——用户取消不提供续跑；
// - 续跑集成：失败 run 的 finalMessages 带进新 run，已完成的工具调用不重复执行。

@MainActor
final class AgentResumeTests: XCTestCase {

    private var ctx: MockAgentContext!
    private var cfg: AIConfig!

    override func setUp() {
        super.setUp()
        ctx = MockAgentContext()
        ctx.currentDocument     = "Initial document content"
        ctx.currentDocumentName = "test.md"
        cfg = AIConfig(
            kind: .disabled, baseURL: "", model: "", cliPath: "", cliModel: "", apiKey: "",
            requestTimeoutSeconds: 60
        )
    }

    // MARK: - AgentResumeContext.makeMessages

    func test_makeMessages_appendsResumeInstruction_preservesToolHistory() {
        let toolCall = AgentToolCall(id: "tc1", name: "read_document", argumentsJSON: "{}")
        let history: [AgentMessage] = [
            AgentMessage(role: .system,    content: "old system"),
            AgentMessage(role: .user,      content: "original instruction"),
            AgentMessage(role: .assistant, content: "", toolCalls: [toolCall]),
            AgentMessage(role: .tool,      content: "tool result body",
                         toolCallID: "tc1", toolName: "read_document"),
        ]

        let messages = AgentResumeContext.makeMessages(history: history, freshSystemPrompt: "fresh system")

        XCTAssertEqual(messages?.count, 5)
        // system 被刷新而非保留旧值
        XCTAssertEqual(messages?.first?.role, .system)
        XCTAssertEqual(messages?.first?.content, "fresh system")
        // 原始指令与已完成工具调用结果原样保留（续跑的上下文基础）
        XCTAssertEqual(messages?[1].content, "original instruction")
        XCTAssertEqual(messages?[3].role, .tool)
        XCTAssertEqual(messages?[3].content, "tool result body")
        // 末尾追加 user 续跑指令
        XCTAssertEqual(messages?.last?.role, .user)
        XCTAssertEqual(messages?.last?.content, AgentResumeContext.resumeInstruction)
        // 不改动调用方持有的历史
        XCTAssertEqual(history.count, 4)
        XCTAssertEqual(history.first?.content, "old system")
    }

    func test_makeMessages_emptyHistory_returnsNil() {
        XCTAssertNil(AgentResumeContext.makeMessages(history: [], freshSystemPrompt: "sys"))
    }

    func test_makeMessages_historyWithoutSystem_insertsSystemAtFront() {
        let history = [AgentMessage(role: .user, content: "hi")]
        let messages = AgentResumeContext.makeMessages(history: history, freshSystemPrompt: "sys")
        XCTAssertEqual(messages?.first?.role, .system)
        XCTAssertEqual(messages?.first?.content, "sys")
        XCTAssertEqual(messages?.last?.role, .user)
        XCTAssertEqual(messages?.count, 3)
    }

    // MARK: - 结束方式分类（取消 vs 失败 vs 完成）

    func test_completedRun_terminationCompleted() async {
        let runner = AgentRunner(maxSteps: 5, backendFactory: { _ in
            ScriptedBackend(steps: [.text("all done")])
        })
        await runAndWait(runner)

        XCTAssertEqual(runner.finalText, "all done")
        XCTAssertNil(runner.error)
        XCTAssertEqual(runner.state.termination, .completed)
    }

    func test_backendThrowsNetworkError_terminationFailed_resumable() async {
        let runner = AgentRunner(maxSteps: 5, backendFactory: { _ in
            ScriptedBackend(steps: [.fail(URLError(.networkConnectionLost))])
        })
        await runAndWait(runner)

        XCTAssertNotNil(runner.error)
        XCTAssertEqual(runner.state.termination, .failed)
    }

    func test_timeout_terminationFailed_resumable() async {
        let runner = AgentRunner(maxSteps: 5, backendFactory: { _ in
            SlowBackend(delay: 10.0)
        })
        runner.timeoutSeconds = 0.3
        await runAndWait(runner, timeout: 5.0)

        XCTAssertNotNil(runner.error)
        XCTAssertEqual(runner.state.termination, .failed)
    }

    func test_userCancel_terminationCancelled_notResumable() async {
        let runner = AgentRunner(maxSteps: 5, backendFactory: { _ in
            SlowBackend(delay: 10.0)
        })
        runner.run(messages: [AgentMessage(role: .user, content: "hi")],
                   tools: [], config: cfg, context: ctx)

        try? await Task.sleep(for: .milliseconds(50))
        runner.cancel()

        let deadline = Date().addingTimeInterval(2)
        while runner.state.termination == .running && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertFalse(runner.isRunning)
        XCTAssertNotNil(runner.error, "取消仍有 error 文案")
        XCTAssertEqual(runner.state.termination, .cancelled,
                       "用户取消必须归类为 cancelled（UI 据此不提供「继续」入口）")
    }

    func test_newRun_resetsTermination() async {
        // 同一 runner 复用：失败后新一轮 run 先把 termination 复位为 running，
        // 本轮正常完成则归类为 completed（共享 backend 的 steps 耗尽后回退 .text("done")）
        let backend = ScriptedBackend(steps: [.fail(URLError(.timedOut))])
        let runner = AgentRunner(maxSteps: 5, backendFactory: { _ in backend })
        await runAndWait(runner)
        XCTAssertEqual(runner.state.termination, .failed)

        await runAndWait(runner)
        XCTAssertNil(runner.error)
        XCTAssertEqual(runner.finalText, "done")
        XCTAssertEqual(runner.state.termination, .completed)
    }

    // MARK: - 续跑集成：已完成工具调用结果带进新 run

    func test_resume_carriesCompletedToolResults_doesNotRestartFromScratch() async {
        // run1：read_document 已完成，第二轮请求时网络中断
        let spy = SpyTool(name: "read_document", result: "DOCUMENT_BODY_XYZ")
        let failingBackend = ScriptedBackend(steps: [
            .toolCall(id: "tc1", name: "read_document", args: "{}"),
            .fail(URLError(.networkConnectionLost)),
        ])
        let runner1 = AgentRunner(maxSteps: 5, backendFactory: { _ in failingBackend })
        await runAndWait(runner1, tools: [spy], userMessage: "summarize the doc")

        XCTAssertEqual(runner1.state.termination, .failed)
        XCTAssertEqual(spy.callCount, 1)

        // 续跑上下文 = 原始指令 + 已完成工具调用结果 + 续跑指令
        guard let resumeMessages = AgentResumeContext.makeMessages(
            history: runner1.finalMessages, freshSystemPrompt: "fresh system"
        ) else {
            return XCTFail("失败 run 应保留可续跑的历史")
        }

        // run2（续跑）：后端直接给最终文本
        let resumeBackend = ScriptedBackend(steps: [.text("summary done")])
        let runner2 = AgentRunner(maxSteps: 5, backendFactory: { _ in resumeBackend })
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            runner2.onComplete = { cont.resume() }
            runner2.run(messages: resumeMessages, tools: [spy], config: cfg, context: ctx)
        }

        XCTAssertEqual(runner2.finalText, "summary done")
        XCTAssertEqual(runner2.state.termination, .completed)

        // 发给续跑后端的请求包含 run1 已完成的工具结果与原始指令
        let sent = resumeBackend.receivedMessages.first ?? []
        XCTAssertTrue(sent.contains { $0.role == .tool && $0.content.contains("DOCUMENT_BODY_XYZ") },
                      "续跑请求必须带上已完成工具调用的结果")
        XCTAssertTrue(sent.contains { $0.role == .user && $0.content == "summarize the doc" },
                      "续跑请求必须保留原始指令")
        XCTAssertEqual(sent.last?.role, .user, "续跑指令以 user 消息结尾")
        // 已完成的工具没有被重新执行（脚本后端没再发 toolCall）
        XCTAssertEqual(spy.callCount, 1)
    }

    // MARK: - Helpers

    private func runAndWait(
        _ runner: AgentRunner,
        tools: [any AgentTool] = [],
        userMessage: String = "test",
        timeout: TimeInterval = 10.0
    ) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            runner.onComplete = { cont.resume() }
            runner.run(
                messages: [AgentMessage(role: .user, content: userMessage)],
                tools: tools,
                config: cfg,
                context: ctx
            )
        }
    }
}

// MARK: - Test doubles

private final class ScriptedBackend: AgentBackend, @unchecked Sendable {
    enum Step {
        case text(String)
        case toolCall(id: String, name: String, args: String)
        case fail(Error)
    }

    private let steps: [Step]
    private var index = 0
    private let lock  = NSLock()
    private(set) var receivedMessages: [[AgentMessage]] = []

    init(steps: [Step]) { self.steps = steps }

    func complete(messages: [AgentMessage], tools: [any AgentTool]) async throws -> AgentCompletionResponse {
        lock.lock()
        receivedMessages.append(messages)
        let step = index < steps.count ? steps[index] : .text("done")
        index += 1
        lock.unlock()

        switch step {
        case .text(let text):
            return AgentCompletionResponse(text: text, toolCalls: [], finishReason: "stop")
        case .toolCall(let id, let name, let args):
            return AgentCompletionResponse(
                text: "",
                toolCalls: [AgentToolCall(id: id, name: name, argumentsJSON: args)],
                finishReason: "tool_calls"
            )
        case .fail(let error):
            throw error
        }
    }
}

/// 慢速 backend，模拟网络延迟（用于测试超时 / 取消）。
private final class SlowBackend: AgentBackend, @unchecked Sendable {
    private let delay: TimeInterval
    init(delay: TimeInterval) { self.delay = delay }

    func complete(messages: [AgentMessage], tools: [any AgentTool]) async throws -> AgentCompletionResponse {
        try await Task.sleep(for: .seconds(delay))
        return AgentCompletionResponse(text: "too late", toolCalls: [], finishReason: "stop")
    }
}

/// 记录调用次数的 spy 工具。
private final class SpyTool: AgentTool, @unchecked Sendable {
    let spec: AgentToolSpec
    private let result: String
    private(set) var callCount = 0

    init(name: String, result: String) {
        self.spec   = AgentToolSpec(name: name, description: "Spy tool: \(name)")
        self.result = result
    }

    func execute(arguments: [String: AnySendableValue], context: any AgentContextProtocol) async throws -> String {
        callCount += 1
        return result
    }
}
