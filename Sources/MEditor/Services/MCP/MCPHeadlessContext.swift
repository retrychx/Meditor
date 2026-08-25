import Foundation

// MARK: - 无头 AgentContext（MCP / CLI 环境）

/// 无 UI 环境下 AgentContextProtocol 的实现：
/// - 文件操作锚定固定的工作区根目录（无 tab / 光标 / 当前文档概念，
///   「当前文档」恒为 nil，工具需显式传 filename）；
/// - 文件写入直接放行：MCP 会话里客户端（外部 agent 及其用户）即操作主体，
///   没有可弹确认条的 UI；写目标仍强制限制在工作区内（与 GUI 同一安全边界）；
/// - shell 命令沿用 CommandSandbox 的风险分级：blocked 由工具层直接拒绝，
///   safe 自动批准，warn 级默认拒绝（防御层——桥接层在调用前已按
///   --allow-warn-commands 拦截并给出明确提示，这里兜底防绕过）。
@MainActor
final class MCPHeadlessContext: AgentContextProtocol {

    /// 工作区根目录（启动时固定，不随会话变化）。nonisolated：只读配置。
    nonisolated let workspaceRoot: URL
    /// warn 级命令放行开关（CLI --allow-warn-commands）。默认 false = 从严。
    nonisolated let allowWarnCommands: Bool

    private let files: any AgentFileRepository
    private var approvedCommandKeys: Set<String> = []

    /// nonisolated：只初始化存储属性（URL/Bool/Repository 均为可安全构造的值），
    /// 让 MCPServer（非 MainActor）与测试可以在任意上下文创建实例。
    nonisolated init(workspaceRoot: URL, allowWarnCommands: Bool = false) {
        let root = workspaceRoot.standardizedFileURL
        self.workspaceRoot = root
        self.allowWarnCommands = allowWarnCommands
        self.files = DefaultAgentFileRepository({ root })
    }

    // MARK: DocumentContext —— 无「当前文档」概念

    var currentDocument: String? { nil }
    var currentDocumentName: String? { nil }

    func writeDocument(_ content: String) throws {
        throw AgentError.noDocument
    }

    func patchDocument(find: String, replace: String, all: Bool) throws -> Int {
        throw AgentError.noDocument
    }

    func insertIntoDocument(_ text: String) {}

    /// 文件级 patch：与 AgentContext.patchFile 同引擎同校验，只是没有 tab 优先级与快照。
    func patchFile(name: String, find: String, replace: String, all: Bool) async throws -> Int {
        guard let url = resolveExistingFile(name) else {
            throw AgentContextError.fileNotFound(name)
        }
        try validateWriteTarget(url)
        let original = try await files.readDiskFull(at: url)
        let (updated, count) = PatchEngine.apply(to: original, find: find, replace: replace, all: all)
        if count == 0 {
            throw PatchNotFoundError(
                find: find,
                nearbyContext: PatchEngine.nearbyContext(in: original, around: find)
            )
        }
        try files.writeDisk(updated, to: url)
        return count
    }

    // MARK: WorkspaceContext

    var workspaceURL: URL? { workspaceRoot }

    func listWorkspaceFiles(extensions: [String]) async -> [URL] {
        await files.listWorkspaceFiles(extensions: extensions)
    }

    func readFile(at url: URL) async throws -> String {
        try await files.readFile(at: url)
    }

    func fileContentFull(at url: URL) async throws -> String {
        try await files.readDiskFull(at: url)
    }

    func resolveFile(_ name: String) -> FileResolveResult {
        files.resolveFile(name)
    }

    func searchWorkspace(query: String, extensions: [String]) async -> [String] {
        await files.searchWorkspace(query: query, extensions: extensions)
    }

    func createFile(name: String, content: String) throws -> URL {
        try validateWriteTarget(files.resolveURL(name))
        return try files.createFile(name: name, content: content)
    }

    func writeFile(name: String, content: String) throws -> URL {
        try validateWriteTarget(files.resolveURL(name))
        return try files.writeFile(name: name, content: content)
    }

    func createDirectory(name: String) throws -> URL {
        try validateWriteTarget(files.resolveURL(name))
        return try files.createDirectory(name: name)
    }

    /// 无编辑器，「打开 tab」无意义（对应工具本身也未暴露给 MCP）。
    func openFile(named name: String) -> Bool { false }

    /// 与 AgentContext.validateWriteTarget 同一安全边界：写入目标必须在工作区内，
    /// 两侧都先解析符号链接再比较（防工作区内 symlink 逃逸）。
    private func validateWriteTarget(_ url: URL) throws {
        let target = CommandSandbox.resolveSymlinks(url)
        let root = CommandSandbox.resolveSymlinks(workspaceRoot)
        guard target.path == root.path || target.path.hasPrefix(root.path + "/") else {
            throw AgentContextError.pathOutsideWorkspace(target.path)
        }
    }

    // MARK: ShellContext

    /// 无 UI 可弹确认：safe 自动批准；warn 级按 allowWarnCommands 开关决定
    /// （默认拒绝并记 stderr 日志）。blocked 在工具层已被拦截，到不了这里。
    func confirmCommandExecution(_ command: String, cwd: String?) async -> Bool {
        if case .warn = CommandSandbox.assess(command), !allowWarnCommands {
            MCPLog.info("denied warn-level command in headless mode: \(command)")
            return false
        }
        return true
    }

    func isCommandApproved(_ key: String) -> Bool {
        approvedCommandKeys.contains(key)
    }

    func markCommandApproved(_ key: String) {
        approvedCommandKeys.insert(key)
    }

    /// 无 Skill 上下文，不做命令前缀白名单限制（沙箱风险分级仍然生效）。
    var allowedCommandPatterns: [String]? { nil }
    func setAllowedCommandPatterns(_ patterns: [String]?) {}

    // MARK: 文件写入确认 —— 无头放行（见类型注释）

    func confirmFileWrite(_ path: String, summary: String) async -> Bool { true }
    func confirmFileWrite(_ preview: FileWritePreview) async -> Bool { true }

    /// 恒为 true：写工具跳过确认与 diff 预览构建，直接执行。
    var isFileWriteAllowedForRun: Bool { true }
}
