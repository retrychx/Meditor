import SwiftUI

/// Floating action strip shown at the editor's bottom when text is selected.
/// Tapping an action triggers AI processing and morphs the content area into
/// an inline split diff view — no sheet, no modal.
struct InlineEditBar: View {
    @Environment(AppState.self)    private var state
    @Environment(AppSettings.self) private var settings

    let selectedText: String

    @State private var isLoading:    Bool   = false
    @State private var loadingLabel: String = ""

    private let agent = InlineEditAgent()

    var body: some View {
        HStack(spacing: 2) {
            if isLoading {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("AI \(loadingLabel)中…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button {
                        state.diffReview.dismiss()
                        isLoading    = false
                        loadingLabel = ""
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
                    actionButton(action)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    // MARK: - Action button

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

    // MARK: - Trigger

    private func triggerAction(_ action: InlineEditAction) {
        guard !selectedText.isEmpty else { return }

        isLoading    = true
        loadingLabel = action.rawValue

        // Save editor selection range before focus is lost
        let savedRange = state.editorSelectedRange
        state.pendingReplaceRange = savedRange

        // Full document as context for diff review
        let fullContent = state.selectedTab?.content ?? selectedText

        // Helper: splice `replacement` into `fullContent` at `savedRange`
        func spliced(_ replacement: String) -> String {
            guard let swiftRange = Range(savedRange, in: fullContent) else {
                // Fallback: string search
                return fullContent.replacingOccurrences(of: selectedText, with: replacement, options: .literal)
            }
            return fullContent.replacingCharacters(in: swiftRange, with: replacement)
        }

        // Enter diff mode immediately
        state.diffReview.beginStreaming(original: fullContent, actionLabel: action.rawValue)

        var accumulated = ""
        let task = agent.process(
            text: selectedText,
            action: action,
            settings: settings,
            pluginManager: state.pluginManager,
            onChunk: { chunk in
                accumulated += chunk
                state.diffReview.streamedContent = spliced(accumulated)
            },
            onComplete: { _, error in
                isLoading    = false
                loadingLabel = ""

                if let error {
                    state.diffReview.dismiss()
                    state.showToast(error.localizedDescription, icon: "exclamationmark.triangle")
                    return
                }

                let modified = spliced(accumulated)
                state.diffReview.commitStreamWithModified(modified) { merged in
                    if let tab = state.selectedTab {
                        tab.content = merged
                        tab.contentRevision &+= 1   // 通知编辑器刷新视图
                        state.scheduleDebounceSave()
                    }
                }
            }
        )
        state.diffReview.activeStreamTask = task
    }
}
