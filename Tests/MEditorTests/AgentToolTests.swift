import XCTest
@testable import MEditor

// MARK: - AgentToolTests
//
// 工具层单测：验证工具的参数解析、context 调用、错误格式化。
// 所有测试在 @MainActor 隔离下运行，与 AgentContextProtocol 的 isolation 一致。

@MainActor
final class AgentToolTests: XCTestCase {

    // MARK: - Setup

    var ctx: MockAgentContext!

    override func setUp() {
        super.setUp()
        ctx = MockAgentContext()
        ctx.currentDocument     = "Hello world\nSecond line\nThird line"
        ctx.currentDocumentName = "doc.md"
        ctx.addFile("notes.md", content: "# Notes\n\nSome notes here.\nMore content.")
        ctx.addFile("config.json", content: "{ \"key\": \"value\" }")
    }

    // MARK: - ReadDocumentTool

    func testReadDocument_currentDoc() async throws {
        let tool   = ReadDocumentTool()
        let result = try await tool.execute(arguments: [:], context: ctx)
        XCTAssertTrue(result.contains("Hello world"), "应返回当前文档内容")
        XCTAssertTrue(result.contains("doc.md"), "应包含文件名")
    }

    func testReadDocument_byFilename() async throws {
        let tool   = ReadDocumentTool()
        let result = try await tool.execute(arguments: ["filename": .string("notes.md")], context: ctx)
        XCTAssertTrue(result.contains("# Notes"), "应返回指定文件内容")
    }

    func testReadDocument_fileNotFound() async throws {
        let tool   = ReadDocumentTool()
        let result = try await tool.execute(arguments: ["filename": .string("nonexistent.md")], context: ctx)
        XCTAssertTrue(result.lowercased().contains("not found") || result.contains("未找到"), "找不到文件时应返回错误信息")
    }

    // MARK: - WriteDocumentTool

    func testWriteDocument_success() async throws {
        let tool    = WriteDocumentTool()
        let newContent = "# New Content\n\nReplaced."
        let result  = try await tool.execute(arguments: ["content": .string(newContent)], context: ctx)
        XCTAssertEqual(ctx.writtenContents.last, newContent, "应写入正确内容")
        XCTAssertTrue(result.contains("✅") || result.lowercased().contains("success") || result.contains("已写入"),
                      "成功时应有正向反馈")
    }

    func testWriteDocument_propagatesError() async throws {
        ctx.writeDocumentError = CocoaError(.fileWriteNoPermission)
        let tool   = WriteDocumentTool()
        let result = try await tool.execute(arguments: ["content": .string("x")], context: ctx)
        XCTAssertTrue(result.contains("❌") || result.lowercased().contains("error") || result.contains("错误"),
                      "写入失败时应返回错误消息")
    }

    // MARK: - PatchDocumentTool

    func testPatchDocument_success() async throws {
        let tool   = PatchDocumentTool()
        let result = try await tool.execute(
            arguments: ["find": .string("Hello world"), "replace": .string("Hi there")],
            context: ctx
        )
        XCTAssertEqual(ctx.patchCalls.count, 1, "应调用一次 patchDocument")
        XCTAssertEqual(ctx.patchCalls[0].find, "Hello world")
        XCTAssertEqual(ctx.patchCalls[0].replace, "Hi there")
        XCTAssertTrue(result.contains("✅") || result.contains("已替换"), "成功时应有正向反馈")
    }

    func testPatchDocument_allFlag() async throws {
        let tool = PatchDocumentTool()
        _ = try await tool.execute(
            arguments: ["find": .string("line"), "replace": .string("LINE"), "all": .bool(true)],
            context: ctx
        )
        XCTAssertTrue(ctx.patchCalls[0].all, "all=true 应传递到 context")
    }

