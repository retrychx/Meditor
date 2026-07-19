import Foundation

/// iOS 端 AgentContextProtocol 实现。
///
/// macOS 端由 AgentContext + AgentDocumentAdapter（AppKit 桥）组成；移动端没有
/// AppKit/AppState，这里直接基于 DocumentStore（当前文档）+
/// DefaultAgentFileRepository（工作区 IO，限定在沙盒 Documents 目录）实现。
///
/// 不支持的能力（光标插入、shell 命令确认等）按约定返回空实现 / false。
@MainActor
final class MobileAgentContext: AgentContextProtocol {

    private let store: DocumentStore
    private let repo: DefaultAgentFileRepository

    init(store: DocumentStore) {
        self.store = store
        // 工作区跟随 store（可注入，测试友好），不再静态直引。
        self.repo  = DefaultAgentFileRepository { store.workspace }
    }

    // MARK: - DocumentContext

    var currentDocument: String? { store.hasDocument ? store.text : nil }
    var currentDocumentName: String? { store.hasDocument ? store.fileName : nil }

    func writeDocument(_ content: String) throws {
        try store.noteAIReplace(content)
    }

    @discardableResult
    func patchDocument(find: String, replace: String, all: Bool) throws -> Int {
        guard store.hasDocument else { throw AgentContextError.noActiveDocument }
        let (updated, count) = PatchEngine.apply(to: store.text, find: find, replace: replace, all: all)
        if count == 0 {
            throw PatchNotFoundError(
                find: find,
                nearbyContext: PatchEngine.nearbyContext(in: store.text, around: find)
            )
        }
        try store.noteAIReplace(updated)
        return count
    }

    /// 移动端没有编辑器光标：退化为追加到文档末尾。
    func insertIntoDocument(_ text: String) {
        guard store.hasDocument else { return }
        let separator = store.text.hasSuffix("\n") || store.text.isEmpty ? "" : "\n"
        do {
            try store.noteAIReplace(store.text + separator + text)
        } catch {
            print("[MobileAgentContext] insert_at_cursor 写盘失败：\(error.localizedDescription)")
        }
    }

    @discardableResult
    func patchFile(name: String, find: String, replace: String, all: Bool) async throws -> Int {
        guard let url = resolveExistingFile(name) else {
            throw AgentContextError.fileNotFound(name)
        }
        try validateWriteTarget(url)
        let original       = try await fileContentFull(at: url)
        let (updated, cnt) = PatchEngine.apply(to: original, find: find, replace: replace, all: all)
        if cnt == 0 {
            throw PatchNotFoundError(
                find: find,
                nearbyContext: PatchEngine.nearbyContext(in: original, around: find)
            )
        }
        try repo.writeDisk(updated, to: url)
        store.reloadIfCurrent(url)
        return cnt
    }

    /// 写入目标合规性校验：必须位于工作区内（对应 macOS 端 AgentContext.validateWriteTarget；
    /// iOS 无散文件 Tab 概念，工作区即全部可写范围）。
    /// DefaultAgentFileRepository.resolveURL 接受绝对路径与 ../——读路径由沙盒兜底，
    /// 写路径在此拒绝逃逸，防止提示注入诱导 Agent 写工作区外文件。
    private func validateWriteTarget(_ url: URL) throws {
        let target = url.standardizedFileURL
        guard let root = workspaceURL?.standardizedFileURL,
              target.path == root.path || target.path.hasPrefix(root.path + "/") else {
            throw AgentContextError.pathOutsideWorkspace(target.path)
        }
    }

    // MARK: - WorkspaceContext

    var workspaceURL: URL? { store.workspace }

    func listWorkspaceFiles(extensions: [String]) async -> [URL] {
        await repo.listWorkspaceFiles(extensions: extensions)
    }

    func readFile(at url: URL) async throws -> String {
        try await repo.readFile(at: url)
    }

    func fileContentFull(at url: URL) async throws -> String {
        if url.standardizedFileURL == store.sandboxURL?.standardizedFileURL {
            return store.text
        }
        return try await repo.readDiskFull(at: url)
    }

    @discardableResult func createFile(name: String, content: String) throws -> URL {
        try validateWriteTarget(repo.resolveURL(name))
        return try repo.createFile(name: name, content: content)
    }

    @discardableResult func writeFile(name: String, content: String) throws -> URL {
        try validateWriteTarget(repo.resolveURL(name))
        let url = try repo.writeFile(name: name, content: content)
        store.reloadIfCurrent(url)
        return url
    }

    @discardableResult func createDirectory(name: String) throws -> URL {
        try validateWriteTarget(repo.resolveURL(name))
        return try repo.createDirectory(name: name)
    }

    @discardableResult
    func openFile(named name: String) -> Bool {
        guard let url = resolveExistingFile(name) else { return false }
        return store.loadFromSandbox(url)
    }

    func searchWorkspace(query: String, extensions: [String]) async -> [String] {
        await repo.searchWorkspace(query: query, extensions: extensions)
    }

    func resolveFile(_ name: String) -> FileResolveResult {
        repo.resolveFile(name)
    }

    // MARK: - ShellContext（移动端无 shell：全部空实现）

    func confirmCommandExecution(_ command: String, cwd: String?) async -> Bool { false }
    func isCommandApproved(_ key: String) -> Bool { false }
    func markCommandApproved(_ key: String) {}
    var allowedCommandPatterns: [String]? { nil }
    func setAllowedCommandPatterns(_ patterns: [String]?) {}
}
