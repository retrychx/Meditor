import XCTest
@testable import MEditor

// MARK: - AgentRunnerStabilityTests
//
// Agent 稳定性回归测试（eval 集）—— AgentRunner run loop：
//   B7  最终答案恰好在第 maxSteps 轮返回 → 不报步数超限（off-by-one 回归）
//   B8  工具执行中被 cancel 中断 → reconcileToolResults 保证 tool_calls 配对
//   B9  后端返回非法参数 JSON → 不执行工具、回灌「解析失败」tool result
//   B10 classifyError 文案：401→鉴权 / 429→频繁或额度 / URLError.timedOut→超时
//
// mock 模式沿用 AgentRunnerMultiTurnTests（其 mock 为 private，这里自带等价实现）。

@MainActor
final class AgentRunnerStabilityTests: XCTestCase {

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

    // MARK: - B7 maxSteps off-by-one：第 maxSteps 轮拿到 finalText 不算超限

    func test_finalAnswerExactlyAtMaxSteps_noStepLimitError() async {
        let spy = RunnerSpyTool(name: "read_document", result: "doc")
        let backend = ScriptedBackend(script: [
            .respond(AgentCompletionResponse(
                text: "",
                toolCalls: [AgentToolCall(id: "tc1", name: "read_document", argumentsJSON: "{}")],
                finishReason: "tool_calls"
            )),
            .respond(AgentCompletionResponse(text: "最终答案", toolCalls: [], finishReason: "stop")),
        ])
        let runner = AgentRunner(maxSteps: 2, backendFactory: { _ in backend })

        await runAndWait(runner, tools: [spy])

        XCTAssertTrue(spy.wasCalled)
        XCTAssertEqual(runner.finalText, "最终答案")
        XCTAssertNil(runner.error, "最终答案恰好在第 maxSteps 轮返回时不应误报步数超限")
    }

    // MARK: - B8 工具执行中被 cancel → 未应答的 tool call 补合成中断结果

    func test_cancelledDuringToolExecution_toolResultsReconciled() async {
        let backend = ScriptedBackend(script: [
            // 第一轮：一次返回两个 tool call；第一个工具在执行时 cancel 整个 runner
            .respond(AgentCompletionResponse(
                text: "",
                toolCalls: [
                    AgentToolCall(id: "tc1", name: "cancel_tool", argumentsJSON: "{}"),
                    AgentToolCall(id: "tc2", name: "read_document", argumentsJSON: "{}"),
                ],
                finishReason: "tool_calls"
            )),
            .respond(AgentCompletionResponse(text: "不应到达", toolCalls: [], finishReason: "stop")),
        ])
        let runner = AgentRunner(maxSteps: 5, backendFactory: { _ in backend })
        let cancelTool = SelfCancellingTool(name: "cancel_tool") { [weak runner] in
            runner?.cancel()
        }
        let spy = RunnerSpyTool(name: "read_document", result: "doc")

        await runAndWait(runner, tools: [cancelTool, spy])

        // tc2 不应被执行（循环在 tc1 之后检测到取消）
        XCTAssertFalse(spy.wasCalled, "取消后不应继续执行后续工具")

        // finalMessages 中每个 assistant tool_call 都必须有配对的 tool result
        let allCalls = runner.finalMessages.flatMap { $0.toolCalls ?? [] }
        XCTAssertEqual(Set(allCalls.map(\.id)), ["tc1", "tc2"])
        let answered = Set(runner.finalMessages.compactMap { $0.role == .tool ? $0.toolCallID : nil })
        for call in allCalls {
            XCTAssertTrue(answered.contains(call.id), "tool_call \(call.id) 必须有配对 tool result")
        }

        // tc2 的配对结果应是合成的「中断」结果
        let synthetic = runner.finalMessages.first { $0.role == .tool && $0.toolCallID == "tc2" }
        XCTAssertTrue(synthetic?.content.contains("中断") == true,
                      "未执行的工具调用应补合成含「中断」字样的错误结果，实际：\(synthetic?.content ?? "nil")")
    }

    // MARK: - B9 非法参数 JSON → 短路：不执行工具、回灌解析失败

