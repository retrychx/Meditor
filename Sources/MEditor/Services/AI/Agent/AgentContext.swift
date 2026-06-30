import Foundation

// MARK: - Errors

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

    var errorDescription: String? {
        switch self {
        case .noWorkspace:                return "未打开工作区"
        case .noActiveDocument:           return "没有激活的文档"
        case .fileAlreadyExists(let n):   return "文件已存在：\(n)"
        case .fileNotReadable(let n):     return "文件无法读取（编码不支持）：\(n)"
        case .fileNotFound(let n):        return "未找到文件：\(n)"
        case .fileTooLarge(let n, let s): return "文件过大（\(s / 1000)KB），超出上限 \(DefaultAgentFileRepository.maxFullReadBytes / 1_000_000)MB：\(n)"
        }
    }
}

// MARK: - AgentContext（薄协调层）

/// 把 AgentFileRepository（纯磁盘 IO）和 AgentDocumentAdapter（AppState 交互）
/// 组合成工具层所需的 AgentContextProtocol。
///
/// 自身不含业务逻辑 — 逻辑分别在 PatchEngine / AgentFileRepository / AgentDocumentAdapter 中，
/// 均可独立单测。
@MainActor
final class AgentContext: AgentContextProtocol {

    let files: any AgentFileRepository
    let doc:   any AgentDocumentAdapter

    init(files: any AgentFileRepository, doc: any AgentDocumentAdapter) {
        self.files = files
        self.doc   = doc
    }

    /// 工厂方法：从 AppState 创建标准 AgentContext（App 侧调用）
    static func make(appState: AppState) -> AgentContext {
        let repo    = DefaultAgentFileRepository { [weak appState] in appState?.rootURL }
        let adapter = AppStateDocumentAdapter(appState: appState, fileRepo: repo)
        return AgentContext(files: repo, doc: adapter)
    }

    // MARK: - Current document → doc

    var currentDocument: String?     { doc.currentDocument }
    var currentDocumentName: String? { doc.currentDocumentName }
    var workspaceURL: URL?           { doc.workspaceURL }

    func writeDocument(_ content: String) throws         { try doc.writeDocument(content) }
    func insertIntoDocument(_ text: String)               { doc.insertIntoDocument(text) }

    func patchDocument(find: String, replace: String, all: Bool) throws -> Int {
        try doc.patchDocument(find: find, replace: replace, all: all)
    }

    // MARK: - File IO → files

    func listWorkspaceFiles(extensions: [String]) -> [URL] {
        files.listWorkspaceFiles(extensions: extensions)
    }

    func readFile(at url: URL) throws -> String { try files.readFile(at: url) }

    func searchWorkspace(query: String, extensions: [String]) async -> [String] {
        await files.searchWorkspace(query: query, extensions: extensions)
    }

    // MARK: - fileContentFull（桥接：Tab 内容优先，否则完整读盘）

    func fileContentFull(at url: URL) async throws -> String {
        if let tabContent = doc.contentForTab(at: url) { return tabContent }
        return try await files.readDiskFull(at: url)
    }

    // MARK: - resolveFile（加 Tab 优先级排序）

    func resolveFile(_ name: String) -> FileResolveResult {
        let result = files.resolveFile(name)
        guard case .ambiguous(let urls) = result else { return result }
        let currentURL = doc.currentTabURL
        let sorted = urls.sorted { a, b in
            let aIsCurrent = a.standardizedFileURL == currentURL
            let bIsCurrent = b.standardizedFileURL == currentURL
            if aIsCurrent != bIsCurrent { return aIsCurrent }
            let da = a.pathComponents.count, db = b.pathComponents.count
            return da != db ? da < db : a.path < b.path
        }
        return .ambiguous(sorted)
    }

    // MARK: - File mutations（磁盘 IO + 通知 AppState）

    func createFile(name: String, content: String) throws -> URL {
        let url = try files.createFile(name: name, content: content)
        doc.notifyFileCreated(url)
        return url
    }

    func writeFile(name: String, content: String) throws -> URL {
        let isNew = !FileManager.default.fileExists(atPath: files.resolveURL(name).path)
        let url   = try files.writeFile(name: name, content: content)
        doc.notifyFileWritten(url, content: content, isNew: isNew)
        return url
    }

    func createDirectory(name: String) throws -> URL {
        let url = try files.createDirectory(name: name)
        doc.notifyDirectoryCreated(url)
        return url
    }

    func openFile(named name: String) -> Bool {
        switch resolveFile(name) {
        case .found(let url):      return doc.openFile(at: url)
        case .ambiguous(let urls): return doc.openFile(at: urls[0])
        case .notFound:            return false
        }
    }

    // MARK: - patchFile（桥接：Tab 内容优先 → 磁盘 → 通知）

    func patchFile(name: String, find: String, replace: String, all: Bool) async throws -> Int {
        guard let url = resolveExistingFile(name) else {
            throw AgentContextError.fileNotFound(name)
        }
        let original       = try await fileContentFull(at: url)
        let (updated, cnt) = PatchEngine.apply(to: original, find: find, replace: replace, all: all)
        if cnt == 0 {
            throw PatchNotFoundError(
                find: find,
                nearbyContext: PatchEngine.nearbyContext(in: original, around: find)
            )
        }
        try files.writeDisk(updated, to: url)
        doc.notifyFileWritten(url, content: updated, isNew: false)
        return cnt
    }

    // MARK: - Command Sandbox

    /// Per-Agent-session 的已批准命令 key 集合。
    /// 注意：warn 级命令不写入此集合（每次都弹确认）。
    private var _approvedCommandKeys: Set<String> = []

    func confirmCommandExecution(_ command: String, cwd: String?) async -> Bool {
        await doc.confirmCommandExecution(command, cwd: cwd)
    }

    func isCommandApproved(_ key: String) -> Bool {
        _approvedCommandKeys.contains(key)
    }

    func markCommandApproved(_ key: String) {
        _approvedCommandKeys.insert(key)
    }

    /// 暂时返回 nil（将来当 skill 执行上下文建立后，从 skill 元数据读取）。
    var allowedCommandPatterns: [String]? { nil }
}
