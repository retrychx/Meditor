import SwiftUI

struct PreviewPanel: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ZStack {
            // Markdown preview is always mounted so its WKWebView, marked.js,
            // highlight.js and mermaid stay warm. Cold-start latency is paid
            // once at app launch, not at first file open.
            MarkdownWebPreview(
                content: showsMarkdown ? state.previewContent : "",
                theme: state.themeStore.current,
                // Editor → preview: scroll to line reported by editor.
                scrollToLine: showsMarkdown ? state.editorVisibleLine : -1,
                // Preview → editor: report visible top line.
                onVisibleLineChange: { line in
                    state.previewVisibleLine = line
                },
                exporter: state.previewExporter,
                sourceURL: showsMarkdown ? state.selectedTab?.url : nil
            )
            .opacity(showsMarkdown ? 1 : 0)
            .allowsHitTesting(showsMarkdown)

            // HTML preview is also always mounted for the same reason.
            // Driven by a file URL so WKWebView can mmap directly, bypassing
            // IPC string transfer and proceeding in parallel with the
            // Swift-side file read.
            WebPreviewView(
                fileURL: showsHTML ? state.previewHTMLFileURL : nil,
                reloadToken: state.previewReloadToken
            )
            .opacity(showsHTML ? 1 : 0)
            .allowsHitTesting(showsHTML)

            // Empty-state overlay; both webviews sit invisibly underneath.
            if state.previewMode == .empty {
                emptyState
                    .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var showsMarkdown: Bool { state.previewMode == .markdown }
    private var showsHTML: Bool { state.previewMode == .html }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "eye")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Preview")
                .foregroundStyle(.tertiary)
                .font(.system(size: 12))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
