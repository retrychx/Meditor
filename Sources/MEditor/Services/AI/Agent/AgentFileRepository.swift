import Foundation

// MARK: - Protocol

/// 工作区文件 IO 的抽象 — 无 AppState 依赖，可独立单测。
/// 所有方法都可以在 @MainActor 上下文调用；内部的 async 方法通过 Task.detached 把 IO 移到后台。
protocol AgentFileRepository: AnyObject {
    var workspaceURL: URL? { get }

    // 路径解析
    func resolveURL(_ name: String) -> URL
    func resolveFile(_ name: String) -> FileResolveResult
    func listWorkspaceFiles(extensions: [String]) async -> [URL]

    // 读写
    func readFile(at url: URL) throws -> String               // 截断到 maxReadBytes，多编码 fallback
    func readDiskFull(at url: URL) async throws -> String      // 完整读取，Task.detached
    func writeDisk(_ content: String, to url: URL) throws      // 原子写盘

    // 高级磁盘操作（不触发 AppState 通知）
    func createFile(name: String, content: String) throws -> URL   // 已存在则 throw
    func writeFile(name: String, content: String) throws -> URL    // create-or-overwrite
    func createDirectory(name: String) throws -> URL

    // 搜索
    func searchWorkspace(query: String, extensions: [String]) async -> [String]
}

// MARK: - Default Implementation

final class DefaultAgentFileRepository: AgentFileRepository {

    /// workspaceURL 通过闭包延迟求值，保证每次都是 AppState 最新的 rootURL
    private let workspaceProvider: () -> URL?

    static let maxReadBytes     = 64_000       // ~64 KB，约 16 k tokens
    static let maxFullReadBytes = 5_000_000    // 5 MB

    /// 枚举工作区文件时跳过的噪音目录名
    static let noiseDirectories: Set<String> = [
        "node_modules", ".git", ".build", "dist", ".next", ".nuxt",
        "DerivedData", ".gradle", "Pods", "vendor", ".cache", "__pycache__"
    ]

    init(_ provider: @escaping () -> URL?) {
        self.workspaceProvider = provider
    }

    var workspaceURL: URL? { workspaceProvider() }

    // MARK: - Path resolution

    func resolveURL(_ name: String) -> URL {
        if name.hasPrefix("/") { return URL(fileURLWithPath: name) }
        let root = workspaceURL ?? URL(fileURLWithPath: NSHomeDirectory())
        return root.appendingPathComponent(name)
    }

    /// 多匹配时按路径深度 + 字母序排列（Tab 优先级由 AgentContext 在外层注入）
    func resolveFile(_ name: String) -> FileResolveResult {
        let fm = FileManager.default
        if name.hasPrefix("/") {
            let u = URL(fileURLWithPath: name).standardizedFileURL
            return fm.fileExists(atPath: u.path) ? .found(u) : .notFound
        }
        if name.contains("/"), let root = workspaceURL {
            let u = root.appendingPathComponent(name).standardizedFileURL
            if fm.fileExists(atPath: u.path) { return .found(u) }
        }
        let target   = (name as NSString).lastPathComponent
        let allFiles = _listWorkspaceFilesSync(extensions: []).filter { $0.lastPathComponent == target }
        switch allFiles.count {
        case 0:  return .notFound
        case 1:  return .found(allFiles[0])
        default:
            let sorted = allFiles.sorted { a, b in
                let da = a.pathComponents.count, db = b.pathComponents.count
                return da != db ? da < db : a.path < b.path
            }
            return .ambiguous(sorted)
        }
    }

    // MARK: - Private sync enumeration (used by resolveFile and searchWorkspace)

    private func _listWorkspaceFilesSync(extensions: [String]) -> [URL] {
        guard let root = workspaceURL else { return [] }
        return Self.enumerate(root: root, extensions: extensions, noiseDirectories: Self.noiseDirectories)
    }

