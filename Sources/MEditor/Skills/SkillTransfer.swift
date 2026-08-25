import Foundation

// MARK: - SkillTransferError

/// 技能导入/导出（用户间分享）的错误。错误文案全部走 Localization 表。
enum SkillTransferError: Error, Equatable {
    /// 文件/下载内容为空
    case emptyDocument
    /// 缺少 `---` frontmatter
    case missingFrontmatter
    /// frontmatter 缺少有效 name
    case missingName
    /// name 不是安全的文件夹名（含路径分隔符、控制字符、隐藏名等）
    case unsafeName(String)
    /// frontmatter 之外没有正文
    case emptyBody
    /// 超过大小上限（防呆）
    case tooLarge(limitKB: Int)
    /// URL 字符串无法解析
    case invalidURL
    /// 只允许 https://
    case httpsOnly
    /// 下载失败（网络错误或非 2xx）
    case downloadFailed(String)
    /// Content-Type 不是 Markdown/纯文本
    case badContentType(String)
    /// 不是有效 UTF-8 文本
    case notUTF8
}

extension SkillTransferError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .emptyDocument:              return L("skill.transfer.error.empty")
        case .missingFrontmatter:         return L("skill.transfer.error.noFrontmatter")
        case .missingName:                return L("skill.transfer.error.noName")
        case .unsafeName(let name):       return L("skill.transfer.error.unsafeName", name)
        case .emptyBody:                  return L("skill.transfer.error.emptyBody")
        case .tooLarge(let limitKB):      return L("skill.transfer.error.tooLarge", limitKB)
        case .invalidURL:                 return L("skill.transfer.error.invalidURL")
        case .httpsOnly:                  return L("skill.transfer.error.httpsOnly")
        case .downloadFailed(let detail): return L("skill.transfer.error.download", detail)
        case .badContentType(let type):   return L("skill.transfer.error.contentType", type)
        case .notUTF8:                    return L("skill.transfer.error.notUTF8")
        }
    }
}

// MARK: - ParsedSkillDocument

/// 通过校验的技能文档。
struct ParsedSkillDocument: Equatable {
    /// frontmatter 里的 name（将作为安装文件夹名）
    let name: String
    let description: String
    /// frontmatter 之后的正文（prompt）
    let body: String
    /// 原文档全文：导入时原样落盘，保留 commands 等额外 frontmatter 字段
    let document: String
}

// MARK: - SkillTransfer

/// 技能分享：导出为单文件 .md、从文件/URL 导入并安装到本地技能目录。
///
/// 解析规则与 PluginManager 的 frontmatter 解析保持一致（首个 `---` 块、
/// `key: value` 行、值两侧引号剥离），导入侧额外做防呆校验：
/// 大小上限、UTF-8、name 文件系统安全、正文非空；URL 导入再叠加
/// https-only、Content-Type 白名单与超时限制。
enum SkillTransfer {

    /// 单个技能文件大小上限（256 KB，防呆）。
    static let maxBytes = 256 * 1024
    /// URL 导入的请求超时。
    static let requestTimeout: TimeInterval = 15

    // MARK: - 解析与校验

    /// 从原始字节解析（文件/网络导入入口）：先查大小与 UTF-8，再走文本解析。
    static func parse(data: Data, maxBytes: Int = maxBytes) throws -> ParsedSkillDocument {
        guard !data.isEmpty else { throw SkillTransferError.emptyDocument }
        guard data.count <= maxBytes else {
            throw SkillTransferError.tooLarge(limitKB: maxBytes / 1024)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw SkillTransferError.notUTF8
        }
        return try parse(text)
    }

