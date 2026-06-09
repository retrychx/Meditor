import Foundation

struct EditorTab: Identifiable {
    let id = UUID()
    var url: URL
    var content: String
    var language: EditorLanguage
    var isModified = false
    var awaitingInitialContent = false

    var name: String { url.lastPathComponent }
    var iconName: String {
        language == .markdown ? "doc.text" : "doc.richtext"
    }
}
