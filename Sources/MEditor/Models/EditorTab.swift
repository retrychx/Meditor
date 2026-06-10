import Foundation

struct EditorTab: Identifiable {
    let id = UUID()
    var url: URL
    var content: String
    /// Monotonic revision used by SwiftUI equality gates without comparing the
    /// full content string on every render.
    var contentRevision: Int = 0
    var language: EditorLanguage
    var isModified = false
    var awaitingInitialContent = false

    var name: String { url.lastPathComponent }
    var iconName: String {
        language == .markdown ? "doc.text" : "doc.richtext"
    }
}