    func test_invalidArgumentsJSON_toolSkipped_parseErrorFedBack() async {
        let spy = RunnerSpyTool(name: "patch_document", result: "patched")
        let backend = ScriptedBackend(script: [
            .respond(AgentCompletionResponse(
                text: "",
                toolCalls: [AgentToolCall(id: "bad1", name: "patch_document", argumentsJSON: "{not valid json")],
                finishReason: "tool_calls"
            )),
            .respond(AgentCompletionResponse(text: "已重新生成参数", toolCalls: [], finishReason: "stop")),
        ])
        let runner = AgentRunner(maxSteps: 5, backendFactory: { _ in backend })

        await runAndWait(runner, tools: [spy])

        XCTAssertFalse(spy.wasCalled, "参数 JSON 非法时工具闭包不应被调用")
        XCTAssertEqual(runner.finalText, "已重新生成参数")

        // 回灌的 tool result 含「解析失败」
        let feedback = runner.finalMessages.first { $0.role == .tool && $0.toolCallID == "bad1" }
        XCTAssertTrue(feedback?.content.contains("解析失败") == true,
                      "回灌的 tool result 应含「解析失败」，实际：\(feedback?.content ?? "nil")")

        // 第二轮请求应携带该错误 tool result（模型据此恢复）
        XCTAssertGreaterThanOrEqual(backend.receivedMessages.count, 2)
        let secondRound = backend.receivedMessages[1]
        XCTAssertTrue(secondRound.contains {
            $0.role == .tool && $0.toolCallID == "bad1" && $0.content.contains("解析失败")
        }, "第二轮发给后端的 messages 应包含解析失败的 tool result")
    }

    // MARK: - B9 附带：AgentToolCall 模型行为钉死（解析失败保留原文）

    func test_toolCallInit_invalidJSON_setsParseErrorAndKeepsRaw() {
        let raw = "{not valid json"
        let call = AgentToolCall(id: "x", name: "t", argumentsJSON: raw)
        XCTAssertNotNil(call.argumentsParseError)
        XCTAssertEqual(call.rawArgumentsJSON, raw, "rawArgumentsJSON 必须保留原始非法文本")
        XCTAssertTrue(call.arguments.isEmpty)

        // 注意：JSONSerialization 的 NSNumber 桥接使 0/1 优先匹配 Bool（现有行为，勿钉反例），
        // 这里用字符串与普通整数验证正常解析路径。
        let good = AgentToolCall(id: "y", name: "t", argumentsJSON: #"{"a":"ok","n":42}"#)
        XCTAssertNil(good.argumentsParseError)
        XCTAssertEqual(good.arguments["a"], .string("ok"))
        XCTAssertEqual(good.arguments["n"], .int(42))
    }

    // MARK: - B10 classifyError 文案（private，经 runner 错误路径断言 state.error）

    func test_classifyError_401_mapsToAuthMessage() async {
        let runner = await runBackendThrowing(AIError.server(401, "invalid api key"))
        XCTAssertTrue(runner.error?.contains("鉴权") == true,
                      "401 应映射为鉴权文案，实际：\(runner.error ?? "nil")")
    }

    func test_classifyError_429_mapsToRateLimitMessage() async {
        let runner = await runBackendThrowing(AIError.server(429, "rate limited"))
        let error = runner.error ?? ""
        XCTAssertTrue(error.contains("频繁") || error.contains("额度"),
                      "429 应映射为频率/额度文案，实际：\(error)")
    }

    func test_classifyError_urlTimedOut_mapsToTimeoutMessage() async {
        let runner = await runBackendThrowing(URLError(.timedOut))
        XCTAssertTrue(runner.error?.contains("超时") == true,
                      "URLError.timedOut 应映射为超时文案，实际：\(runner.error ?? "nil")")
    }

    // MARK: - B11 cancel 后旧 run 与新 run 的竞态：旧收尾不得覆盖新 run 状态
    //
    // 场景：旧 run 卡在不可取消点（工具确认 continuation）→ cancel() 同步放行
    // isRunning → 新 run 立即启动并完成 → 旧 run 被放行走到收尾。
    // 断言：旧收尾因 generation 不匹配静默放弃（不覆盖 finalText/isRunning/error、
    // 不再次触发 onComplete）。覆盖的是收尾守卫 + 循环顶代际检查整条路径。

    func test_staleRunCleanup_doesNotOverwriteNewRun() async {
        let stuck = StuckTool(name: "stuck_tool")
        // 旧 run 的 backend：第一轮发起会卡住的工具调用
        let oldBackend = ScriptedBackend(script: [
            .respond(AgentCompletionResponse(
                text: "",
                toolCalls: [AgentToolCall(id: "tc1", name: "stuck_tool", argumentsJSON: "{}")],
                finishReason: "tool_calls"
            )),
        ])
        // 新 run 的 backend：直接给出最终答案
        let newBackend = ScriptedBackend(script: [
            .respond(AgentCompletionResponse(text: "新 run 答案", toolCalls: [], finishReason: "stop")),
        ])
        let queue = BackendQueue([oldBackend, newBackend])
        let runner = AgentRunner(maxSteps: 5, backendFactory: { _ in queue.next() })

        // 1) 启动旧 run，等它卡进工具
        runner.run(messages: [AgentMessage(role: .user, content: "old")],
                   tools: [stuck], config: cfg, context: ctx)
        let startDeadline = Date().addingTimeInterval(2)
        while !stuck.didStart && Date() < startDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(stuck.didStart, "旧 run 应已进入卡住的工具")

        // 2) cancel：同步放行 isRunning（旧 _run 仍卡在 continuation 上）
        runner.cancel()
        XCTAssertFalse(runner.isRunning)

        // 3) 新 run 立即启动（旧 _run 还没退出），等待其完成
        var completeCount = 0
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            runner.onComplete = { completeCount += 1; cont.resume() }
            runner.run(messages: [AgentMessage(role: .user, content: "new")],
                       tools: [], config: cfg, context: ctx)
        }
        XCTAssertEqual(runner.finalText, "新 run 答案")

        // 4) 放行旧 run：其 _run 走到收尾，必须因代际不匹配静默放弃
        stuck.release()
        try? await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(runner.finalText, "新 run 答案", "旧 run 收尾不得覆盖新 run 的 finalText")
        XCTAssertFalse(runner.isRunning, "旧 run 收尾不得重置 isRunning")
        XCTAssertNil(runner.error, "旧 run 收尾不得写入 error")
        XCTAssertEqual(completeCount, 1, "旧 run 收尾不得再次触发 onComplete")
    }