    /// Static helper: enumerates files under `root` — safe to call from any thread / Task.detached.
    static func enumerate(root: URL, extensions: [String], noiseDirectories: Set<String>) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL,
                  let vals = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  vals.isRegularFile == true else { return nil }
            if url.pathComponents.contains(where: { noiseDirectories.contains($0) }) {
                return nil
            }
            if extensions.isEmpty { return url }
            return extensions.contains(url.pathExtension.lowercased()) ? url : nil
        }
    }

    func listWorkspaceFiles(extensions: [String] = []) async -> [URL] {
        guard let root = workspaceURL else { return [] }
        let noise = Self.noiseDirectories
        let exts  = extensions
        return await Task.detached(priority: .utility) {
            DefaultAgentFileRepository.enumerate(root: root, extensions: exts, noiseDirectories: noise)
        }.value
    }

    // MARK: - Read / Write

    func readFile(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let truncated = data.count > Self.maxReadBytes ? data.prefix(Self.maxReadBytes) : data
        if let text = String(data: truncated, encoding: .utf8) { return text }
        for enc: String.Encoding in [.isoLatin1, .ascii, .unicode] {
            if let text = String(data: truncated, encoding: enc) { return text }
        }
        throw AgentContextError.fileNotReadable(url.lastPathComponent)
    }

    func readDiskFull(at url: URL) async throws -> String {
        let fileURL = url
        return try await Task.detached(priority: .userInitiated) {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size > DefaultAgentFileRepository.maxFullReadBytes {
                throw AgentContextError.fileTooLarge(fileURL.lastPathComponent, size)
            }
            let data = try Data(contentsOf: fileURL)
            guard let text = String(data: data, encoding: .utf8) else {
                throw AgentContextError.fileNotReadable(fileURL.lastPathComponent)
            }
            return text
        }.value
    }

    func writeDisk(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - High-level disk ops

    func createFile(name: String, content: String = "") throws -> URL {
        let target = resolveURL(name)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw AgentContextError.fileAlreadyExists(name)
        }
        try content.write(to: target, atomically: true, encoding: .utf8)
        return target
    }

    func writeFile(name: String, content: String) throws -> URL {
        let target = resolveURL(name)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: target, atomically: true, encoding: .utf8)
        return target
    }

    func createDirectory(name: String) throws -> URL {
        let target = resolveURL(name)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }

    // MARK: - Search（grep 快路径 + Swift fallback）

    func searchWorkspace(query: String, extensions: [String] = ["md", "txt", "markdown"]) async -> [String] {
        guard let root = workspaceURL else { return [] }
        if let results = await grepSearch(query: query, extensions: extensions, root: root) {
            return results
        }
        let files    = _listWorkspaceFilesSync(extensions: extensions)
        let rootPath = root.path
        return await Task.detached(priority: .userInitiated) {
            DefaultAgentFileRepository.swiftSearch(query: query, files: files, rootPath: rootPath)
        }.value
    }

    // MARK: - Search internals

    private func grepSearch(query: String, extensions: [String], root: URL) async -> [String]? {
        let unsafeForGrep = CharacterSet(charactersIn: ".+*?^${}[]|()\\")
        guard query.unicodeScalars.allSatisfy({ !unsafeForGrep.contains($0) }),
              !query.isEmpty else { return nil }
        let includes    = extensions.flatMap { ["--include", "*.\($0)"] }
        let excludeDirs = DefaultAgentFileRepository.noiseDirectories.sorted()
                              .flatMap { ["--exclude-dir", $0] }
        let args: [String] = ["-r", "-n", "-i", "--max-count=5"] + includes + excludeDirs + [query, root.path]
        return await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL  = URL(fileURLWithPath: "/usr/bin/grep")
            proc.arguments      = args
            proc.standardOutput = Pipe()
            proc.standardError  = Pipe()
            guard (try? proc.run()) != nil else { return nil }
            let data = (proc.standardOutput as! Pipe).fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            guard proc.terminationStatus <= 1,
                  let raw = String(data: data, encoding: .utf8) else { return nil }
            let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
            return Array(raw.components(separatedBy: "\n")
                .filter  { !$0.isEmpty }
                .prefix(100)
                .map     { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : $0 })
        }.value
    }

    private static func swiftSearch(query: String, files: [URL], rootPath: String) -> [String] {
        let lowerQuery  = query.lowercased()
        let maxTotal    = 100, maxPerFile = 5, maxFileSize = 1_000_000
        var results: [String] = []
        var skipped:  [String] = []
        for url in files {
            guard !Task.isCancelled, results.count < maxTotal else { break }
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size > maxFileSize { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let content = String(data: data, encoding: .utf8)
                             ?? String(data: data, encoding: .isoLatin1) else {
                skipped.append(url.lastPathComponent); continue
            }
            let relPath  = url.path.hasPrefix(rootPath)
                ? String(url.path.dropFirst(rootPath.count + 1))
                : url.lastPathComponent
            var lineNum  = 0, fileCount = 0
            content.enumerateLines { line, stop in
                lineNum += 1
                guard line.lowercased().contains(lowerQuery) else { return }
                results.append("\(relPath):\(lineNum): \(line)")
                fileCount += 1
                if fileCount >= maxPerFile || results.count >= maxTotal { stop = true }
            }
        }
        if !skipped.isEmpty {
            results.append("[!] 以下文件无法解码，已跳过：\(skipped.joined(separator: ", "))")
        }
        return results
    }
}
