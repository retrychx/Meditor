import Foundation
import Observation

/// A single open editor tab.
///
/// Implemented as `@Observable class` so that SwiftUI observation tracks
/// individual property access rather than the whole `AppState.openTabs`
/// array. The key win: typing text mutates `tab.content` on the class
/// reference — the `openTabs` array value does NOT change, so TabButton
/// views that only read `tab.name` / `tab.isModified` are never re-rendered.
@Observable
final class EditorTab: Identifiable {
    let id: UUID
    var url: URL
    var content: String
    /// Monotonic revision used by SwiftUI equality gates without comparing the
    /// full content string on every render.
    var contentRevision: Int
    var language: EditorLanguage
    var isModified: Bool
    var awaitingInitialContent: Bool

    var name: String { url.lastPathComponent }
    var iconName: String {
        language == .markdown ? "doc.text" : "doc.richtext"
    }

    init(
        id: UUID = UUID(),
        url: URL,
        content: String,
        language: EditorLanguage,
        contentRevision: Int = 0,
        isModified: Bool = false,
        awaitingInitialContent: Bool = false
    ) {
        self.id = id
        self.url = url
        self.content = content
        self.language = language
        self.contentRevision = contentRevision
        self.isModified = isModified
        self.awaitingInitialContent = awaitingInitialContent
    }
}
