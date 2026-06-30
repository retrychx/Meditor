import XCTest
@testable import MEditor

// MARK: - AgentRunnerMultiTurnTests
//
// 覆盖 AgentRunner 的多轮工具调用、错误恢复、步数限制和超时等核心流程。

@MainActor
final class AgentRunnerMultiTurnTests: XCTestCase {

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

    // MARK: - Single Turn（无工具调用）

    func test_singleTurn_noTools_returnsFinalText() async {
        let runner = makeRunner(maxSteps: 5, responses: [
            .text("Hello from AI")
        ])
        await runAndWait(runner)

        XCTAssertEqual(runner.finalText, "Hello from AI")
        XCTAssertNil(runner.error)
        XCTAssertFalse(runner.isRunning)
    }

    // MARK: - 单次工具调用 → 工具结果 → 最终文本

    func test_singleToolCall_executesToolAndReturnsText() async throws {
        let spy = SpyTool(name: "read_document", result: "Document content: hello world")

        let runner = makeRunner(maxSteps: 5, responses: [
            .toolCall(id: "tc1", name: "read_document", args: "{}"),
            .text("I read: hello world")
        ])

        await runAndWait(runner, tools: [spy])

        XCTAssertTrue(spy.wasCalled, "工具应被调用一次")
        XCTAssertEqual(runner.finalText, "I read: hello world")
        // 应有两个 step：toolCall + toolCallDone
        let doneSteps = runner.steps.filter(\.isDone)
        XCTAssertEqual(doneSteps.count, 1)
    }

    // MARK: - 多次连续工具调用

    func test_multipleToolCalls_sequentialExecution() async {
        let readSpy  = SpyTool(name: "read_document",  result: "Doc: abc")
        let writeSpy = SpyTool(name: "write_document", result: "[OK] Written")

        let runner = makeRunner(maxSteps: 10, responses: [
            .toolCall(id: "tc1", name: "read_document",  args: "{}"),
            .toolCall(id: "tc2", name: "write_document", args: "{\"content\":\"new\"}"),
            .text("Done: read and wrote")
        ])

        await runAndWait(runner, tools: [readSpy, writeSpy])

        XCTAssertTrue(readSpy.wasCalled,  "read_document 应被调用")
        XCTAssertTrue(writeSpy.wasCalled, "write_document 应被调用")
        XCTAssertEqual(runner.finalText, "Done: read and wrote")

        let doneSteps = runner.steps.filter(\.isDone)
        XCTAssertEqual(doneSteps.count, 2, "应有两个已完成的工具步骤")
    }

    // MARK: - 工具调用失败（工具抛出错误）

    func test_toolThrowsError_marksStepAsError_continues() async {
        let failTool = FailingTool(name: "patch_document", error: AgentError.executionError("找不到目标文本"))

        let runner = makeRunner(maxSteps: 5, responses: [
            .toolCall(id: "tc1", name: "patch_document", args: "{\"find\":\"x\",\"replace\":\"y\"}"),
            .text("patch failed but I recovered")
        ])

        await runAndWait(runner, tools: [failTool])

        // Runner 应继续运行，不崩溃
        XCTAssertFalse(runner.isRunning)
        XCTAssertNil(runner.error, "工具错误不应导致 runner 整体失败")
        XCTAssertEqual(runner.finalText, "patch failed but I recovered")

        // 错误步骤应被标记
        let errorSteps = runner.steps.filter(\.isError)
        XCTAssertEqual(errorSteps.count, 1, "应有一个错误标记的工具步骤")
    }

    // MARK: - _parse_error 特殊工具（JSON 解析失败）

    func test_parseErrorTool_recoversAndContinues() async {
        let runner = makeRunner(maxSteps: 5, responses: [
            .toolCallRaw(id: "e1", name: "_parse_error",
                         args: "{\"original_tool\":\"patch_document\",\"raw_arguments\":\"bad json\"}"),
            .text("Recovered from parse error")
        ])

        await runAndWait(runner)

        XCTAssertFalse(runner.isRunning)
        XCTAssertEqual(runner.finalText, "Recovered from parse error")
    }

