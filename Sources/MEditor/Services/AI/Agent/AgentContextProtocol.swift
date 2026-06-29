import Foundation

/// 文件解析结果（区分唯一找到、多个同名、未找到）
enum FileResolveResult {
    case found(URL)
    case ambiguous([URL])   // 多个同名文件，按优先级排序
    case notFound
}

/// AgentContext 的抽象协议。
/// 工具依赖此协议而非具体类，方便单测注入 MockAgentContext。
@MainActor
protocol AgentContextProtocol: AnyObject {
    // MARK: - Current document
    var currentDocument: String? { get }
    var currentDocumentName: String? { get }
    var workspaceURL: URL? { get }

    // MARK: - Document operations
    func writeDocument(_ content: String) throws
    @discardableResult
    func patchDocument(find: String, replace: String, all: Bool) throws -> Int
    func insertIntoDocument(_ text: String)
    /// 文件级精准 patch（不依赖激活 tab）。返回替换次数；文件不存在时抛错。
    @discardableResult
    func patchFile(name: String, find: String, replace: String, all: Bool) async throws -> Int

    // MARK: - Workspace file operations
    func listWorkspaceFiles(extensions: [String]) -> [URL]
    func readFile(at url: URL) throws -> String
    /// 文件"当前最准确"的完整内容（开着的 Tab 内存内容优先，否则完整读盘；不截断）。
    func fileContentFull(at url: URL) async throws -> String
    @discardableResult
    func createFile(name: String, content: String) throws -> URL
    @discardableResult
    func writeFile(name: String, content: String) throws -> URL
    @discardableResult
    func createDirectory(name: String) throws -> URL
    @discardableResult
    func openFile(named name: String) -> Bool
    func searchWorkspace(query: String, extensions: [String]) async -> [String]

    /// 请求用户确认执行某条命令（会话级授权：首次确认后本会话不再询问）。
    /// 返回 true 表示允许执行。
    func confirmCommandExecution(_ command: String, cwd: String?) async -> Bool

    /// 解析文件名/路径，区分唯一找到、多个同名、未找到三种情况。
    func resolveFile(_ name: String) -> FileResolveResult
}

// MARK: - Shared path resolution

extension AgentContextProtocol {
    /// 把文件名 / 工作区相对路径 / 绝对路径解析为"已存在"的文件 URL。
    /// 委托给 resolveFile，取 found 或 ambiguous 的首个结果。
    func resolveExistingFile(_ name: String) -> URL? {
        switch resolveFile(name) {
        case .found(let url):       return url
        case .ambiguous(let urls):  return urls.first
        case .notFound:             return nil
        }
    }
}
