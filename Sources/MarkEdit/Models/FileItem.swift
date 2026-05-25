import Foundation
import Observation

@Observable
final class FileItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let isDirectory: Bool
    var children: [FileItem]?
    var isLoading = false

    init(url: URL, isDirectory: Bool, children: [FileItem]? = nil) {
        self.url = url
        self.isDirectory = isDirectory
        self.children = children
    }

    var name: String { url.lastPathComponent }
    var `extension`: String { url.pathExtension.lowercased() }

    var iconName: String {
        if isDirectory { return "folder" }
        switch `extension` {
        case "md", "markdown": return "doc.text"
        case "html", "htm": return "doc.richtext"
        case "css": return "paintbrush"
        case "js": return "doc.append"
        case "json": return "curlybraces"
        case "png", "jpg", "jpeg", "gif", "svg": return "photo"
        default: return "doc"
        }
    }

    static let supportedExtensions: Set<String> = ["md", "markdown", "html", "htm"]

    var isSupported: Bool {
        isDirectory || Self.supportedExtensions.contains(self.extension)
    }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
