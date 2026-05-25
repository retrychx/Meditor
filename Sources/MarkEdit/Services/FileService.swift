import Foundation

enum FileServiceError: LocalizedError {
    case accessDenied
    case readFailed(Error)
    case writeFailed(Error)

    var errorDescription: String? {
        switch self {
        case .accessDenied: return "Access denied to the file"
        case .readFailed(let e): return "Failed to read file: \(e.localizedDescription)"
        case .writeFailed(let e): return "Failed to write file: \(e.localizedDescription)"
        }
    }
}

final class FileService {
    private let fm = FileManager.default

    // MARK: - Directory scanning

    /// Load immediate children of a directory, returning only supported files + folders.
    func loadContents(of directory: URL) -> [FileItem] {
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var items: [URL: FileItem] = [:]

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                  let isDir = values.isDirectory
            else { continue }

            let ext = fileURL.pathExtension.lowercased()
            // Skip directories we don't want (keep going into subdirectories though)
            if !isDir && !FileItem.supportedExtensions.contains(ext) {
                continue
            }

            let item = FileItem(url: fileURL, isDirectory: isDir)
            items[fileURL] = item
        }

        // Build tree from flat list
        let rootItems = buildTree(from: items, root: directory)
        return sortItems(rootItems)
    }

    func loadImmediateChildren(of directory: URL) -> [FileItem] {
        guard let urls = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .localizedNameKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let items = urls.compactMap { url -> FileItem? in
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                  let isDir = values.isDirectory
            else { return nil }

            let ext = url.pathExtension.lowercased()
            if !isDir && !FileItem.supportedExtensions.contains(ext) {
                return nil
            }

            return FileItem(url: url, isDirectory: isDir)
        }

        return sortItems(items)
    }

    func loadChildren(for item: FileItem) -> [FileItem] {
        item.children = loadImmediateChildren(of: item.url)
        return item.children ?? []
    }

    // MARK: - File I/O

    func readFile(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func writeFile(at url: URL, content: String) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Private

    private func buildTree(from items: [URL: FileItem], root: URL) -> [FileItem] {
        let rootChildren = items.filter { $0.key.deletingLastPathComponent() == root }
        let sorted = sortItems(Array(rootChildren.values))

        for item in sorted where item.isDirectory {
            item.children = buildTree(from: items, root: item.url)
        }

        return sorted
    }

    private func sortItems(_ items: [FileItem]) -> [FileItem] {
        items.sorted { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory && !b.isDirectory
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}
