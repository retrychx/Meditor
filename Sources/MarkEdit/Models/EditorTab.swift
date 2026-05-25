import Foundation

struct EditorTab: Identifiable {
    let id = UUID()
    let url: URL
    var content: String
    var language: EditorLanguage
    var isModified = false

    var name: String { url.lastPathComponent }
    var iconName: String {
        language == .markdown ? "doc.text" : "doc.richtext"
    }
}
