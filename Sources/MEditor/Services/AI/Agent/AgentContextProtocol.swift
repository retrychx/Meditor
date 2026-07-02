import Foundation

/// 文件解析结果（区分唯一找到、多个同名、未找到）
enum FileResolveResult {
    case found(URL)
    case ambiguous([URL])   // 多个同名文件，按优先级排序
    case notFound
}

// MARK: - 窄接口拆分

/// 当前文档读写操作。
@MainActor
protocol DocumentContext: AnyObject {
    var currentDocument: String? { get }
    var currentDocumentName: String? { get }
    func writeDocument(_ content: String) throws
    @discardableResult
    func patchDocument(find: String, replace: String, all: Bool) throws -> Int
    func insertIntoDocument(_ text: String)
    /// 文件级精准 patch（不依赖激活 tab）。返回替换次数；文件不存在时抛错。
    @discardableResult
    func patchFile(name: String, find: String, replace: String, all: Bool) async throws -> Int
}

/// 工作区文件操作。
@MainActor
protocol WorkspaceContext: AnyObject {
    var workspaceURL: URL? { get }
    func listWorkspaceFiles(extensions: [String]) async -> [URL]
    func readFile(at url: URL) async throws -> String
    /// 文件"当前最准确"的完整内容（开着的 Tab 内存内容优先，否则完整读盘；不截断）。
    func fileContentFull(at url: URL) async throws -> String
    @discardableResult func createFile(name: String, content: String) throws -> URL
    @discardableResult func writeFile(name: String, content: String) throws -> URL
    @discardableResult func createDirectory(name: String) throws -> URL
    @discardableResult func openFile(named name: String) -> Bool
    func searchWorkspace(query: String, extensions: [String]) async -> [String]
    func resolveFile(_ name: String) -> FileResolveResult
}

/// 命令沙箱与权限控制。
@MainActor
protocol ShellContext: AnyObject {
    /// 向用户展示确认对话框，询问是否允许执行该命令。
    func confirmCommandExecution(_ command: String, cwd: String?) async -> Bool
    func isCommandApproved(_ key: String) -> Bool
    func markCommandApproved(_ key: String)
    /// 当前 skill 声明的可执行命令前缀白名单。nil 表示无限制。
    var allowedCommandPatterns: [String]? { get }
    func setAllowedCommandPatterns(_ patterns: [String]?)
}

/// 向后兼容别名：组合三个窄接口，现有代码无需改动。
typealias AgentContextProtocol = DocumentContext & WorkspaceContext & ShellContext

// MARK: - WorkspaceContext 便利扩展
// Swift typealias 不支持 extension，resolveExistingFile 放到 WorkspaceContext 里。

extension WorkspaceContext {
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
