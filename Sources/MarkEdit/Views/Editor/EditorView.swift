import SwiftUI

struct EditorView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            if !state.openTabs.isEmpty {
                EditorTabBar()
                Divider()
            }

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
                    onScrollChange: { percent in
                        state.editorScrollPercent = percent
                    },
                    previewScrollPercent: state.previewScrollPercent
                )
            } else {
                emptyState
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text("Select a file to edit")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
