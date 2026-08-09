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
}
