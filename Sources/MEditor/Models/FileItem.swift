import Foundation
import Observation

@Observable
final class FileItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let isDirectory: Bool
    var children: [FileItem]?

    init(url: URL, isDirectory: Bool, children: [FileItem]? = nil) {
        self.url = url
        self.isDirectory = isDirectory
        self.children = children
    }

    var name: String { url.lastPathComponent }
    var fileExtension: String { url.pathExtension.lowercased() }

    /// True if this file can be opened by the editor.
    var isSupported: Bool {
        isDirectory || FileTypeConfiguration.shared.supportedExtensions.contains(fileExtension)
    }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