    func testPatchDocument_notFound_returnsRichError() async throws {
        ctx.patchDocumentResult = .failure(
            PatchNotFoundError(query: "MISSING", nearbyContext: "...nearby...", strategy: "literal")
        )
        let tool   = PatchDocumentTool()
        let result = try await tool.execute(
            arguments: ["find": .string("MISSING"), "replace": .string("x")],
            context: ctx
        )
        XCTAssertTrue(result.contains("MISSING"), "错误信息应包含未匹配的 query")
        XCTAssertTrue(result.contains("❌"), "应包含错误标记")
    }

    func testPatchDocument_byFilename() async throws {
        let tool = PatchDocumentTool()
        _ = try await tool.execute(
            arguments: [
                "filename": .string("notes.md"),
                "find": .string("Some notes"),
                "replace": .string("Updated notes")
            ],
            context: ctx
        )
        // 指定文件时调用 patchFile，spy 同样在 patchCalls 里
        XCTAssertFalse(ctx.patchCalls.isEmpty, "应有 patch 调用")
    }

    // MARK: - CreateFileTool

    func testCreateFile_success() async throws {
        let tool   = CreateFileTool()
        let result = try await tool.execute(
            arguments: ["name": .string("new.md"), "content": .string("# New")],
            context: ctx
        )
        XCTAssertNotNil(ctx.files["new.md"], "文件应已写入 context")
        XCTAssertTrue(result.contains("✅") || result.contains("已创建"), "成功时应有正向反馈")
    }

    func testCreateFile_alreadyExists() async throws {
        ctx.addFile("notes.md", content: "existing")
        ctx.createFileError = AgentContextError.fileAlreadyExists("notes.md")
        let tool   = CreateFileTool()
        let result = try await tool.execute(
            arguments: ["name": .string("notes.md"), "content": .string("x")],
            context: ctx
        )
        XCTAssertTrue(result.contains("❌") || result.contains("already") || result.contains("已存在"),
                      "文件已存在时应返回错误")
    }

    // MARK: - ListFilesTool

    func testListFiles_returnsAllFiles() async throws {
        let tool   = ListFilesTool()
        let result = try await tool.execute(arguments: [:], context: ctx)
        XCTAssertTrue(result.contains("notes.md"), "应包含 notes.md")
    }

    func testListFiles_extensionFilter() async throws {
        let tool   = ListFilesTool()
        let result = try await tool.execute(arguments: ["extension": .string("json")], context: ctx)
        XCTAssertTrue(result.contains("config.json"), "应包含 json 文件")
        XCTAssertFalse(result.contains("notes.md"), "不应包含 md 文件")
    }

    // MARK: - SearchWorkspaceTool

    func testSearchWorkspace_findsMatches() async throws {
        let tool   = SearchWorkspaceTool()
        let result = try await tool.execute(arguments: ["query": .string("Notes")], context: ctx)
        XCTAssertTrue(result.contains("notes.md"), "应找到 notes.md 中的匹配")
    }

    func testSearchWorkspace_noMatches() async throws {
        let tool   = SearchWorkspaceTool()
        let result = try await tool.execute(arguments: ["query": .string("XYZZY_NOT_EXIST")], context: ctx)
        XCTAssertTrue(result.contains("0") || result.contains("未找到") || result.contains("no results"),
                      "无匹配时应给出提示")
    }

    // MARK: - ResolveFile

    func testResolveFile_found() {
        let result = ctx.resolveFile("notes.md")
        if case .found(let url) = result {
            XCTAssertTrue(url.lastPathComponent == "notes.md")
        } else {
            XCTFail("应返回 .found")
        }
    }

    func testResolveFile_notFound() {
        let result = ctx.resolveFile("ghost.md")
        if case .notFound = result { /* pass */ } else {
            XCTFail("应返回 .notFound")
        }
    }

    func testResolveFile_ambiguous() {
        // 同名文件在不同"目录"
        ctx.addFile("a/readme.md", content: "A")
        ctx.addFile("b/readme.md", content: "B")
        let result = ctx.resolveFile("readme.md")
        if case .ambiguous(let urls) = result {
            XCTAssertEqual(urls.count, 2)
        } else {
            XCTFail("两个同名文件应返回 .ambiguous")
        }
    }
}