    // MARK: - 未知工具名（graceful fallback）

    func test_unknownToolName_returnsError_doesNotCrash() async {
        let runner = makeRunner(maxSteps: 5, responses: [
            .toolCall(id: "tc1", name: "nonexistent_tool", args: "{}"),
            .text("Handled unknown tool")
        ])

        await runAndWait(runner, tools: [])

        XCTAssertFalse(runner.isRunning)
        // Runner 应返回最终文本，不崩溃
        XCTAssertEqual(runner.finalText, "Handled unknown tool")
    }

    // MARK: - maxSteps 超限

    func test_maxSteps_exceeded_setsError() async {
        // 无限返回 toolCall，永远不给 stop
        let infiniteTool = SpyTool(name: "read_document", result: "still reading")
        let infiniteBackend = InfiniteToolCallBackend(toolName: "read_document")

        let runner = AgentRunner(
            maxSteps: 3,
            backendFactory: { _ in infiniteBackend }
        )

        await runAndWait(runner, tools: [infiniteTool])

        XCTAssertFalse(runner.isRunning)
        XCTAssertNotNil(runner.error, "超过最大步数应设置 error")
        XCTAssertTrue(runner.error?.contains("步数") == true || runner.error?.contains("step") == true,
                      "错误消息应提示步数超限")
    }

    // MARK: - 取消

    func test_cancel_setsErrorAndStopsRunning() async {
        let slowBackend = SlowBackend(delay: 5.0, response: .text("Too late"))
        let runner = AgentRunner(maxSteps: 5, backendFactory: { _ in slowBackend })
        runner.run(messages: [AgentMessage(role: .user, content: "Hi")],
                   tools: [], config: cfg, context: ctx)

        // 短暂等待后取消
        try? await Task.sleep(for: .milliseconds(50))
        runner.cancel()

        // 等待 runner 停止
        let deadline = Date().addingTimeInterval(2)
        while runner.isRunning && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertFalse(runner.isRunning)
        XCTAssertNotNil(runner.error, "取消后 error 应非 nil")
    }

    // MARK: - Timeout

    func test_timeout_setsTimeoutError() async {
        let slowBackend = SlowBackend(delay: 10.0, response: .text("Never arrives"))
        let runner = AgentRunner(maxSteps: 5, backendFactory: { _ in slowBackend })
        runner.timeoutSeconds = 0.3   // 300ms 超时

        await runAndWait(runner, timeout: 5.0)

        XCTAssertFalse(runner.isRunning)
        XCTAssertNotNil(runner.error, "超时后应设置 error")
        XCTAssertTrue(runner.error?.contains("超时") == true || runner.error?.contains("timeout") == true,
                      "错误消息应提示超时")
    }

    // MARK: - onChunk 回调

    func test_onChunk_calledDuringStreaming() async {
        var chunks: [String] = []
        let runner = makeRunner(maxSteps: 5, responses: [.text("final text")])
        runner.onChunk = { chunk in chunks.append(chunk) }

        await runAndWait(runner)

        // 注意：RestAgentBackend 的流式由 backend 决定，这里 mock backend 不发 chunk
        // 只测 finalText 正确；真实流式测试需要 integration test
        XCTAssertEqual(runner.finalText, "final text")
    }

    // MARK: - 工具调用后继续多轮

    func test_threeRound_toolCallChain() async {
        let spyA = SpyTool(name: "list_files",   result: "[\"a.md\",\"b.md\"]")
        let spyB = SpyTool(name: "read_document", result: "content of a.md")
        let spyC = SpyTool(name: "write_document", result: "[OK]")

        let runner = makeRunner(maxSteps: 15, responses: [
            .toolCall(id: "1", name: "list_files",    args: "{}"),
            .toolCall(id: "2", name: "read_document", args: "{\"filename\":\"a.md\"}"),
            .toolCall(id: "3", name: "write_document", args: "{\"content\":\"updated\"}"),
            .text("All done in 3 steps")
        ])

        await runAndWait(runner, tools: [spyA, spyB, spyC])

        XCTAssertTrue(spyA.wasCalled)
        XCTAssertTrue(spyB.wasCalled)
        XCTAssertTrue(spyC.wasCalled)
        XCTAssertEqual(runner.finalText, "All done in 3 steps")
        XCTAssertEqual(runner.steps.filter(\.isDone).count, 3)
    }

