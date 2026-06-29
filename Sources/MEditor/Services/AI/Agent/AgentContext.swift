import Foundation

/// patch 操作无法匹配时抛出，包含周边上下文供 AI 自我纠正
struct PatchNotFoundError: LocalizedError {
    let find: String
    let nearbyContext: String
    var errorDescription: String? {
        "⚠️ 未找到匹配文本：「\(find.prefix(60))」\n\n\(nearbyContext)\n\n建议：请用 read_document 重新读取文件内容，确认目标文本后再 patch。"
    }
}

/// Tool execution context — passed to every AgentTool.execute().
/// Provides controlled access to app state so tools can read/write documents and files.
/// Conforms to AgentContextProtocol so tools can be tested with a mock.
@MainActor
final class AgentContext: AgentContextProtocol {
    weak var appState: AppState?

    /// 单次 readFile 最大读取字节数（避免大文件撑爆 context window）
    static let maxReadBytes = 64_000   // ~64 KB，约 16k tokens

    /// patch / search 等全量读取的体积上限（超过则拒绝，避免主线程同步 IO 卡顿 + 撑爆内存）
    static let maxFullReadBytes = 5_000_000   // 5 MB

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Current document

    var currentDocument: String? {
        guard let tab = appState?.selectedTab else { return nil }
        // 编辑器内容是异步加载的（openFileUnchecked 先以空内容建 Tab，再后台读盘）。
        // 刚打开的 Tab content 仍为 ""，此时直接从磁盘读取，
        // 避免 agent 误判"文件为空"。
        if tab.awaitingInitialContent {
            return (try? readFile(at: tab.url)) ?? tab.content
        }
        return tab.content
    }
    var currentDocumentName: String? { appState?.selectedTab?.name }
    var workspaceURL: URL?           { appState?.rootURL }

    /// 全量替换当前文档内容
    func writeDocument(_ content: String) throws {
        guard let state = appState,
              let tab = state.selectedTab else { throw AgentContextError.noActiveDocument }
        // 走 updateTabContent 路径：同时触发预览刷新（onSyncPreview）和自动保存
        state.updateTabContent(tab.id, content: content)
    }

    /// 精准 patch：把文档中第一个（或全部）匹配的 find 替换为 replace
    @discardableResult
    func patchDocument(find: String, replace: String, all: Bool = false) throws -> Int {
        guard let state = appState,
              let tab = state.selectedTab else { throw AgentContextError.noActiveDocument }
        // 基准内容：Tab 刚打开仍在异步加载时 content 为 ""，回退到读盘，
        // 避免 patch 误判"未找到匹配"。
        let original = tab.awaitingInitialContent
            ? ((try? readFile(at: tab.url)) ?? tab.content)
            : tab.content

        let (updated, count) = applyPatch(to: original, find: find, replace: replace, all: all)
        if count == 0 {
            throw PatchNotFoundError(find: find, nearbyContext: buildNearbyContext(in: original, around: find))
        }
        // 走 updateTabContent 路径：同时触发预览刷新（onSyncPreview）和自动保存
        state.updateTabContent(tab.id, content: updated)
        return count
    }

    /// 在当前光标位置插入文本
    func insertIntoDocument(_ text: String) {
        appState?.insertIntoEditor(text)
    }

