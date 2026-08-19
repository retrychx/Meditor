import SwiftUI

/// 导出前检查清单（功能7）：导出 HTML/PDF 前对当前文档跑 DocumentDiagnostics，
/// 有问题时列出（严重度分级、点击跳转到对应行），底部「仍然导出 / 取消」。
/// 无问题则不弹（见 AppState.requestExport）。
@MainActor
struct ExportPreflightSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    let context: ExportPreflightContext

    /// 是否有模型能改文本修复的问题（missingImage 这类纯缺失资源不算）。
    private var hasAgentFixableIssue: Bool {
        context.issues.contains { $0.kind.isAgentFixable }
    }

    /// 与 /fix 执行器同一 32K 上限：超出后「让 Agent 修复」降级为提示。
    private var currentDocumentTooLarge: Bool {
        (state.selectedTab?.content.count ?? 0) > SlashAICommandExecutor.maxDocumentChars
    }

    var body: some View {
        let theme = state.themeStore.current
        VStack(spacing: 0) {
            header(theme)
            theme.separator.opacity(theme.isDark ? 0.28 : 0.18).frame(height: 1)
            resultsList(theme)
            theme.separator.opacity(theme.isDark ? 0.28 : 0.18).frame(height: 1)
            footer(theme)
        }
        .frame(width: 480, height: 380)
        .background(theme.chromeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Header

    private func header(_ theme: PreviewTheme) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checklist")
                .foregroundStyle(theme.craftSecondary)
                .font(.system(size: 13))
            Text(L("export.preflight.title"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.craftPrimary)

            Spacer()

            Text(L("export.preflight.summary", context.issues.count))
                .font(.system(size: 11))
                .foregroundStyle(theme.craftSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(theme.chromeBackground)
    }

    // MARK: - 问题列表

    private func resultsList(_ theme: PreviewTheme) -> some View {
        List {
            ForEach(context.issues) { issue in
                HStack(spacing: 8) {
                    Image(systemName: issue.severity == .error
                          ? "exclamationmark.triangle.fill"
                          : "exclamationmark.circle")
                        .foregroundStyle(issue.severity == .error
                                         ? Color.red.opacity(0.8)
                                         : Color.orange.opacity(0.8))
                        .font(.system(size: 11))
                        .frame(width: 14)

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
                // 点击跳转到对应行；不关闭 sheet，用户修完还能回来继续导出
                .onTapGesture {
                    state.requestEditorScroll(to: issue.line, select: true)
                }
                .help(L("export.preflight.hint"))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.chromeBackground)
    }

    // MARK: - Footer

    private func footer(_ theme: PreviewTheme) -> some View {
        HStack(spacing: 10) {
            Text(L("export.preflight.hint"))
                .font(.system(size: 11))
                .foregroundStyle(theme.craftSecondary)

            Spacer()

            if currentDocumentTooLarge {
                // 超 /fix 执行器的整篇上限：按钮降级为提示
                Text(L("diagnostics.fix.tooLarge"))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.craftSecondary)
            } else {
                Button(L("diagnostics.fix.agent")) { startAgentFix() }
                    .disabled(!hasAgentFixableIssue)
            }

            Button(L("common.cancel")) { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button(L("export.preflight.exportAnyway")) {
                dismiss()
                state.proceedWithExport(context.format, suggestedName: context.suggestedName)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(theme.chromeBackground)
    }

    // MARK: - Actions

    /// 「让 Agent 修复」：走 /fix 同款链路。写回确认后用新内容重检——干净则
    /// 直接续跑导出，否则带着新的问题列表回到预检（用户可继续导出）。
    private func startAgentFix() {
        guard let command = AISlashCommandRegistry.command(id: "fix"),
              let tab = state.selectedTab else { return }
        let format = context.format
        let suggestedName = context.suggestedName
        let fileURL = tab.url
        let content = tab.content
        dismiss()
        SlashAICommandExecutor.run(
            command: command,
            argument: "",
            documentText: content,
            insertionLocation: 0,
            state: state,
            settings: AppSettings.shared,
            onWriteBack: { merged in
                // merged 即写回的整文；不读 tab.content（编辑器写回是异步应用）
                let remaining = DocumentDiagnostics.issues(in: merged, fileURL: fileURL) {
                    FileManager.default.fileExists(atPath: $0.path)
                }
                if remaining.isEmpty {
                    state.proceedWithExport(format, suggestedName: suggestedName)
                } else {
                    state.exportPreflight = ExportPreflightContext(
                        format: format, suggestedName: suggestedName, issues: remaining)
                }
            }
        )
    }
}
