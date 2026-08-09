import Foundation
import AppKit

#if DEBUG
/// DEBUG 专用演示流：不依赖真实 AI，脚本化走一遍
/// 「流式落笔 → 审阅 → 微调入口 → 接受 → 改哪亮哪」全链路，
/// 供界面走查（launch argument `-debugDemoInlineFlow YES` 触发）。
@MainActor
enum DebugDemoInlineFlow {

    /// 防重入：reopen/二次 onAppear 时只跑一次（否则两个演示任务互相打断）。
    private static var didRun = false

    /// stdout 重定向到文件时是块缓冲，print 可能永不落盘；stderr 无缓冲。
    private static func dlog(_ s: String) {
        FileHandle.standardError.write(Data((s + "\n").utf8))
    }

    static func runIfRequested(state: AppState) {
        dlog("DEMO: runIfRequested, didRun=\(didRun), flag=\(UserDefaults.standard.bool(forKey: "debugDemoInlineFlow"))")
        guard !didRun, UserDefaults.standard.bool(forKey: "debugDemoInlineFlow") else { return }
        didRun = true
        Task { await run(state: state) }
    }

    private static func run(state: AppState) async {
        dlog("DEMO: run start")
        try? await Task.sleep(for: .seconds(2))
        dlog("DEMO: woke, tab=\(state.selectedTab?.name ?? "nil")")
        // 演示窗口置顶并居中，避免被其他全屏窗口遮挡（仅 DEBUG）
        if let w = NSApp.windows.first {
            w.level = .floating
            w.center()
        }
        // 无会话恢复时（裸二进制场景）：自建演示文档打开
        if state.selectedTab == nil {
            let demoURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("meditor-demo-inline.md")
            let demo = """
            # MEditor 代码质量评审与功能路线图

            评审日期：2026-08-05 项目版本：初版（MarkEdit → MEditor 重命名后）

            ## 项目概览

            本文档用于演示「流式落笔 → 审阅 → 连续微调 → 改哪亮哪」链路。

            - 流式生成实时流入对比视图
            - 微调输入「再短一点」持续打磨
            - 接受后预览自动定位并脉冲高亮
            """
            try? demo.write(to: demoURL, atomically: true, encoding: .utf8)
            // 与 onOpenURL 一致：先开父目录（否则欢迎页不会因 rootURL 为空而退出）
            state.openFolder(demoURL.deletingLastPathComponent())
            state.openFile(FileItem(url: demoURL, isDirectory: false))
            // 文件内容异步加载：轮询等待非空（最长 6s）
            for _ in 0..<30 where state.selectedTab?.content.isEmpty != false {
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        guard let tab = state.selectedTab else { return }
        let full = tab.content

        // 圈选目标：文档 H1 标题（code-review 文档的第一个标题）
        guard let h1 = full.components(separatedBy: "\n").first(where: { $0.hasPrefix("# ") }) else { return }
        let title = String(h1.dropFirst(2))
        guard let range = SourceTextMapper.sourceRange(ofPlainSelection: title, in: full) else { return }

        // 1) 流式落笔：逐字流入 diff 右栏（放慢节奏便于观察）
        dlog("DEMO: beginStreaming")
        state.diffReview.beginStreaming(original: full, actionLabel: "精简")
        let fakeResult = "MEditor 评审与路线图"
        var acc = ""
        for ch in fakeResult {
            acc.append(ch)
            state.diffReview.streamedContent = full.replacingCharacters(in: range, with: acc)
            try? await Task.sleep(for: .milliseconds(120))
            dlog("DEMO: char \(acc.count)")
        }
        dlog("DEMO: loop done")

        // 2) 进入审阅（微调输入框应出现在 DiffModeBar）
        try? await Task.sleep(for: .milliseconds(600))
        state.diffReview.lastGeneratedText = fakeResult
        let modified = full.replacingCharacters(in: range, with: fakeResult)
        dlog("DEMO: commit, diffs 待确认")
        state.diffReview.commitStreamWithModified(modified) { merged in
            dlog("DEMO: finalize 回调, merged.count=\(merged.count)")
            state.showToast("演示：写回 \(merged.count) 字符", icon: "checkmark.circle")
            tab.content = merged
            tab.contentRevision &+= 1
            state.scheduleDebounceSave()
            state.flashPreviewChange(sourceRange: range, in: merged)
        }
        dlog("DEMO: commit 后 diffs=\(state.diffReview.diffs.count) pending=\(state.diffReview.pendingCount)")

        // 3) 接受全部 → 写回 → 预览闪示改动位置（改哪亮哪）
        try? await Task.sleep(for: .seconds(2.5))
        dlog("DEMO: acceptAll 前 diffs=\(state.diffReview.diffs.count) streaming=\(state.diffReview.isStreaming) onFinalize=\(state.diffReview.onFinalize != nil)")
        state.diffReview.acceptAll()
        dlog("DEMO: acceptAll 完成")
    }
}
#endif
