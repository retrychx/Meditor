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