    /// 请求用户确认执行命令（会话级授权）。已授权则直接放行；否则挂起等待 UI 确认。
    func confirmCommandExecution(_ command: String, cwd: String?) async -> Bool {
        guard let convo = appState?.aiConversation else { return false }
        if convo.commandApprovedThisSession { return true }
        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            convo.pendingCommand = PendingCommand(command: command, cwd: cwd) { approved in
                if approved { convo.commandApprovedThisSession = true }
                convo.pendingCommand = nil
                cont.resume(returning: approved)
            }
        }
    }

    /// 文件级精准 patch：直接对磁盘上指定文件做 find→replace（不依赖激活 tab）。
    /// 完整读取文件内容（不走 readFile 的 64KB 截断，避免把大文件写坏），
    /// 替换后写回，并复用 writeFile 刷新已打开的同名 Tab / Toast / 文件树。
    @discardableResult
    func patchFile(name: String, find: String, replace: String, all: Bool = false) async throws -> Int {
        guard let url = resolveExistingFile(name) else {
            throw AgentContextError.fileNotFound(name)
        }
        // 基准内容：优先用已打开 Tab 的内存内容（含未保存编辑），否则完整读盘。
        // 避免直接读盘后写回，把用户在编辑器里未保存的修改覆盖掉。
        let original = try await fileContentFull(at: url)

        let (updated, count) = applyPatch(to: original, find: find, replace: replace, all: all)
        if count == 0 {
            throw PatchNotFoundError(find: find, nearbyContext: buildNearbyContext(in: original, around: find))
        }
        // 用绝对路径写回：writeFile 会刷新已打开 Tab、reloadFileTree 并弹 Toast
        try writeFile(name: url.path, content: updated)
        return count
    }

    // MARK: - Workspace file operations

    /// 列出工作区中的文件（可按扩展名过滤）
    func listWorkspaceFiles(extensions: [String] = []) -> [URL] {
        guard let root = workspaceURL else { return [] }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL,
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { return nil }
            if extensions.isEmpty { return url }
            return extensions.contains(url.pathExtension.lowercased()) ? url : nil
        }
    }

    /// 读取文件内容，超过 maxReadBytes 时截断并附加提示。
    /// 若该文件已在编辑器打开且加载完成，优先返回其内存内容（含未保存编辑），
    /// 保证 read_document / read_file / open_file 与编辑器看到的一致。
    func readFile(at url: URL) throws -> String {
        if let tab = openLoadedTab(for: url) {
            return truncateForContext(tab.content)
        }

        let data = try Data(contentsOf: url)

        // 尝试 UTF-8 解码
        if let text = String(data: data, encoding: .utf8) {
            return truncateForContext(text)
        }

        // 非 UTF-8 文件：尝试常见编码
        let fallbackEncodings: [String.Encoding] = [.isoLatin1, .ascii, .unicode]
        for enc in fallbackEncodings {
            if let text = String(data: data, encoding: enc) {
                return "⚠️ [文件非 UTF-8 编码，已用 \(enc) 解码]\n\n" + truncateForContext(text)
            }
        }

        throw AgentContextError.fileNotReadable(url.lastPathComponent)
    }

    /// 找到已打开且加载完成的同名 Tab（用于"内存内容优先"，含未保存编辑）。
    private func openLoadedTab(for url: URL) -> EditorTab? {
        appState?.openTabs.first {
            $0.url.standardizedFileURL == url.standardizedFileURL && !$0.awaitingInitialContent
        }
    }

    /// 按 maxReadBytes 对文本做截断（喂给 AI 时控制 token），超限时附加提示。
    private func truncateForContext(_ text: String) -> String {
        guard let data = text.data(using: .utf8), data.count > Self.maxReadBytes else { return text }
        let truncated = data.prefix(Self.maxReadBytes)
        let safe = String(data: truncated, encoding: .utf8)
            ?? String(data: truncated, encoding: .isoLatin1)
            ?? ""
        return safe + "\n\n⚠️ [文件过大，内容已截断至前 \(Self.maxReadBytes / 1000)KB，共 \(data.count / 1000)KB]"
    }

    /// 返回指定文件"当前最准确"的完整内容（不截断）：
    /// 若该文件已在编辑器中打开且已加载完成，优先返回其内存内容（含未保存编辑）；
    /// 否则完整读盘（后台线程，避免主线程阻塞）。
    func fileContentFull(at url: URL) async throws -> String {
        // 内存优先：已打开且已加载完成的 Tab，无需磁盘 IO
        if let tab = openLoadedTab(for: url) { return tab.content }

        // 后台线程做磁盘 IO，避免主线程阻塞（fileURL 是值类型，安全捕获）
        let fileURL = url
        return try await Task.detached(priority: .userInitiated) {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size > AgentContext.maxFullReadBytes {
                throw AgentContextError.fileTooLarge(fileURL.lastPathComponent, size)
            }
            let data = try Data(contentsOf: fileURL)
            guard let text = String(data: data, encoding: .utf8)
                          ?? String(data: data, encoding: .isoLatin1)
            else { throw AgentContextError.fileNotReadable(fileURL.lastPathComponent) }
            return text
        }.value
    }

    /// 在工作区创建新文件（已存在则报错），创建后自动打开并弹出 Toast
    @discardableResult
    func createFile(name: String, content: String = "") throws -> URL {
        let target = resolveURL(name)
        let dir = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw AgentContextError.fileAlreadyExists(name)
        }
        try content.write(to: target, atomically: true, encoding: .utf8)
        appState?.reloadFileTree()
        // 创建后自动在编辑器中打开新文件
        if let state = appState {
            DispatchQueue.main.async {
                let item = FileItem(url: target, isDirectory: false)
                state.openFile(item)
                state.showToast("已创建 \(target.lastPathComponent)", icon: "doc.badge.plus")
            }
        }
        return target
    }

    /// 在工作区创建或覆盖文件，写入后弹出 Toast
    @discardableResult
    func writeFile(name: String, content: String) throws -> URL {
        let target = resolveURL(name)
        let dir = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let isNew = !FileManager.default.fileExists(atPath: target.path)
        try content.write(to: target, atomically: true, encoding: .utf8)
        if let state = appState {
            state.reloadFileTree()
            // 已打开的 Tab 刷新内容
            if let tab = state.openTabs.first(where: { $0.url.standardizedFileURL == target.standardizedFileURL }) {
                state.updateTabContent(tab.id, content: content)
                tab.isModified = false
            }
            let filename = target.lastPathComponent
            if isNew {
                // 新建文件：自动打开
                DispatchQueue.main.async {
                    let item = FileItem(url: target, isDirectory: false)
                    state.openFile(item)
                    state.showToast("已创建 \(filename)", icon: "doc.badge.plus")
                }
            } else {
                state.showToast("已更新 \(filename)", icon: "checkmark.circle")
            }
            // 方案 A：AI 写盘后，若正在预览这个 HTML 文件则强制刷新
            state.reloadHTMLPreviewIfShowing(target)
        }
        return target
    }

    /// 在工作区创建目录（支持多级，支持绝对路径），完成后弹出 Toast
    @discardableResult
    func createDirectory(name: String) throws -> URL {
        let target = resolveURL(name)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        appState?.reloadFileTree()
        let displayName: String
        if let root = appState?.rootURL?.path, target.path.hasPrefix(root) {
            displayName = String(target.path.dropFirst(root.count + 1))
        } else {
            displayName = target.lastPathComponent
        }
        appState?.showToast("已创建目录 \(displayName)", icon: "folder.badge.plus")
        return target
    }

    /// 在编辑器中打开文件（支持文件名、相对路径、绝对路径）
    @discardableResult
    func openFile(named name: String) -> Bool {
        guard let state = appState else { return false }
        // 1. 绝对路径精确匹配
        if name.hasPrefix("/") {
            let target = URL(fileURLWithPath: name).standardizedFileURL
            if FileManager.default.fileExists(atPath: target.path) {
                let item = FileItem(url: target, isDirectory: false)
                state.openFile(item)
                return true
            }
            return false
        }
        // 2. 相对路径（相对工作区根目录）精确匹配
        if let root = state.rootURL {
            let target = root.appendingPathComponent(name).standardizedFileURL
            if FileManager.default.fileExists(atPath: target.path) {
                let item = FileItem(url: target, isDirectory: false)
                state.openFile(item)
                return true
            }
        }
        // 3. 文件名模糊匹配（fallback）
        let files = listWorkspaceFiles()
        guard let url = files.first(where: { $0.lastPathComponent == name }) else { return false }
        let item = FileItem(url: url, isDirectory: false)
        state.openFile(item)
        return true
    }

    /// 全工作区关键词搜索，返回匹配行（带文件名+行号）
    func searchWorkspace(query: String, extensions: [String] = ["md", "txt", "markdown"]) -> [String] {
        let files = listWorkspaceFiles(extensions: extensions)
        let root = workspaceURL?.path ?? ""
        var results: [String] = []
        var skipped: [String] = []

        for url in files {
            guard let data = try? Data(contentsOf: url) else { continue }

            // 非 UTF-8 文件记录但不崩溃
            guard let content = String(data: data, encoding: .utf8) else {
                skipped.append(url.lastPathComponent)
                continue
            }

            let relPath = url.path.hasPrefix(root)
                ? String(url.path.dropFirst(root.count + 1))
                : url.lastPathComponent
            let lines = content.components(separatedBy: "\n")
            for (idx, line) in lines.enumerated() {
                if line.localizedCaseInsensitiveContains(query) {
                    results.append("\(relPath):\(idx + 1): \(line)")
                }
            }
            if results.count >= 100 { break }
        }

        if !skipped.isEmpty {
            results.append("⚠️ 以下文件非 UTF-8 编码，已跳过：\(skipped.joined(separator: ", "))")
        }
        return results
    }

    /// 解析文件名/路径，区分唯一找到、多个同名、未找到三种情况。
    func resolveFile(_ name: String) -> FileResolveResult {
        let fm = FileManager.default

        // 1. 绝对路径
        if name.hasPrefix("/") {
            let u = URL(fileURLWithPath: name).standardizedFileURL
            return fm.fileExists(atPath: u.path) ? .found(u) : .notFound
        }

        // 2. 包含路径分隔符的相对路径
        if name.contains("/"), let root = workspaceURL {
            let u = root.appendingPathComponent(name).standardizedFileURL
            if fm.fileExists(atPath: u.path) { return .found(u) }
        }

        // 3. 纯文件名 — 全工作区递归匹配
        let target = (name as NSString).lastPathComponent
        let allFiles = listWorkspaceFiles(extensions: []).filter { $0.lastPathComponent == target }

        switch allFiles.count {
        case 0: return .notFound
        case 1: return .found(allFiles[0])
        default:
            let currentURL = appState?.selectedTab?.url.standardizedFileURL
            let sorted = allFiles.sorted { a, b in
                if a.standardizedFileURL == currentURL { return true }
                if b.standardizedFileURL == currentURL { return false }
                let da = a.pathComponents.count, db = b.pathComponents.count
                return da != db ? da < db : a.path < b.path
            }
            return .ambiguous(sorted)
        }
    }

    // MARK: - Private

    /// 将相对路径解析为绝对 URL（绝对路径直接使用）
    private func resolveURL(_ name: String) -> URL {
        if name.hasPrefix("/") {
            return URL(fileURLWithPath: name)
        }
        let root = workspaceURL ?? URL(fileURLWithPath: NSHomeDirectory())
        return root.appendingPathComponent(name)
    }

    /// 核心 patch：三级降级匹配（字面→统一换行→去行尾空白），返回 (updated, count)
    private func applyPatch(
        to original: String,
        find: String,
        replace: String,
        all: Bool
    ) -> (updated: String, count: Int) {
        // 三套 (haystack, needle) 按优先级尝试
        let candidates: [(String, String)] = [
            (original, find),
            (
                original.replacingOccurrences(of: "\r\n", with: "\n"),
                find.replacingOccurrences(of: "\r\n", with: "\n")
            ),
            (normalizeWSLines(original), normalizeWSLines(find))
        ]

        for (idx, (haystack, needle)) in candidates.enumerated() {
            if all {
                let replaced = haystack.replacingOccurrences(of: needle, with: replace)
                guard replaced != haystack else { continue }
                let count = haystack.components(separatedBy: needle).count - 1
                // 在 original 上做同样操作（保留原始换行风格）
                let out = idx == 0
                    ? replaced
                    : original.replacingOccurrences(of: find, with: replace)
                return (out, count)
            } else {
                guard let range = haystack.range(of: needle, options: .literal) else { continue }
                if idx == 0 {
                    // 字面匹配：直接在 original 上替换
                    var tmp = original
                    tmp.replaceSubrange(range, with: replace)
                    return (tmp, 1)
                } else {
                    // 归一化策略：尝试在 original 上做字面替换（大文件安全）
                    if let origRange = original.range(of: find, options: .literal) {
                        var tmp = original
                        tmp.replaceSubrange(origRange, with: replace)
                        return (tmp, 1)
                    }
                    var tmp = haystack
                    tmp.replaceSubrange(range, with: replace)
                    return (tmp, 1)
                }
            }
        }
        return (original, 0)
    }

    /// 去掉每行行尾空白并统一换行符
    private func normalizeWSLines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { line -> String in
                var s = line
                while s.last == " " || s.last == "\t" { s.removeLast() }
                return s
            }
            .joined(separator: "\n")
    }

    /// 找不到匹配时，返回文件中最接近的行（帮 AI 自我纠正）
    private func buildNearbyContext(in text: String, around find: String) -> String {
        let keyword = find
            .components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        guard !keyword.isEmpty else { return "(无法生成上下文：find 文本为空)" }

        let lines = text.components(separatedBy: "\n")
        let lower = keyword.lowercased()

        if let matchIdx = lines.indices.first(where: { lines[$0].lowercased().contains(lower) }) {
            let start = max(0, matchIdx - 2)
            let end   = min(lines.count - 1, matchIdx + 2)
            let ctx = lines[start...end].enumerated()
                .map { "L\(start + $0.offset + 1): \($0.element)" }
                .joined(separator: "\n")
            return "文件中最接近的内容（L\(matchIdx + 1) 附近）：\n\(ctx)"
        }
        return "文件中未找到包含「\(keyword.prefix(40))」的行，请重新 read_document 确认内容。"
    }
}

// MARK: - Errors

enum AgentContextError: LocalizedError {
    case noWorkspace
    case noActiveDocument
    case fileAlreadyExists(String)
    case fileNotReadable(String)
    case fileNotFound(String)
    case fileTooLarge(String, Int)

    var errorDescription: String? {
        switch self {
        case .noWorkspace:              return "未打开工作区"
        case .noActiveDocument:         return "没有激活的文档"
        case .fileAlreadyExists(let n): return "文件已存在：\(n)"
        case .fileNotReadable(let n):   return "文件无法读取（编码不支持）：\(n)"
        case .fileNotFound(let n):      return "未找到文件：\(n)"
        case .fileTooLarge(let n, let s): return "文件过大（\(s / 1000)KB），超出可处理上限 \(AgentContext.maxFullReadBytes / 1_000_000)MB：\(n)"
        }
    }
}