    /// 从文本解析并校验技能文档。
    static func parse(_ content: String) throws -> ParsedSkillDocument {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SkillTransferError.emptyDocument
        }
        guard let (frontMatter, body) = splitFrontMatter(content) else {
            throw SkillTransferError.missingFrontmatter
        }
        guard let name = frontMatterValue("name", in: frontMatter), !name.isEmpty else {
            throw SkillTransferError.missingName
        }
        guard isSafeFolderName(name) else {
            throw SkillTransferError.unsafeName(name)
        }
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { throw SkillTransferError.emptyBody }
        let description = frontMatterValue("description", in: frontMatter) ?? ""
        return ParsedSkillDocument(name: name, description: description,
                                   body: trimmedBody, document: content)
    }

    // MARK: - 导出

    /// 生成某个已安装技能的导出文档：
    /// - 手动技能：SKILL.md 原文（保留 commands 等字段），不合法时返回 nil
    /// - 内置技能：用 name/description + 正文合成规范 frontmatter
    static func exportDocument(for skill: PluginSkill) -> String? {
        switch skill.source {
        case .manual:
            guard let content = try? String(contentsOf: skill.skillPath, encoding: .utf8),
                  (try? parse(content)) != nil else { return nil }
            return content
        case .builtin:
            guard let def = BuiltinSkills.all.first(where: { $0.id == skill.id }) else { return nil }
            return normalizedDocument(name: def.name, description: def.description, body: def.content)
        }
    }

    /// 规范化导出文档：frontmatter 只含 name/description，值为双引号包裹
    /// （含冒号的值也能被解析回原文），正文为 prompt。
    static func normalizedDocument(name: String, description: String, body: String) -> String {
        func clean(_ s: String) -> String {
            s.replacingOccurrences(of: "\n", with: " ")
             .trimmingCharacters(in: .whitespaces)
             .replacingOccurrences(of: "\"", with: "'")
        }
        return """
        ---
        name: "\(clean(name))"
        description: "\(clean(description))"
        ---

        \(body.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }

    /// 导出文件的默认文件名（把文件系统不安全字符替换为 `-`）。
    static func suggestedFileName(for name: String) -> String {
        var cleaned = name.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        for ch in ["/", "\\", ":"] {
            cleaned = cleaned.replacingOccurrences(of: ch, with: "-")
        }
        if cleaned.isEmpty || cleaned.hasPrefix(".") { cleaned = "skill" }
        return "\(cleaned).md"
    }

    // MARK: - 导入安装

    /// 导入安装结果。
    struct InstallOutcome: Equatable {
        /// 最终落地的技能名（文件夹名；冲突时自动加 `-2`/`-3` 后缀）
        let name: String
        /// 落盘的 SKILL.md 路径
        let url: URL
        /// 是否因重名被自动改名
        let renamed: Bool
    }

    /// 解析并安装到本地技能目录，注册进 PluginManager。
    /// 重名（内置 id/name、已安装技能名、目标目录已有文件夹）时自动加后缀，
    /// 与 SkillInstaller 的冲突处理思路一致（不覆盖已有技能）。
    @MainActor
    @discardableResult
    static func install(document: String,
                        into directory: URL = SkillInstaller.defaultSkillsDirectory,
                        pluginManager: PluginManager) throws -> InstallOutcome {
        let parsed = try parse(document)
        let fm = FileManager.default

        var taken = Set(BuiltinSkills.all.map(\.id))
        taken.formUnion(BuiltinSkills.all.map(\.name))
        taken.formUnion(pluginManager.skills.map(\.name))
        if let existing = try? fm.contentsOfDirectory(atPath: directory.path) {
            taken.formUnion(existing)
        }

        let finalName = uniqueName(for: parsed.name, taken: taken)
        let skillDir = directory.appendingPathComponent(finalName, isDirectory: true)
        let skillMD  = skillDir.appendingPathComponent("SKILL.md")
        try fm.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try parsed.document.write(to: skillMD, atomically: true, encoding: .utf8)
        _ = pluginManager.addManual(skillMDURL: skillMD)
        return InstallOutcome(name: finalName, url: skillMD, renamed: finalName != parsed.name)
    }

    // MARK: - URL 导入

    /// URL 安全校验：必须能解析出 host，且 scheme 只允许 https。
    static func validateURL(_ string: String) throws -> URL {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              let host = url.host, !host.isEmpty else {
            throw SkillTransferError.invalidURL
        }
        guard scheme == "https" else { throw SkillTransferError.httpsOnly }
        return url
    }

    /// 从 URL 下载技能文档（返回原文，尚未安装）。
    /// 安全边界：https-only、15s 超时、2xx 状态码、Content-Type 白名单
    /// （拒绝 text/html 等，避免把错误页当技能导入）、大小上限、UTF-8。
    static func fetchDocument(
        urlString: String,
        session: URLSessionDataProtocol = URLSession.shared
    ) async throws -> String {
        let url = try validateURL(urlString)
        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = "GET"

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SkillTransferError.downloadFailed(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse {
            guard (200...299).contains(http.statusCode) else {
                throw SkillTransferError.downloadFailed("HTTP \(http.statusCode)")
            }
            if let rawType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() {
                let base = rawType.split(separator: ";").first?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                let allowed: Set<String> = [
                    "text/plain", "text/markdown", "text/x-markdown", "text/x-web-markdown",
                    "application/markdown", "application/x-markdown", "application/octet-stream",
                ]
                guard allowed.contains(base) else {
                    throw SkillTransferError.badContentType(base)
                }
            }
        }

        guard data.count <= maxBytes else {
            throw SkillTransferError.tooLarge(limitKB: maxBytes / 1024)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw SkillTransferError.notUTF8
        }
        return text
    }

    // MARK: - 名称工具

    /// name 必须能安全用作文件夹名：非空、≤100 字符、无路径分隔符/控制字符、
    /// 不是 `.`/`..`、不以 `.` 开头（隐藏目录）。
    static func isSafeFolderName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 100 else { return false }
        guard trimmed != ".", trimmed != "..", !trimmed.hasPrefix(".") else { return false }
        let illegal = CharacterSet(charactersIn: "/\\:").union(.controlCharacters)
        return trimmed.rangeOfCharacter(from: illegal) == nil
    }

    /// 重名时追加 `-2`/`-3`… 直到不冲突。
    static func uniqueName(for proposed: String, taken: Set<String>) -> String {
        // APFS 默认大小写不敏感：比较统一小写化，避免 "Foo" 静默覆盖已有 "foo" 目录
        let lowered = Set(taken.map { $0.lowercased() })
        guard lowered.contains(proposed.lowercased()) else { return proposed }
        var n = 2
        while lowered.contains("\(proposed)-\(n)".lowercased()) { n += 1 }
        return "\(proposed)-\(n)"
    }

    // MARK: - frontmatter 解析（与 PluginManager 规则对齐）

    /// 切出 `---` frontmatter 与正文；没有 frontmatter 返回 nil。
    /// 行尾容忍 `\r`（CRLF 文件），与 PluginManager 的解析行为对齐。
    static func splitFrontMatter(_ content: String) -> (frontMatter: String, body: String)? {
        guard content.hasPrefix("---") else { return nil }
        let lines = content.components(separatedBy: "\n")
        var end = -1
        for (i, line) in lines.dropFirst().enumerated() {
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == "---" { end = i + 1; break }
        }
        guard end > 0 else { return nil }
        let frontMatter = lines[1..<end].joined(separator: "\n")
        let body = end + 1 < lines.count ? lines[(end + 1)...].joined(separator: "\n") : ""
        return (frontMatter, body)
    }

    /// 取 frontmatter 中某个 `key: value` 的值（剥离两侧引号与空白）。
    static func frontMatterValue(_ key: String, in frontMatter: String) -> String? {
        for line in frontMatter.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = trimmed.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces) == key else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return value
        }
        return nil
    }
}
