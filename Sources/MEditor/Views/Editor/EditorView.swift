import SwiftUI

struct EditorView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let tab = state.selectedTab {
            NativeEditorView(
                content: tab.content,
                language: tab.language,
                onContentChange: { [tabID = tab.id] content in
                    state.updateTabContent(tabID, content: content)
                },
                onCursorChange: { line, col in
                    state.updateCursorPosition(line: line, column: col)
                },
                // Scroll sync intentionally disabled. Source-view height
                // (compact code) and rendered-view height (large headings,
                // expanded blocks) diverge enough that percentage-based sync
                // is misleading. A future enhancement can use source-line
                // anchors emitted by marked.js for accurate sync.
                onScrollChange: nil,
                previewScrollPercent: 0,
                theme: state.themeStore.current
            )
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.quaternary)
                Text("Select a file to edit")
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
