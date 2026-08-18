import XCTest
@testable import MEditor

// MARK: - WriteDiffPreviewTests
//
// 写确认 diff 预览单测：写工具在 confirmFileWrite 前预算「写前 vs 写入」的段落级 diff。
//   - write / patch / create 三条路径都携带正确的 diff 数据
//   - 写前内容走 fileContentFull（tab 内存优先入口），不是 readFile
//   - 超过大小上限退化为 .tooLarge，不算 diff；写前内容不可得退化为 .unavailable
//   - 只实现旧签名（path/summary）的 conformer 经协议默认转发，语义不变
// mock 模式同 FileWriteConfirmationTests（MockAgentContext spy + 结果注入）。

@MainActor
final class WriteDiffPreviewTests: XCTestCase {

    // MARK: - Setup

    var ctx: MockAgentContext!

    override func setUp() {
        super.setUp()
        ctx = MockAgentContext()
        // 段落以空行分隔（ParagraphDiffer 按空行切段），方便精确断言 hunk
        ctx.currentDocument     = "Alpha\n\nBeta\n\nGamma"
        ctx.currentDocumentName = "doc.md"
        ctx.addFile("notes.md", content: "Alpha\n\nBeta")
    }

    /// 从 preview 取 hunks（非 hunks 形态直接 fail）
    private func hunks(of preview: FileWritePreview?,
                       file: StaticString = #filePath, line: UInt = #line) -> [WriteDiffHunk] {
        guard let preview, case .hunks(let h) = preview.diff else {
            XCTFail("期望 diff 为 hunks 形态", file: file, line: line)
            return []
        }
        return h
    }

    // MARK: - write_document

    func testWriteDocument_currentDoc_carriesParagraphDiff() async throws {
        _ = try await WriteDocumentTool().execute(
            arguments: ["content": .string("Alpha\n\nBETA\n\nGamma")],
            context: ctx
        )
        let h = hunks(of: ctx.confirmedWritePreviews.first)
        XCTAssertEqual(h.count, 1, "只有一个段落被改动")
        XCTAssertEqual(h[0].original, "Beta")
        XCTAssertEqual(h[0].modified, "BETA")
    }

    func testWriteDocument_existingFile_diffAgainstOldContent() async throws {
        _ = try await WriteDocumentTool().execute(
            arguments: ["filename": .string("notes.md"),
                        "content": .string("Alpha\n\nBeta\n\nDelta")],
            context: ctx
        )
        let preview = ctx.confirmedWritePreviews.first
        XCTAssertEqual(preview?.path.hasSuffix("notes.md"), true)
        let h = hunks(of: preview)
        XCTAssertEqual(h.count, 1, "末尾新增一段")
        XCTAssertEqual(h[0].original, "", "纯新增段落的 original 应为空")
        XCTAssertEqual(h[0].modified, "Delta")
    }

    func testWriteDocument_newFile_allInsertions() async throws {
        _ = try await WriteDocumentTool().execute(
            arguments: ["filename": .string("brand-new.md"),
                        "content": .string("# Title\n\nBody")],
            context: ctx
        )
        let h = hunks(of: ctx.confirmedWritePreviews.first)
        XCTAssertEqual(h.count, 2)
        XCTAssertTrue(h.allSatisfy { $0.original.isEmpty }, "新文件的 diff 应全部为纯新增")
        XCTAssertEqual(h.map(\.modified), ["# Title", "Body"])
    }

    // MARK: - patch_document

    func testPatchDocument_currentDoc_previewsPatchedContent() async throws {
        _ = try await PatchDocumentTool().execute(
            arguments: ["find": .string("Beta"), "replace": .string("BETA")],
            context: ctx
        )
        let h = hunks(of: ctx.confirmedWritePreviews.first)
        XCTAssertEqual(h.count, 1)
        XCTAssertEqual(h[0].original, "Beta")
        XCTAssertEqual(h[0].modified, "BETA", "预览应与 PatchEngine 预演结果一致")
    }

    func testPatchDocument_existingFile_carriesDiff() async throws {
        _ = try await PatchDocumentTool().execute(
            arguments: ["filename": .string("notes.md"),
                        "find": .string("Beta"), "replace": .string("BETA")],
            context: ctx
        )
        let h = hunks(of: ctx.confirmedWritePreviews.first)
        XCTAssertEqual(h.count, 1)
        XCTAssertEqual(h[0].original, "Beta")
        XCTAssertEqual(h[0].modified, "BETA")
    }

