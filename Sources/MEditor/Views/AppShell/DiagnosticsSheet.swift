import SwiftUI

/// 文档诊断面板：菜单「工具 → 文档诊断…」触发。
///
/// 实现参照 GlobalSearchSheet：AppState.showingDiagnostics 驱动的 sheet。
/// 扫描走 DocumentDiagnostics.scan（后台线程，随面板关闭/取消按钮中断），
/// 结果按文件分组；点击行跳转：openFile 后 requestEditorScroll(select: true)。
@MainActor
struct DiagnosticsSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var issues: [DocumentIssue] = []
    @State private var isScanning = false
    @State private var scannedFiles = 0
    @State private var totalFiles = 0
    @State private var scanTask: Task<Void, Never>?
    /// Agent 修复写回后的前后对比横幅（修复 X 条、剩 Y 条）；手动重扫时清除。
    @State private var fixReport: (fixed: Int, remaining: Int)? = nil

    /// 按文件分组（相对路径排序），组内保持行号顺序（scan 已排序）。
    private var groups: [(path: String, issues: [DocumentIssue])] {
        let grouped = Dictionary(grouping: issues) { relativePath($0.fileURL) }
        return grouped.keys.sorted().map { ($0, grouped[$0]!) }
    }

    /// 当前文档内模型可修复的问题（missingImage 是纯缺失资源，模型修不了，不计入）。
    /// /fix 链路只作用于当前文档，按钮可用性也按当前文档口径。
    private var fixableIssuesInCurrentDocument: [DocumentIssue] {
        guard let tab = state.selectedTab else { return [] }
        let tabPath = tab.url.standardizedFileURL.path
        return issues.filter {
            $0.fileURL.standardizedFileURL.path == tabPath && $0.kind.isAgentFixable
        }
    }

    /// 与 /fix 执行器同一 32K 上限：超出后「输出完整文档」不可靠，按钮降级为提示。
    private var currentDocumentTooLarge: Bool {
        (state.selectedTab?.content.count ?? 0) > SlashAICommandExecutor.maxDocumentChars
    }

    var body: some View {
        let theme = state.themeStore.current
        VStack(spacing: 0) {
            header(theme)
            theme.separator.opacity(theme.isDark ? 0.28 : 0.18).frame(height: 1)
            if let fixReport {
                fixReportBanner(fixReport, theme)
                theme.separator.opacity(theme.isDark ? 0.28 : 0.18).frame(height: 1)
            }
            if issues.isEmpty {
                emptyState
            } else {
                resultsList(theme)
                theme.separator.opacity(theme.isDark ? 0.28 : 0.18).frame(height: 1)
                footer(theme)
            }
        }
        .frame(width: 560, height: 420)
        .background(theme.chromeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear { startScan() }
        .onDisappear { scanTask?.cancel() }
    }

    // MARK: - Header

    private func header(_ theme: PreviewTheme) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "stethoscope")
                .foregroundStyle(theme.craftSecondary)
                .font(.system(size: 13))
            Text(L("diagnostics.title"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.craftPrimary)

            Spacer()

            if isScanning {
                ProgressView()
                    .controlSize(.small)
                Text(L("diagnostics.scanning", scannedFiles, totalFiles))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.craftSecondary)
            } else {
                Text(L("diagnostics.summary", issues.count, groups.count))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.craftSecondary)
                Button(L("diagnostics.rescan")) { startScan() }
                    .controlSize(.small)
            }

            Button(isScanning ? L("common.cancel") : L("diagnostics.close")) {
                scanTask?.cancel()
                dismiss()
            }
            .controlSize(.small)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(theme.chromeBackground)
    }

    // MARK: - Results

    private func resultsList(_ theme: PreviewTheme) -> some View {
        // List 自带懒加载，大工作区结果多也不卡
        List {
            ForEach(groups, id: \.path) { group in
                Section {
                    ForEach(group.issues) { issue in
                        resultRow(issue, theme)
                    }
                } header: {
                    Text(group.path)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.craftSecondary)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.chromeBackground)
    }

    private func resultRow(_ issue: DocumentIssue, _ theme: PreviewTheme) -> some View {
        HStack(spacing: 8) {
            Image(systemName: issue.kind.icon)
                .foregroundStyle(theme.craftSecondary)
                .font(.system(size: 11))
                .frame(width: 14)

            Text(issue.kind.message)
                .font(.system(size: 13))
                .foregroundStyle(theme.craftPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text(":\(issue.line + 1)")   // 展示用 1-based 行号
                .font(.system(size: 10))
                .foregroundStyle(theme.craftSecondary.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(theme.chromeBackground)
        .contentShape(Rectangle())
        .onTapGesture { jump(to: issue) }
    }

    private var emptyState: some View {
        let theme = state.themeStore.current
        return VStack(spacing: 8) {
            Image(systemName: isScanning ? "doc.text.magnifyingglass" : "checkmark.circle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            if isScanning {
                Text(L("diagnostics.scanning", scannedFiles, totalFiles))
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            } else {
                Text(L("diagnostics.noIssues"))
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.chromeBackground)
    }

    // MARK: - Fix report banner / Footer

    /// Agent 修复写回后的前后对比：修复几条、剩余几条（工作区口径，重扫后生成）。
    private func fixReportBanner(_ report: (fixed: Int, remaining: Int), _ theme: PreviewTheme) -> some View {
        HStack(spacing: 8) {
            Image(systemName: report.remaining == 0 ? "checkmark.circle.fill" : "wand.and.stars")
                .foregroundStyle(report.remaining == 0 ? Color.green.opacity(0.8) : theme.craftSecondary)
                .font(.system(size: 12))
            Text(L("diagnostics.fix.report", report.fixed, report.remaining))
                .font(.system(size: 12))
                .foregroundStyle(theme.craftPrimary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(theme.chromeBackground)
    }

    private func footer(_ theme: PreviewTheme) -> some View {
        HStack(spacing: 10) {
            if currentDocumentTooLarge {
                // 超 /fix 执行器的整篇上限：按钮降级为提示
                Text(L("diagnostics.fix.tooLarge"))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.craftSecondary)
            } else {
                Text(L("diagnostics.fix.scope", fixableIssuesInCurrentDocument.count))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.craftSecondary)
            }

            Spacer()

            if !currentDocumentTooLarge {
                Button(L("diagnostics.fix.agent")) { startAgentFix() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(isScanning || fixableIssuesInCurrentDocument.isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(theme.chromeBackground)
    }

    // MARK: - Actions

    /// 「让 Agent 修复」：走 /fix 同款链路（诊断 → prompt → 流式 diff → 确认写回）。
    /// diff 审阅是窗口内 overlay，本 sheet 必须让位；写回确认后重开面板自动重扫。
    private func startAgentFix() {
        guard let command = AISlashCommandRegistry.command(id: "fix"),
              let tab = state.selectedTab else { return }
        let baseline = issues.count
        let content = tab.content
        dismiss()
        SlashAICommandExecutor.run(
            command: command,
            argument: "",
            documentText: content,
            insertionLocation: 0,
            state: state,
            settings: AppSettings.shared,
            onWriteBack: { _ in
                // 用户在 diff 审阅里确认写回才会走到这：记录基线并重开面板，
                // onAppear 自动重扫，扫描完成时生成前后对比横幅
                state.diagnosticsFixBaseline = baseline
                state.showingDiagnostics = true
            }
        )
    }

    private func startScan() {
        scanTask?.cancel()
        guard let root = state.rootURL else { return }
        isScanning = true
        issues = []
        fixReport = nil
        scannedFiles = 0
        totalFiles = 0
        scanTask = Task {
            var result = await DocumentDiagnostics.scan(rootURL: root) { done, total in
                Task { @MainActor in
                    scannedFiles = done
                    totalFiles = total
                }
            }
            guard !Task.isCancelled else { return }
            // 当前 tab 可能有未落盘的编辑（AI 写回走 2s 防抖保存）：该文件的
            // 诊断改用内存内容重算，否则修复后立刻重扫会读到磁盘旧内容
            if let tab = state.selectedTab {
                let tabPath = tab.url.standardizedFileURL.path
                let rootPath = root.standardizedFileURL.path
                if tabPath.hasPrefix(rootPath + "/") {
                    let live = DocumentDiagnostics.issues(in: tab.content, fileURL: tab.url) {
                        FileManager.default.fileExists(atPath: $0.path)
                    }
                    result.removeAll { $0.fileURL.standardizedFileURL.path == tabPath }
                    result.append(contentsOf: live)
                    result.sort {
                        $0.fileURL.path != $1.fileURL.path
                            ? $0.fileURL.path < $1.fileURL.path
                            : $0.line < $1.line
                    }
                }
            }
            issues = result
            isScanning = false
            // Agent 修复闭环：有基线说明本次重扫由修复写回触发，生成前后对比
            if let baseline = state.diagnosticsFixBaseline {
                fixReport = (fixed: max(0, baseline - result.count), remaining: result.count)
                state.diagnosticsFixBaseline = nil
            }
        }
    }

    private func jump(to issue: DocumentIssue) {
        state.openFile(FileItem(url: issue.fileURL, isDirectory: false))
        // 0-based 行号；select: true → 光标落行 + Find 指示器闪烁高亮
        state.requestEditorScroll(to: issue.line, select: true)
        dismiss()
    }

    // MARK: - Presentation helpers

    private func relativePath(_ url: URL) -> String {
        guard let root = state.rootURL else { return url.lastPathComponent }
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return path
    }
}
