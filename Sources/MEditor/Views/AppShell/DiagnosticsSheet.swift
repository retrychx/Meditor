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

    /// 按文件分组（相对路径排序），组内保持行号顺序（scan 已排序）。
    private var groups: [(path: String, issues: [DocumentIssue])] {
        let grouped = Dictionary(grouping: issues) { relativePath($0.fileURL) }
        return grouped.keys.sorted().map { ($0, grouped[$0]!) }
    }

    var body: some View {
        let theme = state.themeStore.current
        VStack(spacing: 0) {
            header(theme)
            theme.separator.opacity(theme.isDark ? 0.28 : 0.18).frame(height: 1)
            if issues.isEmpty {
                emptyState
            } else {
                resultsList(theme)
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
            Image(systemName: icon(for: issue.kind))
                .foregroundStyle(theme.craftSecondary)
                .font(.system(size: 11))
                .frame(width: 14)

            Text(message(for: issue.kind))
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

    // MARK: - Actions

    private func startScan() {
        scanTask?.cancel()
        guard let root = state.rootURL else { return }
        isScanning = true
        issues = []
        scannedFiles = 0
        totalFiles = 0
        scanTask = Task {
            let result = await DocumentDiagnostics.scan(rootURL: root) { done, total in
                Task { @MainActor in
                    scannedFiles = done
                    totalFiles = total
                }
            }
            guard !Task.isCancelled else { return }
            issues = result
            isScanning = false
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

    private func icon(for kind: DocumentIssue.Kind) -> String {
        switch kind {
        case .deadLink:         return "link"
        case .missingImage:     return "photo"
        case .duplicateHeading: return "doc.on.doc"
        case .headingLevelSkip: return "list.number"
        }
    }

    private func message(for kind: DocumentIssue.Kind) -> String {
        switch kind {
        case .deadLink(let target):
            return L("diagnostics.deadLink", target)
        case .missingImage(let target):
            return L("diagnostics.missingImage", target)
        case .duplicateHeading(let text):
            return L("diagnostics.duplicateHeading", text)
        case .headingLevelSkip(let from, let to):
            return L("diagnostics.headingLevelSkip", from, to)
        }
    }
}