    func testPatchDocument_missingFile_diffUnavailable() async throws {
        _ = try await PatchDocumentTool().execute(
            arguments: ["filename": .string("ghost.md"),
                        "find": .string("x"), "replace": .string("y")],
            context: ctx
        )
        guard case .unavailable = ctx.confirmedWritePreviews.first?.diff else {
            return XCTFail("目标不可解析时 diff 应退化为 unavailable")
        }
    }

    // MARK: - create_file / write_file

    func testCreateFile_allInsertions() async throws {
        _ = try await CreateFileTool().execute(
            arguments: ["filename": .string("created.md"),
                        "content": .string("# New\n\nBody")],
            context: ctx
        )
        let h = hunks(of: ctx.confirmedWritePreviews.first)
        XCTAssertEqual(h.count, 2)
        XCTAssertTrue(h.allSatisfy { $0.original.isEmpty }, "create_file 的 diff 应全部为纯新增")
    }

    func testWriteFile_existingFile_carriesDiff() async throws {
        _ = try await WriteFileTool().execute(
            arguments: ["filename": .string("notes.md"),
                        "content": .string("Alpha\n\nREWRITTEN")],
            context: ctx
        )
        let h = hunks(of: ctx.confirmedWritePreviews.first)
        XCTAssertEqual(h.count, 1)
        XCTAssertEqual(h[0].original, "Beta")
        XCTAssertEqual(h[0].modified, "REWRITTEN")
    }

    // MARK: - tab 内存内容优先

    func testWriteFile_prefersFullContentOverDisk() async throws {
        // fileContentFull 在真实实现里是「tab 内存优先」入口；这里用 override 模拟
        // tab 内存版本与磁盘版本不一致，断言 diff 基于 tab 版本计算
        ctx.addFile("a.md", content: "磁盘版本")
        ctx.fullContentOverrides["a.md"] = "TAB 内存版本"
        _ = try await WriteFileTool().execute(
            arguments: ["filename": .string("a.md"), "content": .string("NEW")],
            context: ctx
        )
        let h = hunks(of: ctx.confirmedWritePreviews.first)
        XCTAssertEqual(h.map(\.original), ["TAB 内存版本"],
                       "写前内容应取自 fileContentFull（tab 内存优先），而非磁盘 readFile")
    }

    // MARK: - 大小上限降级

    func testWriteFile_newContentTooLarge_degradesToTooLarge() async throws {
        let big = String(repeating: "x", count: WriteDiffPreviewBuilder.maxDiffBytes + 1)
        _ = try await WriteFileTool().execute(
            arguments: ["filename": .string("big.md"), "content": .string(big)],
            context: ctx
        )
        guard case .tooLarge = ctx.confirmedWritePreviews.first?.diff else {
            return XCTFail("写入内容超过上限应退化为 tooLarge（只显示 summary）")
        }
    }

    func testWriteFile_oldContentTooLarge_degradesToTooLarge() async throws {
        let big = String(repeating: "y", count: WriteDiffPreviewBuilder.maxDiffBytes + 1)
        ctx.addFile("huge.md", content: big)
        _ = try await WriteFileTool().execute(
            arguments: ["filename": .string("huge.md"), "content": .string("small")],
            context: ctx
        )
        guard case .tooLarge = ctx.confirmedWritePreviews.first?.diff else {
            return XCTFail("写前内容超过上限应退化为 tooLarge")
        }
    }

    // MARK: - 协议默认转发（只实现旧签名的 conformer 不破坏）

    /// 只实现 path/summary 旧签名的 ShellContext：preview 版本应经扩展默认实现转发过来。
    private final class LegacyShellContext: ShellContext {
        var received: [(path: String, summary: String)] = []
        func confirmCommandExecution(_ command: String, cwd: String?) async -> Bool { true }
        func isCommandApproved(_ key: String) -> Bool { false }
        func markCommandApproved(_ key: String) {}
        var allowedCommandPatterns: [String]? { nil }
        func setAllowedCommandPatterns(_ patterns: [String]?) {}
        func confirmFileWrite(_ path: String, summary: String) async -> Bool {
            received.append((path: path, summary: summary))
            return true
        }
    }

    func testPreviewConfirm_forwardsToLegacySignature() async {
        let shell = LegacyShellContext()
        let preview = FileWritePreview(path: "a.md", summary: "写入 a.md", diff: .hunks([]))
        let allowed = await shell.confirmFileWrite(preview)
        XCTAssertTrue(allowed)
        XCTAssertEqual(shell.received.first?.path, "a.md",
                       "只实现旧签名的 conformer 应收到转发（diff 被丢弃，语义不变）")
        XCTAssertEqual(shell.received.first?.summary, "写入 a.md")
    }
}
