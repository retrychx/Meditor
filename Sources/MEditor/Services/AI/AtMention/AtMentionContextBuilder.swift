import Foundation

// MARK: - AtMentionContextBuilder

/// 把一组已确认的 @token 转成可直接注入 system prompt 的字符串。
///
/// 职责单一：只负责"读取内容 → 格式化文本"，不感知 UI。
/// 所有 IO 都是同步的（文件读取），调用方负责在合适的线程执行（通常在 send() 时主线程即可）。
@MainActor
enum AtMentionContextBuilder {

    // MARK: - Build

    /// 为一组 token 构建注入片段。
    /// - Parameters:
    ///   - tokens: 用户在输入框中已确认的 @引用列表
    ///   - appState: 用于读取当前文档 / 工作区信息
    /// - Returns: 可追加到 system prompt 末尾的字符串（空时不注入）
    static func build(tokens: [AtMentionToken], appState: AppState) -> String {
        guard !tokens.isEmpty else { return "" }

        // 去重（同一文件 @ 多次只读一次）
        var seen = Set<AtMentionKind>()
        let unique = tokens.filter { seen.insert($0.kind).inserted }

        // 尊重数量上限
        let limited = Array(unique.prefix(AtMentionLimits.maxTokensPerMessage))
        let skipped = unique.count - limited.count

        var sections: [String] = []

        for token in limited {
            if let section = buildSection(for: token, appState: appState) {
                sections.append(section)
            }
        }

        if skipped > 0 {
            sections.append("⚠️ [\(skipped) more @mention(s) were omitted to stay within context limits]")
        }

        guard !sections.isEmpty else { return "" }
        return "\n\n---\n# Referenced Files (@mentions)\n\n" + sections.joined(separator: "\n\n")
    }

    // MARK: - Per-token section

    private static func buildSection(for token: AtMentionToken, appState: AppState) -> String? {
        switch token.kind {

        case .currentDocument:
            guard let tab = appState.selectedTab else {
                return "<!-- @current: no document is open -->"
            }
            let content = truncate(tab.content, maxBytes: AtMentionLimits.maxFileBytesPerToken, name: tab.name)
            return "## @current — \(tab.name)\n\n```\n\(content)\n```"

        case .workspace:
            guard let root = appState.rootURL else {
                return "<!-- @workspace: no workspace open -->"
            }
            let files = appState.fileItemMap.values
                .filter { !$0.isDirectory }
                .sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
                .prefix(AtMentionLimits.maxDirChildren)
                .map { item -> String in
                    let rel = relativePath(item.url, to: root)
                    return "- \(rel)"
                }
            return "## @workspace — file list\n\n" + files.joined(separator: "\n")

        case .file(let url):
            guard FileManager.default.fileExists(atPath: url.path) else {
                return "<!-- @\(url.lastPathComponent): file not found -->"
            }
            guard let raw = try? Data(contentsOf: url),
                  let text = String(data: raw, encoding: .utf8)
                           ?? String(data: raw, encoding: .isoLatin1) else {
                return "<!-- @\(url.lastPathComponent): binary or unreadable file -->"
            }
            let content = truncate(text, maxBytes: AtMentionLimits.maxFileBytesPerToken, name: url.lastPathComponent)
            let ext = url.pathExtension.lowercased()
            let lang = languageTag(for: ext)
            return "## @\(url.lastPathComponent)\n\n```\(lang)\n\(content)\n```"

        case .directory(let url):
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                return "<!-- @\(url.lastPathComponent)/: directory not readable -->"
            }
            let sorted = items.sorted { $0.lastPathComponent < $1.lastPathComponent }
            let lines = sorted.prefix(AtMentionLimits.maxDirChildren).map { item -> String in
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                return isDir ? "📁 \(item.lastPathComponent)/" : "📄 \(item.lastPathComponent)"
            }
            let more = items.count > AtMentionLimits.maxDirChildren
                ? "\n… and \(items.count - AtMentionLimits.maxDirChildren) more" : ""
            return "## @\(url.lastPathComponent)/ — directory contents\n\n" + lines.joined(separator: "\n") + more
        }
    }

    // MARK: - Helpers

    private static func truncate(_ text: String, maxBytes: Int, name: String) -> String {
        guard let data = text.data(using: .utf8), data.count > maxBytes else { return text }
        let prefix = data.prefix(maxBytes)
        let truncated = String(data: prefix, encoding: .utf8)
            ?? String(data: prefix, encoding: .isoLatin1)
            ?? String(text.prefix(maxBytes))
        return truncated + "\n\n⚠️ [\(name) truncated at \(maxBytes / 1000)KB — \(data.count / 1000)KB total]"
    }

    private static func relativePath(_ url: URL, to root: URL) -> String {
        let p = url.standardizedFileURL.path
        let r = root.standardizedFileURL.path
        return p.hasPrefix(r) ? String(p.dropFirst(r.count + 1)) : url.lastPathComponent
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