// MARK: - MockAgentBackend

/// 用于 AgentRunner 测试的 mock backend。
struct MockAgentBackend: AgentBackend {

    /// 预设的响应序列，每次 complete 弹出一个。
    var responses: [AgentCompletionResponse]
    private var index = 0

    mutating func next() -> AgentCompletionResponse {
        defer { index += 1 }
        return index < responses.count ? responses[index] : AgentCompletionResponse(text: "done", toolCalls: [], finishReason: "stop")
    }

    // AgentBackend 是 Sendable，用 actor 包一下状态
    func complete(messages: [AgentMessage], tools: [any AgentTool]) async throws -> AgentCompletionResponse {
        // 注意：测试时直接传固定值（通过 closure 捕获外部 counter）
        fatalError("Use MockAgentBackendActor for stateful tests")
    }
}

// MARK: - AgentRunnerTests

@MainActor
final class AgentRunnerTests: XCTestCase {

    func testRunner_singleTurn() async throws {
        var callCount = 0
        let runner = AgentRunner(
            maxSteps: 5,
            backendFactory: { _ in
                SingleResponseBackend(
                    response: AgentCompletionResponse(
                        text: "Done!", toolCalls: [], finishReason: "stop"
                    )
                )
            }
        )

        let ctx   = MockAgentContext()
        let tools: [any AgentTool] = []
        let msgs  = [AgentMessage(role: .user, content: "Hello")]
        let cfg   = AIConfig(kind: .disabled, baseURL: "", model: "", cliPath: "", cliModel: "", apiKey: "")

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            runner.onComplete = { cont.resume() }
            runner.start(messages: msgs, tools: tools, config: cfg, context: ctx)
        }

        XCTAssertEqual(runner.finalText, "Done!")
        XCTAssertNil(runner.error)
        XCTAssertFalse(runner.isRunning)
    }

    func testRunner_parseErrorToolCall_doesNotCrash() async throws {
        // _parse_error 工具调用应被 runner 处理为错误消息，不崩溃，并继续下一轮
        let runner = AgentRunner(
            maxSteps: 3,
            backendFactory: { _ in
                TwoStepBackend(
                    first: AgentCompletionResponse(
                        text: "",
                        toolCalls: [AgentToolCall(
                            id: "err1",
                            name: "_parse_error",
                            argumentsJSON: "{\"original_tool\":\"patch_document\",\"raw_arguments\":\"bad json\"}"
                        )],
                        finishReason: "tool_calls"
                    ),
                    second: AgentCompletionResponse(text: "Recovered", toolCalls: [], finishReason: "stop")
                )
            }
        )

        let ctx = MockAgentContext()
        let cfg = AIConfig(kind: .disabled, baseURL: "", model: "", cliPath: "", cliModel: "", apiKey: "")

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            runner.onComplete = { cont.resume() }
            runner.start(messages: [AgentMessage(role: .user, content: "test")],
                         tools: [], config: cfg, context: ctx)
        }

        XCTAssertFalse(runner.isRunning)
        // Runner 应从 _parse_error 中恢复，最终给出文字响应
        XCTAssertEqual(runner.finalText, "Recovered")
    }
}

// MARK: - Minimal test backends

private struct SingleResponseBackend: AgentBackend {
    let response: AgentCompletionResponse
    func complete(messages: [AgentMessage], tools: [any AgentTool]) async throws -> AgentCompletionResponse { response }
}

private final class TwoStepBackend: AgentBackend, @unchecked Sendable {
    let first: AgentCompletionResponse
    let second: AgentCompletionResponse
    private var step = 0
    private let lock = NSLock()
    init(first: AgentCompletionResponse, second: AgentCompletionResponse) {
        self.first = first; self.second = second
    }
    func complete(messages: [AgentMessage], tools: [any AgentTool]) async throws -> AgentCompletionResponse {
        lock.lock(); defer { lock.unlock() }
        defer { step += 1 }
        return step == 0 ? first : second
    }
}
