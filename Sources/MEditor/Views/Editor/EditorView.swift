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
                // Editor → preview: report visible top line.
                onVisibleTopLineChange: { line in
                    state.editorVisibleLine = line
                },
                // Preview → editor: scroll to line set by preview.
                scrollToLine: state.editorScrollCommand.line,
                scrollRequestID: state.editorScrollCommand.nonce,
                theme: state.themeStore.current
            )
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.quaternary)
                Text(L("editor.selectFile"))
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
