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
                onScrollChange: { percent in
                    state.editorScrollPercent = percent
                },
                previewScrollPercent: state.previewScrollPercent
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
