import SwiftUI

struct PreviewPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            if state.previewContent.isEmpty {
                emptyState
            } else if state.previewLanguage == .markdown {
                MarkdownWebPreview(
                    content: state.previewContent,
                    scrollPercentage: state.editorScrollPercent,
                    onScrollChange: { percent in
                        state.previewScrollPercent = percent
                    }
                )
            } else {
                htmlPreview
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - HTML Preview

    private var htmlPreview: some View {
        WebPreviewView(htmlContent: state.previewContent)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "eye")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("Preview")
                .foregroundStyle(.tertiary)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
