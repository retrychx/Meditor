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

    // MARK: - 快照过期防护（写回时重定位合并）

    /// 触发后用户在无关区域编辑 → 接受 → 用户编辑保留且 AI 修改生效
    func test_acceptAll_afterUnrelatedUserEdit_rebasesOntoCurrentDocument() {
        let dr = DiffReviewState()
        let snapshot = "开头\n\n目标段落\n\n结尾"
        let modified = "开头\n\nAI 改写后的段落\n\n结尾"

        var currentDoc = snapshot   // 模拟文档：provider 每次读最新值
        var conflict = false
        var finalized: String? = nil

        dr.beginStreaming(original: snapshot, actionLabel: "改写")
        dr.currentContentProvider = { currentDoc }
        dr.onRebaseConflict = { conflict = true }
        dr.commitStreamWithModified(modified) { finalized = $0 }
        XCTAssertEqual(dr.pendingCount, 1)

        // AI 运行期间，用户在目标区域之前插入一段（无关编辑，索引发生偏移）
        currentDoc = "开头\n\n用户手写的补充\n\n目标段落\n\n结尾"

        dr.acceptAll()
        XCTAssertFalse(conflict, "无关区域编辑不应触发冲突")
        XCTAssertEqual(finalized, "开头\n\n用户手写的补充\n\nAI 改写后的段落\n\n结尾",
                       "合并应基于当前文档：用户编辑保留 + AI 替换生效")
        XCTAssertFalse(dr.isPresented)
    }

    /// 触发后用户改了目标区域 → 接受被拒绝、绝不覆盖，审阅界面保留
    func test_acceptAll_afterTargetAreaEdited_refusesAndDoesNotOverwrite() {
        let dr = DiffReviewState()
        let snapshot = "开头\n\n目标段落\n\n结尾"

        var currentDoc = snapshot
        var conflict = false
        var finalized: String? = nil

        dr.beginStreaming(original: snapshot, actionLabel: "改写")
        dr.currentContentProvider = { currentDoc }
        dr.onRebaseConflict = { conflict = true }
        dr.commitStreamWithModified("开头\n\nAI 改写\n\n结尾") { finalized = $0 }

        // AI 运行期间，用户改动了目标区域本身
        currentDoc = "开头\n\n用户改过的目标段落\n\n结尾"

        dr.acceptAll()
        XCTAssertTrue(conflict, "目标区域被改动必须触发冲突回调")
        XCTAssertNil(finalized, "校验失败绝不写回")
        XCTAssertTrue(dr.isPresented, "保留审阅界面，由用户放弃本次结果")

        // 用户放弃：dismiss 后状态清空
        dr.dismiss()
        XCTAssertFalse(dr.isPresented)
        XCTAssertTrue(dr.diffs.isEmpty)
    }

    /// 文档未被改动 + 注入 provider：走精确索引合并，行为与无 provider 一致
    func test_acceptAll_withProvider_unchangedDocument_mergesNormally() {
        let dr = DiffReviewState()
        let snapshot = "a\n\nb\n\nc"
        let modified = "a\n\nB\n\nc"

        var finalized: String? = nil
        dr.beginStreaming(original: snapshot, actionLabel: "改写")
        dr.currentContentProvider = { snapshot }
        dr.onRebaseConflict = { XCTFail("文档未改动不应触发冲突") }
        dr.commitStreamWithModified(modified) { finalized = $0 }

        dr.acceptAll()
        XCTAssertEqual(finalized, modified)
    }

    /// AI 把目标段落扩成多段（替换 + 纯新增），且用户在无关区域编辑过：
    /// 新增段落锚定到替换结果之后，整体落到当前文档的正确位置
    func test_acceptAll_additionRebasedAfterUserEdit() {
        let dr = DiffReviewState()
        let snapshot = "A\n\nB\n\nC"
        let modified = "A\n\nB1\n\nB2\n\nC"   // B → B1 替换 + B2 纯新增

        var currentDoc = snapshot
        var conflict = false
        var finalized: String? = nil

        dr.beginStreaming(original: snapshot, actionLabel: "扩写")
        dr.currentContentProvider = { currentDoc }
        dr.onRebaseConflict = { conflict = true }
        dr.commitStreamWithModified(modified) { finalized = $0 }

        // 用户在目标之前插入一段
        currentDoc = "A\n\n用户插入\n\nB\n\nC"

        dr.acceptAll()
        XCTAssertFalse(conflict)
        XCTAssertEqual(finalized, "A\n\n用户插入\n\nB1\n\nB2\n\nC")
    }
}
