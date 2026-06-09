import SwiftUI
import Combine

struct PreviewPanel: View {
    @Environment(AppState.self) private var state
    @State private var fontSize: Int = AppSettings.shared.previewFontSize
    @State private var tocItems: [TOCItem] = []
    @State private var activeTOCIndex: Int = -1
    /// The line number to scroll the preview to. -1 means "don't scroll".
    @State private var scrollTarget: Int = -1

    var body: some View {
        HStack(spacing: 0) {
            if showsMarkdown && !tocItems.isEmpty {
                TOCOutlineView(
                    items: tocItems,
                    activeLineIndex: activeTOCIndex,
                    onSelect: { item in
                        guard item.line >= 0 else { return }
                        if let idx = tocItems.firstIndex(where: { $0.id == item.id }) {
                            activeTOCIndex = idx
                        }
                        scrollTarget = item.line
                    }
                )
                .frame(width: 170)
                .background(state.themeStore.current.chromeBackground.opacity(0.5))

                state.themeStore.current.separator
                    .frame(width: 1)
            }

            ZStack {
                MarkdownWebPreview(
                    content: showsMarkdown ? state.previewContent : "",
                    theme: state.themeStore.current,
                    scrollToLine: showsMarkdown ? scrollTarget : -1,
                    onVisibleLineChange: { line in
                        state.previewVisibleLine = line
                        updateActiveTOC(visibleLine: line)
                    },
                    onTOCUpdate: { items in
                        tocItems = items
                        updateActiveTOC(visibleLine: state.previewVisibleLine)
                    },
                    exporter: state.previewExporter,
                    sourceURL: showsMarkdown ? state.selectedTab?.url : nil,
                    fontSize: fontSize
                )
                .opacity(showsMarkdown ? 1 : 0)
                .allowsHitTesting(showsMarkdown)

                WebPreviewView(
                    fileURL: showsHTML ? state.previewHTMLFileURL : nil,
                    reloadToken: state.previewReloadToken,
                    exporter: state.previewExporter,
                    rootURL: state.rootURL
                )
                .opacity(showsHTML ? 1 : 0)
                .allowsHitTesting(showsHTML)

                if state.previewMode == .empty {
                    emptyState
                        .background(Color(nsColor: .textBackgroundColor))
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: state.editorVisibleLine) { _, newLine in
            // Editor scroll drives preview scroll (normal editor↔preview sync)
            scrollTarget = newLine
        }
        .onReceive(NotificationCenter.default.publisher(for: .previewFontSizeChanged)) { _ in
            fontSize = AppSettings.shared.previewFontSize
        }
    }

    private var showsMarkdown: Bool { state.previewMode == .markdown }
    private var showsHTML: Bool { state.previewMode == .html }

    private func updateActiveTOC(visibleLine: Int) {
        guard !tocItems.isEmpty else { activeTOCIndex = -1; return }
        var best = -1
        for (idx, item) in tocItems.enumerated() {
            if item.line <= visibleLine { best = idx }
            else { break }
        }
        activeTOCIndex = best
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "eye")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text(L("preview.empty"))
                .foregroundStyle(.tertiary)
                .font(.system(size: 12))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
