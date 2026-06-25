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
                ForEach(InlineEditAction.allCases) { action in
                    Button {
                        triggerAction(action)
                    } label: {
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
