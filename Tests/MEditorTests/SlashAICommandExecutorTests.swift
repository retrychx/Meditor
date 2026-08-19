import XCTest
@testable import MEditor

/// SlashAICommandExecutor 编排测试：document 级 chatBubble 命令（/summary）
/// 走 DocumentContextExcerpt 预算截取（不整篇硬塞聊天框）；/fix 无选中 tab 时
/// toast 提示而非静默返回。
@MainActor
final class SlashAICommandExecutorTests: XCTestCase {

    private var state: AppState!

    override func setUp() {
        super.setUp()
        state = AppState(fileService: MockFileService(), fileWatcher: MockFileWatcher())
    }

    override func tearDown() {
        state = nil
        super.tearDown()
    }

    /// 造 n 个段落，每段约 40 个估算 token。
    private func makeDoc(paragraphs n: Int) -> String {
        (1...n).map { "P\($0) " + String(repeating: "x", count: 160) }
            .joined(separator: "\n\n")
    }

    func testSummaryPrefillsExcerptNotWholeDocument() {
        // 300 段 × ~40 token ≈ 12000 token，远超默认预算（3000）
        let doc = makeDoc(paragraphs: 300)
        let summary = AISlashCommandRegistry.command(id: "summary")!

        SlashAICommandExecutor.run(
            command: summary, argument: "", documentText: doc,
            insertionLocation: 0, state: state, settings: AppSettings.shared)

        let prefilled = state.aiUI.pendingSelectionPrompt
        XCTAssertNotNil(prefilled)
        let docTokens = AIConversation.estimateTokens(doc)
        let prefilledTokens = AIConversation.estimateTokens(prefilled ?? "")
        XCTAssertLessThan(prefilledTokens, docTokens / 3, "应注入预算截取后的摘录而非整篇")
        XCTAssertTrue((prefilled ?? "").contains(DocumentContextExcerpt.ellipsis))
        XCTAssertFalse((prefilled ?? "").contains("P150 "), "被截掉的中段不应出现在预填内容里")
    }

    func testSummarySmallDocumentPassesThroughIntact() {
        let doc = "short intro\n\nshort outro"
        let summary = AISlashCommandRegistry.command(id: "summary")!

        SlashAICommandExecutor.run(
            command: summary, argument: "", documentText: doc,
            insertionLocation: 0, state: state, settings: AppSettings.shared)

        let prefilled = state.aiUI.pendingSelectionPrompt ?? ""
        XCTAssertTrue(prefilled.contains(doc), "预算内文档应完整进入 prompt")
    }

    func testFixWithoutSelectedTabShowsToast() {
        let fix = AISlashCommandRegistry.command(id: "fix")!

        SlashAICommandExecutor.run(
            command: fix, argument: "", documentText: "some content",
            insertionLocation: 0, state: state, settings: AppSettings.shared)

        XCTAssertEqual(state.toastMessage?.text, L("slash.noDocument"))
        XCTAssertFalse(state.diffReview.isStreaming, "无选中 tab 时不应进入写回流式")
    }
}