    // MARK: - Helpers

    private func makeRunner(maxSteps: Int, responses: [MockResponse]) -> AgentRunner {
        AgentRunner(
            maxSteps: maxSteps,
            backendFactory: { _ in SequentialBackend(responses: responses) }
        )
    }

    private func runAndWait(_ runner: AgentRunner, tools: [any AgentTool] = [], timeout: TimeInterval = 10.0) async {
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
}

// MARK: - Mock Responses

private enum MockResponse {
    case text(String)
    case toolCall(id: String, name: String, args: String)
    case toolCallRaw(id: String, name: String, args: String)  // same as toolCall for now

    var asCompletion: AgentCompletionResponse {
        switch self {
        case .text(let t):
            return AgentCompletionResponse(text: t, toolCalls: [], finishReason: "stop")
        case .toolCall(let id, let name, let args), .toolCallRaw(let id, let name, let args):
            return AgentCompletionResponse(
                text: "",
                toolCalls: [AgentToolCall(id: id, name: name, argumentsJSON: args)],
                finishReason: "tool_calls"
            )
        }
    }
}

// MARK: - Test Backends

/// 按顺序返回预设响应的测试 backend。
private final class SequentialBackend: AgentBackend, @unchecked Sendable {
    private let responses: [MockResponse]
    private var index = 0
    private let lock  = NSLock()

    init(responses: [MockResponse]) { self.responses = responses }

    func complete(messages: [AgentMessage], tools: [any AgentTool]) async throws -> AgentCompletionResponse {
        lock.lock(); defer { lock.unlock() }
        let resp = index < responses.count ? responses[index] : MockResponse.text("done")
        index += 1
        return resp.asCompletion
    }
}

/// 无限返回同一个工具调用（用于测试 maxSteps）。
private final class InfiniteToolCallBackend: AgentBackend, @unchecked Sendable {
    private let toolName: String
    private var callCount = 0

    init(toolName: String) { self.toolName = toolName }

    func complete(messages: [AgentMessage], tools: [any AgentTool]) async throws -> AgentCompletionResponse {
        callCount += 1
        return AgentCompletionResponse(
            text: "",
            toolCalls: [AgentToolCall(id: "tc\(callCount)", name: toolName, argumentsJSON: "{}")],
            finishReason: "tool_calls"
        )
    }
}

/// 慢速 backend，模拟网络延迟（用于测试超时 / 取消）。
private final class SlowBackend: AgentBackend, @unchecked Sendable {
    private let delay: TimeInterval
    private let response: MockResponse

    init(delay: TimeInterval, response: MockResponse) {
        self.delay    = delay
        self.response = response
    }

    func complete(messages: [AgentMessage], tools: [any AgentTool]) async throws -> AgentCompletionResponse {
        try await Task.sleep(for: .seconds(delay))
        return response.asCompletion
    }
}

// MARK: - Test Tools

/// 记录是否被调用，返回固定结果的 spy 工具。
private final class SpyTool: AgentTool, @unchecked Sendable {
    let spec: AgentToolSpec
    private let result: String
    private(set) var wasCalled = false
    private(set) var lastArguments: [String: AnySendableValue] = [:]

    init(name: String, result: String) {
        self.spec   = AgentToolSpec(name: name, description: "Spy tool: \(name)")
        self.result = result
    }

    func execute(arguments: [String: AnySendableValue], context: any AgentContextProtocol) async throws -> String {
        wasCalled = true
        lastArguments = arguments
        return result
    }
}

/// 总是抛出错误的工具（测试错误恢复）。
private struct FailingTool: AgentTool, Sendable {
    let spec: AgentToolSpec
    let error: Error

    init(name: String, error: Error) {
        self.spec  = AgentToolSpec(name: name, description: "Failing tool: \(name)")
        self.error = error
    }

    func execute(arguments: [String: AnySendableValue], context: any AgentContextProtocol) async throws -> String {
        throw error
    }
}
