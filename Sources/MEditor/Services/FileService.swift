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

final class FileService: FileServiceProtocol {
    private let fm = FileManager.default

    // MARK: - Directory scanning

    /// Load immediate children of a directory (one level only).
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

            if !isDir && !FileTypeConfiguration.shared.supportedExtensions.contains(url.pathExtension.lowercased()) {
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

    private func sortItems(_ items: [FileItem]) -> [FileItem] {
        items.sorted { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory && !b.isDirectory
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}
