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

    // MARK: - Command Sandbox

    /// 向用户展示确认对话框，询问是否允许执行该命令。
    /// 此方法 **仅负责 UI 对话**，不做缓存判断；缓存逻辑由调用方（RunCommandTool）管理。
    /// 返回 true 表示用户点击了「允许」。
    func confirmCommandExecution(_ command: String, cwd: String?) async -> Bool

    /// 检查某条命令（由 CommandSandbox.approvalKey 生成的 key）是否已在本 Agent 会话中被批准。
    func isCommandApproved(_ key: String) -> Bool

    /// 将某条命令标记为已在本 Agent 会话中批准，后续相同 key 不再弹确认框。
    func markCommandApproved(_ key: String)

    /// 当前 skill 声明的可执行命令前缀白名单（来自 SKILL.md `allowedCommands:` 字段）。
    /// nil 表示无限制（未在 skill 内运行，或 skill 未声明白名单）。
    var allowedCommandPatterns: [String]? { get }

    /// 由 Skill 调用方将 allowedCommands 注入上下文。
    /// - Parameter patterns: 允许的命令前缀列表；nil 或空数组表示无限制。
    func setAllowedCommandPatterns(_ patterns: [String]?)

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
