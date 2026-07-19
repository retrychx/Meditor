import Foundation

// MARK: - AtMentionContextBuilder

/// 把一组已确认的 @token 转成可直接注入 system prompt 的字符串。
///
/// 职责单一：只负责“读取内容 → 格式化文本”，不感知 UI。
/// 文件 IO 在 Task.detached 后台执行，不阻塞主线程。
enum AtMentionContextBuilder {

    // MARK: - Build

    /// 异步为一组 token 构建注入片段。文件 IO 在后台执行。
    /// - Parameters:
    ///   - tokens: 用户在输入框中已确认的 @引用列表
    ///   - currentDocName: 当前文档名（由主线程在调用时传入）
    ///   - currentDocContent: 当前文档内容
    ///   - workspaceRoot: 工作区根目录
    ///   - workspaceFiles: 工作区文件列表（已在内存）
    /// - Returns: 可追加到 system prompt 末尾的字符串
    static func build(
        tokens: [AtMentionToken],
        currentDocName: String?,
        currentDocContent: String?,
        workspaceRoot: URL?,
        workspaceFiles: [FileItem]
    ) async -> String {
        guard !tokens.isEmpty else { return "" }

        // 去重（同一文件 @ 多次只读一次）
        var seen = Set<AtMentionKind>()
        let unique  = tokens.filter { seen.insert($0.kind).inserted }
        let limited = Array(unique.prefix(AtMentionLimits.maxTokensPerMessage))
        let skipped = unique.count - limited.count

        // 文件 IO 在后台执行
        let sections: [String] = await Task.detached(priority: .userInitiated) {
            var result: [String] = []
            for token in limited {
                if let section = buildSection(
                    for: token,
                    currentDocName: currentDocName,
                    currentDocContent: currentDocContent,
                    workspaceRoot: workspaceRoot,
                    workspaceFiles: workspaceFiles
                ) {
                    result.append(section)
                }
            }
            if skipped > 0 {
                result.append("[!] [\(skipped) more @mention(s) were omitted to stay within context limits]")
            }
            return result
        }.value

        guard !sections.isEmpty else { return "" }
        return "\n\n---\n# Referenced Files (@mentions)\n\n" + sections.joined(separator: "\n\n")
    }

    // MARK: - Per-token section (在后台执行，nonisolated)

    private static func buildSection(
        for token: AtMentionToken,
        currentDocName: String?,
        currentDocContent: String?,
        workspaceRoot: URL?,
        workspaceFiles: [FileItem]
    ) -> String? {
        switch token.kind {

        case .currentDocument:
            guard let name = currentDocName, let content = currentDocContent else {
                return "<!-- @current: no document is open -->"
            }
            let truncated = truncate(content, maxBytes: AtMentionLimits.maxFileBytesPerToken, name: name)
            return "## @current — \(name)\n\n```\n\(truncated)\n```"

        case .workspace:
            guard let root = workspaceRoot else {
                return "<!-- @workspace: no workspace open -->"
            }
            let files = workspaceFiles
                .filter { !$0.isDirectory }
                .sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
                .prefix(AtMentionLimits.maxDirChildren)
                .map { item -> String in
                    let rel = relativePath(item.url, to: root)
                    return "- \(rel)"
                }
            return "## @workspace — file list\n\n" + files.joined(separator: "\n")

        case .file(let url):
            let display = displayPath(url, root: workspaceRoot)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return "<!-- @\(display): file not found -->"
            }
            guard let raw = try? Data(contentsOf: url),
                  let text = TextFileDecoder.decode(raw) else {
                return "<!-- @\(display): binary or unreadable file -->"
            }
            let content = truncate(text, maxBytes: AtMentionLimits.maxFileBytesPerToken, name: url.lastPathComponent)
            let lang = languageTag(for: url.pathExtension.lowercased())
            return "## @\(display)\n\n绝对路径（调用工具或 run_command 时必须使用此完整路径）：\(url.path)\n\n```\(lang)\n\(content)\n```"

        case .directory(let url):
            let display = displayPath(url, root: workspaceRoot)
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return "<!-- @\(display)/: directory not readable -->"
            }
            let sorted = items.sorted { $0.lastPathComponent < $1.lastPathComponent }
            let lines = sorted.prefix(AtMentionLimits.maxDirChildren).map { item -> String in
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                return isDir ? "[dir] \(item.lastPathComponent)/" : "[file] \(item.lastPathComponent)"
            }
            let more = items.count > AtMentionLimits.maxDirChildren
                ? "\n... and \(items.count - AtMentionLimits.maxDirChildren) more" : ""
            return "## @\(display)/ — directory contents\n\n绝对路径（调用工具或 run_command 时必须使用此完整路径）：\(url.path)\n\n" + lines.joined(separator: "\n") + more
        }
    }

    // MARK: - Helpers

    private static func truncate(_ text: String, maxBytes: Int, name: String) -> String {
        guard let data = text.data(using: .utf8), data.count > maxBytes else { return text }
        // 解码统一走 TextFileDecoder：截断点可能落在多字节字符中间 → 去掉末尾
        // 最多 3 字节重试 UTF-8；不做 isoLatin1 回退——该回退必然"成功"，
        // 会把 CJK 文件尾部整段解码成乱码。
        // text 本身是合法 UTF-8，解码必然成功；String(text.prefix) 仅为理论兜底。
        let result = TextFileDecoder.decode(Data(data.prefix(maxBytes)))
            ?? String(text.prefix(maxBytes))
        return result + "\n\n⚠️ [\(name) truncated at \(maxBytes / 1000)KB - \(data.count / 1000)KB total]"
    }

    private static func relativePath(_ url: URL, to root: URL) -> String {
        let p = url.standardizedFileURL.path
        let r = root.standardizedFileURL.path
        return p.hasPrefix(r) ? String(p.dropFirst(r.count + 1)) : url.lastPathComponent
    }

    /// @ 引用标题显示路径：工作区内 → 相对工作区根路径（如 test111/index.html）；
    /// 工作区外或无工作区 → 绝对路径。让 AI 拿到可精确定位/回写的路径，而非仅文件名。
    private static func displayPath(_ url: URL, root: URL?) -> String {
        let p = url.standardizedFileURL.path
        if let root {
            let r = root.standardizedFileURL.path
            if p == r { return url.lastPathComponent }
            if p.hasPrefix(r + "/") { return String(p.dropFirst(r.count + 1)) }
        }
        return p
    }

    private static func languageTag(for ext: String) -> String {
        switch ext {
        case "md", "markdown": return "markdown"
        case "swift":          return "swift"
        case "ts", "tsx":      return "typescript"
        case "js", "jsx":      return "javascript"
        case "py":             return "python"
        case "json":           return "json"
        case "yaml", "yml":    return "yaml"
        case "html":           return "html"
        case "css":            return "css"
        case "sh", "bash":     return "bash"
        case "go":             return "go"
        case "rs":             return "rust"
        case "kt":             return "kotlin"
        case "java":           return "java"
        case "c", "h":         return "c"
        case "cpp", "hpp":     return "cpp"
        case "rb":             return "ruby"
        default:               return ""
        }
    }
}
