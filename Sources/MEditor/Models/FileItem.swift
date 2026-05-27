import Foundation
import Observation

@Observable
final class FileItem: Identifiable, Hashable {
    /// Stable identity based on URL. Using the URL (not a per-instance UUID)
    /// is critical so that SwiftUI's List preserves expansion state when
    /// `reloadFileTree()` rebuilds the entire tree (e.g. after a file watcher
    /// event). Without a stable id, every reload would collapse all expanded
    /// folders.
    var id: URL { url }

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
        lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}
