import SwiftUI

/// Floating action strip shown at the bottom of the preview when text is selected.
/// Triggers AI inline edit then opens the diff-review overlay instead of a sheet.
struct PreviewInlineEditBar: View {
    @Environment(AppState.self)    private var state
    @Environment(AppSettings.self) private var settings

    let selectedText: String
    var onDismiss: (() -> Void)? = nil

    @State private var isLoading      = false
    @State private var loadingAction:  InlineEditAction? = nil
    @State private var streamTask:     Task<Void, Never>? = nil

    private let agent = InlineEditAgent()

    var body: some View {
        HStack(spacing: 2) {
            if isLoading {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("AI \(loadingAction?.rawValue ?? "")中…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button {
                        streamTask?.cancel()
                        isLoading     = false
                        loadingAction = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            } else {
                // 内容感知：按选中内容类型只显示最相关的 3-4 个操作（与编辑器内联栏一致）
                ForEach(contextualActions) { action in
                    actionButton(action)
                }

                // 问 AI 入口（预览栏此前缺失）
                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, 4)
                askAIButton
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .padding(.bottom, 12)
        .onDisappear { streamTask?.cancel() }
    }

    // MARK: - 内容感知动作列表

    /// 根据选中内容类型返回最相关的 AI 操作，最多 4 个（与 InlineEditBar 一致）。
    private var contextualActions: [InlineEditAction] {
        let t = selectedText.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("```") || t.hasPrefix("    ") {
            return [.explainCode, .addComments, .condense]
        }
        if t.hasPrefix("#") {
            return [.expandSection, .rewrite]
        }
        let lines = t.components(separatedBy: "\n").filter { !$0.isEmpty }
        let isListLike = lines.count >= 2 && lines.prefix(3).allSatisfy {
            $0.hasPrefix("- ") || $0.hasPrefix("* ") || $0.hasPrefix("+ ") ||
            $0.range(of: #"^\d+\. "#, options: .regularExpression) != nil
        }
        if isListLike {
            return [.organizeList, .expand, .condense]
        }
        return [.rewrite, .expand, .condense, .translate]
    }

    private func actionButton(_ action: InlineEditAction) -> some View {
        Button { triggerAction(action) } label: {
            HStack(spacing: 4) {
                Image(systemName: action.icon)
                    .font(.system(size: 10, weight: .medium))
                Text(action.rawValue)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.05), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(action.rawValue)
    }

    /// 把选中文本带入 AI 面板，开启对话。
    private var askAIButton: some View {
        Button {
            guard !selectedText.isEmpty else { return }
            let quoted = selectedText.count <= 200
                ? "> \(selectedText)\n\n"
                : "> \(String(selectedText.prefix(200)))…\n\n"
            state.openAssistantWithSelection(quoted)
            onDismiss?()
        } label: {
            HStack(spacing: 4) {
                AIAssistantOrb(size: 12)
                Text(L("ai.askAI"))
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(AIBrand.blue)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(AIBrand.blue.opacity(0.09), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(L("ai.askAIHint"))
    }

    // MARK: - Action

    private func triggerAction(_ action: InlineEditAction) {
        isLoading     = true
        loadingAction = action
        var result    = ""

        streamTask = agent.process(
            text: selectedText,
            action: action,
            settings: settings,
            pluginManager: state.pluginManager,
            onChunk: { chunk in
                result += chunk
            },
            onComplete: { [self] _, error in
                isLoading     = false
                loadingAction = nil
                streamTask    = nil

                guard error == nil, !result.isEmpty else {
                        if let err = error {
                            state.showToast(err.localizedDescription, icon: "exclamationmark.triangle")
                        }
                        return
                    }

                let fullContent = state.selectedTab?.content ?? selectedText
                // Replace selected text with AI result in full document
                let modified: String
                if let range = fullContent.range(of: selectedText, options: .literal) {
                    modified = fullContent.replacingCharacters(in: range, with: result)
                } else {
                    modified = result
                }

                state.diffReview.present(
                    original: fullContent,
                    modified: modified,
                    mode: .markdownVsMarkdown,
                    selectedOriginal: selectedText,
                    selectedModified: result,
                    onFinalize: { merged in
                        if let tab = state.selectedTab {
                            tab.content = merged
                            tab.contentRevision &+= 1   // 通知编辑器刷新视图
                            state.scheduleDebounceSave()
                        }
                    }
                )
                onDismiss?()
            }
        )
    }
}
