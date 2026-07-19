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
        self.repo  = DefaultAgentFileRepository { DocumentStore.workspaceURL }
    }

    // MARK: - DocumentContext

    var currentDocument: String? { store.hasDocument ? store.text : nil }
    var currentDocumentName: String? { store.hasDocument ? store.fileName : nil }

    func writeDocument(_ content: String) throws {
        try store.replaceContent(content)
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
        try store.replaceContent(updated)
        return count
    }

    /// 移动端没有编辑器光标：退化为追加到文档末尾。
    func insertIntoDocument(_ text: String) {
        guard store.hasDocument else { return }
        let separator = store.text.hasSuffix("\n") || store.text.isEmpty ? "" : "\n"
        try? store.replaceContent(store.text + separator + text)
    }

    @discardableResult
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
        try repo.writeDisk(updated, to: url)
        store.reloadIfCurrent(url)
        return cnt
    }

    // MARK: - WorkspaceContext

    var workspaceURL: URL? { DocumentStore.workspaceURL }

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
        try repo.createFile(name: name, content: content)
    }

    @discardableResult func writeFile(name: String, content: String) throws -> URL {
        let url = try repo.writeFile(name: name, content: content)
        store.reloadIfCurrent(url)
        return url
    }

    @discardableResult func createDirectory(name: String) throws -> URL {
        try repo.createDirectory(name: name)
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
