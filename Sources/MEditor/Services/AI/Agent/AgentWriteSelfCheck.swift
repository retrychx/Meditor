import Foundation
import Observation

/// Agent 写后自检：AI 是文档的唯一作者，写工具内容生效后自动跑一遍本地诊断。
///
/// 挂点在最下游统一写入点（AppStateDocumentAdapter 的 writeDocument/patchDocument/
/// notifyFileWritten——内容已应用到 tab / 落盘之后），不在工具调用点：
/// diff 预览确认、回滚等链路最终都汇入这几个点，只触发一次不重复。
/// 用户手动编辑不经过这些路径，既有诊断行为（诊断面板手动扫描）不变。
///
/// 防打扰：同一静默窗口内的连续写入按文件合并，只在最后一改后跑一次；
/// Agent run 仍在进行（shouldDefer）时到点顺延一个窗口，避免拿中途态误报。
@MainActor
@Observable
final class AgentWriteSelfCheck {

    /// 一次防抖合并后的自检结果。
    /// fixable = 文本层面可确定性修复（进「一键修复」列表）；
    /// reportOnly = 结果可能受外部因素影响（死链目标可能稍后才创建、缺图是
    /// 资源缺失），只报告不自动改。
    struct Report: Equatable {
        var fileURLs: [URL]
        var fixable: [DocumentIssue]
        var reportOnly: [DocumentIssue]
        var totalCount: Int { fixable.count + reportOnly.count }
        /// 一键修复的目标文档（第一个有可修问题的文件；多文件报告逐个修，从它开始）
        var fixTarget: URL? { fixable.first?.fileURL }
    }

    /// 有未处理问题时报非 nil，AI 面板据此显示报告条。最新一次检查结果整体
    /// 替换旧值：最后一改后复查干净则回到 nil（静默），不打扰。
    private(set) var pendingReport: Report?

    /// 合并窗口内各文件的最新内容（key = 标准化路径）。同文档连写只留最新一份。
    @ObservationIgnored private var pendingWrites: [String: (url: URL, content: String)] = [:]
    @ObservationIgnored private var debounceTask: Task<Void, Never>?

    /// 静默窗口时长（默认 1.5s；测试注入短间隔）。
    let debounceInterval: TimeInterval
    /// 到点时 Agent run 是否仍在进行（是则顺延一个窗口，只在 run 收尾后报告）。
    /// 由 AppState 接线到 aiConversation.isResponding；测试可注入。
    @ObservationIgnored var shouldDefer: () -> Bool = { false }
    /// 链接/图片目标存在性检查（测试注入，避免碰真实磁盘）。
    @ObservationIgnored var fileExists: (URL) -> Bool = {
        FileManager.default.fileExists(atPath: $0.path)
    }
    /// 每次实际执行检查后回调（参数为本次检查的文件数）——防抖合并的测试观测点；
    /// 发现新问题时也会回调 onReport。
    @ObservationIgnored var onDidRunChecks: ((Int) -> Void)?
    /// 检查发现新问题时回调（AppState 接线 toast 通知）；复查干净不回调（静默）。
    @ObservationIgnored var onReport: ((Report) -> Void)?

    init(debounceInterval: TimeInterval = 1.5) {
        self.debounceInterval = debounceInterval
    }

    deinit { debounceTask?.cancel() }

    /// Agent 写入生效后调用（可多次；同文件只保留最新内容）。
    func notifyAgentWrite(url: URL, content: String) {
        pendingWrites[url.standardizedFileURL.path] = (url, content)
        schedule()
    }

    /// 用户关掉报告条（「忽略」）。
    func dismissReport() { pendingReport = nil }

    // MARK: - 内部

    private func schedule() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.debounceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            // run 还在进行（Agent 可能还要继续改）：顺延一个窗口，不拿中途态误报
            if self.shouldDefer() { self.schedule(); return }
            self.runPendingChecks()
        }
    }

    /// 执行一次合并检查（防抖触发；测试也可直接同步调用）。
    func runPendingChecks() {
        let batch = pendingWrites
        pendingWrites.removeAll()
        guard !batch.isEmpty else { return }

        var fixable: [DocumentIssue] = []
        var reportOnly: [DocumentIssue] = []
        for entry in batch.values {
            let issues = DocumentDiagnostics.issues(
                in: entry.content, fileURL: entry.url, fileExists: fileExists)
            for issue in issues {
                if issue.kind.isDeterministicFix {
                    fixable.append(issue)
                } else {
                    reportOnly.append(issue)
                }
            }
        }
        onDidRunChecks?(batch.count)

        // 排序与诊断面板一致（路径 + 行号），多文件报告按路径聚合
        let order: (DocumentIssue, DocumentIssue) -> Bool = {
            $0.fileURL.path != $1.fileURL.path
                ? $0.fileURL.path < $1.fileURL.path
                : $0.line < $1.line
        }
        fixable.sort(by: order)
        reportOnly.sort(by: order)

        guard fixable.count + reportOnly.count > 0 else {
            pendingReport = nil   // 复查干净：静默，不打扰
            return
        }
        let report = Report(
            fileURLs: batch.values.map(\.url).sorted { $0.path < $1.path },
            fixable: fixable,
            reportOnly: reportOnly)
        pendingReport = report
        onReport?(report)
    }
}
