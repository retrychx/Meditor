import Foundation

// MARK: - Errors（共享层：macOS / iOS 共用，勿在 iOS 端另设替身）

struct PatchNotFoundError: LocalizedError {
    let find: String
    let nearbyContext: String
    var errorDescription: String? {
        "[!] 未找到匹配文本：「\(find.prefix(60))」\n\n\(nearbyContext)\n\n建议：请用 read_document 重新读取文件内容，确认目标文本后再 patch。"
    }
}

enum AgentContextError: LocalizedError {
    case noWorkspace
    case noActiveDocument
    case fileAlreadyExists(String)
    case fileNotReadable(String)
    case fileNotFound(String)
    case fileTooLarge(String, Int)
    case fileNotDownloaded(String)
    case pathOutsideWorkspace(String)

    var errorDescription: String? {
        switch self {
        case .noWorkspace:                return "未打开工作区"
        case .noActiveDocument:           return "没有激活的文档"
        case .fileAlreadyExists(let n):   return "文件已存在：\(n)"
        case .fileNotReadable(let n):     return "文件无法读取（编码不支持）：\(n)"
        case .fileNotFound(let n):        return "未找到文件：\(n)"
        case .fileTooLarge(let n, let s): return "文件过大（\(s / 1000)KB），超出上限 \(DefaultAgentFileRepository.maxFullReadBytes / 1_000_000)MB：\(n)"
        case .fileNotDownloaded(let n):   return "文件尚未从 iCloud 下载到本地：\(n)。已开始下载，请稍后重试。"
        case .pathOutsideWorkspace(let p): return "安全限制：目标路径不在工作区内（\(p)），已拒绝写入。"
        }
    }
}

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
    func readFile(at url: URL) async throws -> String          // 截断到 maxReadBytes，多编码 fallback，Task.detached
    /// 同步小文件读取，仅供 DocumentContext 的同步接口（currentDocument/patchDocument）在
    /// tab 初始内容尚未异步加载完成时的读盘兜底使用；不用于 AI 工具调用的主路径。
    func readFileSyncFallback(at url: URL) throws -> String
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

    static let maxReadBytes     = 64_000       // 截断阈值（按字符数，约 64 KB ASCII 等量，~16 k tokens）
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

    func readFile(at url: URL) async throws -> String {
        let fileURL = url
        return try await Task.detached(priority: .userInitiated) {
            try Self.decodeFile(at: fileURL, maxChars: Self.maxReadBytes)
        }.value
    }

    func readFileSyncFallback(at url: URL) throws -> String {
        try Self.decodeFile(at: url, maxChars: Self.maxReadBytes)
    }

    /// 共享的读盘 + 多编码解码逻辑，供同步/异步两个入口复用。
    /// 解码统一走 TextFileDecoder；先完整解码，再按**字符**截断——按字节截断可能切断
    /// 多字节 UTF-8 字符，导致 utf8 解码整体失败、全文错误回退其他编码（非 ASCII 文件乱码）。
    private static func decodeFile(at url: URL, maxChars: Int) throws -> String {
        // iCloud 占位符：触发后台下载，抛出可读错误让模型稍后重试（下载完成由 FSEvents 刷新）
        if UbiquitousFileHelper.isUbiquitousItemNotDownloaded(url) {
            UbiquitousFileHelper.startDownloadingIfNeeded(url)
            throw AgentContextError.fileNotDownloaded(url.lastPathComponent)
        }
        let data = try Data(contentsOf: url)
        guard let full = TextFileDecoder.decode(data) else {
            throw AgentContextError.fileNotReadable(url.lastPathComponent)
        }
        guard full.count > maxChars else { return full }
        return String(full.prefix(maxChars))
            + "\n\n…[truncated: showing first \(maxChars) of \(full.count) characters]"
    }

    func readDiskFull(at url: URL) async throws -> String {
        let fileURL = url
        return try await Task.detached(priority: .userInitiated) {
            // iCloud 占位符：同 decodeFile，先触发下载再报可读错误
            if UbiquitousFileHelper.isUbiquitousItemNotDownloaded(fileURL) {
                UbiquitousFileHelper.startDownloadingIfNeeded(fileURL)
                throw AgentContextError.fileNotDownloaded(fileURL.lastPathComponent)
            }
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
#if os(macOS)
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
#else
        // iOS 无 Process：返回 nil，由 searchWorkspace 回退到 swiftSearch 慢路径
        return nil
#endif
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
            // 解码与读盘路径统一走 TextFileDecoder（不认识的编码进 skipped 清单，
            // 不再用 isoLatin1 把二进制/非 UTF 文件当乱码文本搜）
            guard let content = TextFileDecoder.decode(data) else {
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
