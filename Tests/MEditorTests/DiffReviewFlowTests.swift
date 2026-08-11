import XCTest
@testable import MEditor

/// DiffReviewState 流式状态机：beginStreaming → commitStreamWithModified → acceptAll
/// 必须产出应用了替换的合并结果并回调 onFinalize。
@MainActor
final class DiffReviewFlowTests: XCTestCase {

    func test_streamCommitAcceptAll_producesMergedWrite() {
        let dr = DiffReviewState()
        let original = "# 旧标题\n\n第一段\n\n第二段"
        let modified = "# 新标题\n\n第一段\n\n第二段"

        dr.beginStreaming(original: original, actionLabel: "精简")
        XCTAssertTrue(dr.isStreaming)
        XCTAssertTrue(dr.isPresented)

        var finalized: String? = nil
        dr.commitStreamWithModified(modified) { merged in
            finalized = merged
        }
        XCTAssertFalse(dr.isStreaming)
        XCTAssertEqual(dr.pendingCount, 1, "标题段应有 1 处替换待处理")

        dr.acceptAll()
        XCTAssertEqual(finalized, modified, "acceptAll 后 onFinalize 应收到应用了替换的合并内容")
        XCTAssertFalse(dr.isPresented, "finalize 后应自动关闭")
    }

    func test_skipAll_producesNoCallback() {
        let dr = DiffReviewState()
        var called = false
        dr.beginStreaming(original: "a\n\nb", actionLabel: "改写")
        dr.commitStreamWithModified("a\n\nc") { _ in called = true }
        dr.skipAll()
        XCTAssertFalse(called)
        XCTAssertFalse(dr.isPresented)
    }

    // MARK: - 回调失效防护（generation token）

    func test_dismiss_thenLateCallbacks_doNotReviveState() {
        let dr = DiffReviewState()
        dr.beginStreaming(original: "原文", actionLabel: "改写")
        let gen = dr.streamGeneration

        dr.dismiss()

        // dismiss 后迟到的 onChunk：不得写回 streamedContent
        dr.writeStreamedContent("迟到的 chunk", generation: gen)
        XCTAssertEqual(dr.streamedContent, "")

        // dismiss 后迟到的 onComplete：不得复活 diffs，也不得触发 onFinalize
        var finalized = false
        let committed = dr.commitStreamWithModified("迟到的修改", generation: gen) { _ in finalized = true }
        XCTAssertFalse(committed)
        XCTAssertTrue(dr.diffs.isEmpty)
        XCTAssertFalse(finalized)
        XCTAssertFalse(dr.isStreaming)
        XCTAssertFalse(dr.isPresented)
    }

    func test_currentGeneration_writesStillApply() {
        let dr = DiffReviewState()
        dr.beginStreaming(original: "a\n\nb", actionLabel: "改写")
        let gen = dr.streamGeneration

        dr.writeStreamedContent("a\n\nc", generation: gen)
        XCTAssertEqual(dr.streamedContent, "a\n\nc")

        let committed = dr.commitStreamWithModified("a\n\nc", generation: gen) { _ in }
        XCTAssertTrue(committed)
        XCTAssertEqual(dr.pendingCount, 1)
    }

    func test_newStream_invalidatesPreviousGeneration() {
        let dr = DiffReviewState()
        dr.beginStreaming(original: "旧", actionLabel: "改写")
        let oldGen = dr.streamGeneration

        // 新一轮流式开始：旧 run 的在途回调 token 失效
        dr.beginStreaming(original: "新", actionLabel: "扩写")
        dr.writeStreamedContent("旧 run 迟到的 chunk", generation: oldGen)
        XCTAssertEqual(dr.streamedContent, "")

        let committed = dr.commitStreamWithModified("旧 run 迟到的修改", generation: oldGen) { _ in }
        XCTAssertFalse(committed)
        XCTAssertTrue(dr.diffs.isEmpty)
        XCTAssertTrue(dr.isStreaming, "新一轮流式不应被旧回调打断")
    }
}
