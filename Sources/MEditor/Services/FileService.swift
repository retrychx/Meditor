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
    private let indexedResourceKeys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]

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
        item.childrenLoaded = true
        return item.children ?? []
    }

    func loadAllFiles(under directory: URL) -> [FileItem] {
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: indexedResourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [FileItem] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(indexedResourceKeys)) else { continue }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else { continue }
            guard FileTypeConfiguration.shared.supportedExtensions.contains(url.pathExtension.lowercased()) else {
                continue
            }
            files.append(FileItem(url: url, isDirectory: false, childrenLoaded: true))
        }
        return sortItems(files)
    }

    // MARK: - File I/O

    func readFile(at url: URL) throws -> String {
        try TextFileDecoder.decode(contentsOf: url)
    }

    func writeFile(at url: URL, content: String) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func createFile(at url: URL, content: String) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func createDirectory(at url: URL) throws {
        try fm.createDirectory(at: url, withIntermediateDirectories: false)
    }

    func moveItem(from source: URL, to destination: URL) throws {
        try fm.moveItem(at: source, to: destination)
    }

    func removeItem(at url: URL) throws {
        try fm.removeItem(at: url)
    }

    func fileExists(at url: URL) -> Bool {
        fm.fileExists(atPath: url.path)
    }

    func fileExists(at url: URL, isDirectory: inout Bool) -> Bool {
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: url.path, isDirectory: &isDir)
        isDirectory = isDir.boolValue
        return exists
    }

    func attributes(at url: URL) -> [FileAttributeKey: Any]? {
        try? fm.attributesOfItem(atPath: url.path)
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
