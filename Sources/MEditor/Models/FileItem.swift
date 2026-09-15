import Foundation
import Observation

/// @unchecked Sendable：树模型在后台线程构建、主线程消费；现有设计已按此约定使用，
/// 迁移到 Swift 6 语言模式时显式标注该约定（真正的隔离重构另议）。
@Observable
final class FileItem: Identifiable, Hashable, @unchecked Sendable {
    /// Stable identity based on URL. Using the URL (not a per-instance UUID)
    /// is critical so that SwiftUI's List preserves expansion state when
    /// `reloadFileTree()` rebuilds the entire tree (e.g. after a file watcher
    /// event). Without a stable id, every reload would collapse all expanded
    /// folders.
    var id: URL { url }

    let url: URL
    let isDirectory: Bool
    var children: [FileItem]?
    var childrenLoaded: Bool
    var isLoadingChildren = false

    init(url: URL, isDirectory: Bool, children: [FileItem]? = nil, childrenLoaded: Bool? = nil) {
        self.url = url
        self.isDirectory = isDirectory
        self.children = children
        self.childrenLoaded = childrenLoaded ?? (!isDirectory || children != nil)
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
