import Foundation

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
    func patchFile(name: String, find: String, replace: String, all: Bool) throws -> Int

    // MARK: - Workspace file operations
    func listWorkspaceFiles(extensions: [String]) -> [URL]
    func readFile(at url: URL) throws -> String
    /// 文件"当前最准确"的完整内容（开着的 Tab 内存内容优先，否则完整读盘；不截断）。
    func fileContentFull(at url: URL) throws -> String
    @discardableResult
    func createFile(name: String, content: String) throws -> URL
    @discardableResult
    func writeFile(name: String, content: String) throws -> URL
    @discardableResult
    func createDirectory(name: String) throws -> URL
    @discardableResult
    func openFile(named name: String) -> Bool
    func searchWorkspace(query: String, extensions: [String]) -> [String]
}

// MARK: - Shared path resolution

extension AgentContextProtocol {
    /// 把文件名 / 工作区相对路径 / 绝对路径解析为"已存在"的文件 URL。
    /// 解析顺序：绝对路径 → 工作区相对路径 → 全工作区按文件名递归匹配。
    /// 让 read_file / open_file 等工具能统一接受 "index.html"、"test111/index.html"
    /// 以及绝对路径，避免相对路径被误判为"未找到文件"。
    func resolveExistingFile(_ name: String) -> URL? {
        let fm = FileManager.default
        if name.hasPrefix("/") {
            let u = URL(fileURLWithPath: name).standardizedFileURL
            return fm.fileExists(atPath: u.path) ? u : nil
        }
        if let root = workspaceURL {
            let u = root.appendingPathComponent(name).standardizedFileURL
            if fm.fileExists(atPath: u.path) { return u }
        }
        // fallback：按文件名（去掉目录部分）在全工作区递归匹配
        let target = (name as NSString).lastPathComponent
        return listWorkspaceFiles(extensions: []).first { $0.lastPathComponent == target }
    }
}