    // MARK: - Helpers

    private func runAndWait(_ runner: AgentRunner, tools: [any AgentTool] = []) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            runner.onComplete = { cont.resume() }
            runner.run(
                messages: [AgentMessage(role: .user, content: "test")],
                tools: tools,
                config: cfg,
                context: ctx
            )
        }
    }

    /// 用一个首轮即抛错的 backend 跑 runner，返回结束后的 runner 供断言 error。
    private func runBackendThrowing(_ error: Error) async -> AgentRunner {
        let backend = ScriptedBackend(script: [.fail(error)])
        let runner = AgentRunner(maxSteps: 3, backendFactory: { _ in backend })
        await runAndWait(runner)
        return runner
    }
}

// MARK: - 私有测试 doubles

/// 按脚本依次返回响应或抛错的 backend；记录每轮收到的 messages。
private final class ScriptedBackend: AgentBackend, @unchecked Sendable {
    enum Step {
        case respond(AgentCompletionResponse)
        case fail(Error)
    }

    private var script: [Step]
    private let lock = NSLock()
    private(set) var receivedMessages: [[AgentMessage]] = []

    init(script: [Step]) { self.script = script }

    func complete(messages: [AgentMessage], tools: [any AgentTool]) async throws -> AgentCompletionResponse {
        lock.lock()
        receivedMessages.append(messages)
        let step = script.isEmpty
            ? Step.respond(AgentCompletionResponse(text: "done", toolCalls: [], finishReason: "stop"))
            : script.removeFirst()
        lock.unlock()
        switch step {
        case .respond(let response): return response
        case .fail(let error):       throw error
        }
    }
}

/// 记录是否被调用的 spy 工具。
private final class RunnerSpyTool: AgentTool, @unchecked Sendable {
    let spec: AgentToolSpec
    private let result: String
    private(set) var wasCalled = false

    init(name: String, result: String) {
        self.spec   = AgentToolSpec(name: name, description: "Spy tool: \(name)")
        self.result = result
    }

    func execute(arguments: [String: AnySendableValue], context: any AgentContextProtocol) async throws -> String {
        wasCalled = true
        return result
    }
}

/// 执行时在 MainActor 上调用给定闭包的工具——用于在工具执行中途 cancel runner。
private final class SelfCancellingTool: AgentTool, @unchecked Sendable {
    let spec: AgentToolSpec
    private let body: @MainActor @Sendable () -> Void

    init(name: String, body: @escaping @MainActor @Sendable () -> Void) {
        self.spec = AgentToolSpec(name: name, description: "Self-cancelling tool")
        self.body = body
    }

    func execute(arguments: [String: AnySendableValue], context: any AgentContextProtocol) async throws -> String {
        await body()
        return "cancel issued"
    }
}

/// 卡在不可取消点的工具：execute 挂起在 continuation 上，直到 release() 手动放行
/// （模拟命令确认对话框——continuation 不响应 Task 取消）。
private final class StuckTool: AgentTool, @unchecked Sendable {
    let spec: AgentToolSpec
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Never>?
    private(set) var didStart = false

    init(name: String) {
        self.spec = AgentToolSpec(name: name, description: "Stuck tool: \(name)")
    }

    func execute(arguments: [String: AnySendableValue], context: any AgentContextProtocol) async throws -> String {
        lock.lock(); didStart = true; lock.unlock()
        return await withCheckedContinuation { cont in
            lock.lock()
            continuation = cont
            lock.unlock()
        }
    }

    func release() {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: "stuck tool released")
    }
}

/// 按序派发 backend 的队列（backendFactory 是 @Sendable 闭包，用锁盒避免捕获可变 var）。
private final class BackendQueue: @unchecked Sendable {
    private let backends: [ScriptedBackend]
    private var index = 0
    private let lock = NSLock()

    init(_ backends: [ScriptedBackend]) { self.backends = backends }

    func next() -> ScriptedBackend {
        lock.lock(); defer { lock.unlock() }
        let backend = backends[min(index, backends.count - 1)]
        index += 1
        return backend
    }
}
