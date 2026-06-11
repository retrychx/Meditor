import SwiftUI

struct EditorView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let tab = state.selectedTab {
            EditorViewContent(
                tabID: tab.id,
                content: tab.content,
                contentRevision: tab.contentRevision,
                language: tab.language,
                scrollToLine: state.editorScrollCommand.line,
                scrollRequestID: state.editorScrollCommand.nonce,
                theme: state.themeStore.current
            )
            .equatable()
            .transition(.opacity.animation(.easeIn(duration: 0.12)))
            .id(tab.id)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.quaternary)
                Text(L("editor.selectFile"))
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 12))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Inner view that conforms to Equatable — SwiftUI uses this to skip
/// re-evaluation when nothing meaningful changed. The key insight: we
/// compare only `tabID` + `scrollRequestID` + `theme`, NOT the full
/// `content` string. The NSViewRepresentable's `updateNSView` already
/// has its own `lastAcknowledgedContent` gate so it handles content
/// diffs cheaply on its own terms.
private struct EditorViewContent: View, Equatable {
    let tabID: UUID
    let content: String
    let contentRevision: Int
    let language: EditorLanguage
    let scrollToLine: Int
    let scrollRequestID: Int
    let theme: PreviewTheme

    @Environment(AppState.self) private var state

    static func == (lhs: EditorViewContent, rhs: EditorViewContent) -> Bool {
        // Skip content string comparison — O(1) instead of O(n).
        // `contentRevision` preserves correctness for async file loads,
        // external reloads, and model-side content updates.
        lhs.tabID == rhs.tabID &&
        lhs.contentRevision == rhs.contentRevision &&
        lhs.scrollRequestID == rhs.scrollRequestID &&
        lhs.theme == rhs.theme &&
        lhs.language == rhs.language
    }

    var body: some View {
        NativeEditorView(
            content: content,
            contentRevision: contentRevision,
            language: language,
            onContentChange: { [tabID] content in
                state.updateTabContent(tabID, content: content)
            },
            onCursorChange: { line, col in
                state.updateCursorPosition(line: line, column: col)
            },
            onVisibleTopLineChange: { line in
                state.editorVisibleLine = line
            },
            scrollToLine: scrollToLine,
            scrollRequestID: scrollRequestID,
            theme: theme
        )
    }
}
