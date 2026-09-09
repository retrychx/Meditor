import Foundation

// MARK: - AgentSkill

/// Agent 技能（Claude Code 风格的 SKILL.md），供 agent 工具循环按需加载。
///
/// 发现位置两处，工作区级覆盖全局同名技能：
///   全局：    ~/.meditor/skills/
///   工作区：  <工作区>/.meditor/skills/
/// 每个目录下支持两种布局：`<技能名>/SKILL.md`（目录型，可带附属脚本/模板）
/// 与平铺的 `<技能名>.md`。与 BuiltinSkills 并存：同名时用户技能优先（目录里标注）。
struct AgentSkill: Sendable, Equatable {
    enum Source: String, Sendable {
        case builtin     // 内置（BuiltinSkills，随 App 发布）
        case global      // ~/.meditor/skills/
        case workspace   // <工作区>/.meditor/skills/
    }

    let name: String
    let description: String
    let version: String?
    let source: Source
    /// SKILL.md / 平铺 .md 的文件 URL（内置技能为 nil）
    let fileURL: URL?
    /// 技能目录（目录型技能；平铺 .md 与内置技能为 nil）
    let directoryURL: URL?
    /// 技能全文（含 frontmatter 原文），load_skill 时返回
    let content: String
    /// 技能目录内附属文件的相对路径清单（不读内容，模型经 read_file 按需读取）
    let attachments: [String]
    /// 是否覆盖了同名内置技能（目录标注用）
    var overridesBuiltin: Bool

    init(
        name: String,
        description: String,
        version: String? = nil,
        source: Source,
        fileURL: URL? = nil,
        directoryURL: URL? = nil,
        content: String,
        attachments: [String] = [],
        overridesBuiltin: Bool = false
    ) {
        self.name             = name
        self.description      = description
        self.version          = version
        self.source           = source
        self.fileURL          = fileURL
        self.directoryURL     = directoryURL
        self.content          = content
        self.attachments      = attachments
        self.overridesBuiltin = overridesBuiltin
    }
}

// MARK: - AgentSkillStore

/// 技能目录扫描与缓存（渐进披露的数据源）。
///
/// 系统提示只注入目录（name + description + 来源），技能正文由模型经 load_skill
/// 工具按需拉取——上下文成本控制。扫描结果缓存在内存里，AgentRunner 每次 run 开始
/// 调用 refresh 重扫（目录很小，直接重扫即可，天然覆盖工作区切换与目录内容变更）；
/// load_skill 在非 Runner 路径使用时经 refreshIfNeeded 兜底。
///
/// 坏文件（读不出、空、非 UTF-8、超大、技能名不合法）跳过并记入 loadErrors，不拖垮加载。
final class AgentSkillStore: @unchecked Sendable {

    /// 共享实例。声明为 var 以便测试注入临时目录的实例（用后须还原）。
    static var shared = AgentSkillStore()

    /// 单个技能文件大小上限（与 SkillTransfer.maxBytes 的 256 KB 防呆对齐；
    /// SkillTransfer 不在 iOS 工程内，这里保留本地常量）。
    static let maxSkillFileBytes = 256 * 1024
    /// 附属文件清单条数上限（防呆）
    static let maxAttachments = 50

    /// 全局技能目录（~/.meditor/skills/），与 MCP 客户端配置（~/.meditor/mcp.json）同一约定。
    static var defaultGlobalDirectory: URL {
#if os(macOS)
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".meditor/skills", isDirectory: true)
#else
        // iOS 无 homeDirectoryForCurrentUser：用沙盒容器 home 保持同一相对结构
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".meditor/skills", isDirectory: true)
#endif
    }

    /// 内置技能目录提供者（平台相关）：macOS 取 BuiltinSkills；
    /// iOS 工程不含 BuiltinSkills.swift，返回空（iOS 有自己的 MobileSkills）。
    static var defaultBuiltinProvider: @Sendable () -> [AgentSkill] {
#if os(macOS)
        return {
            BuiltinSkills.all.map {
                AgentSkill(name: $0.name, description: $0.description,
                           source: .builtin, content: $0.content)
            }
        }
#else
        return { [] }
#endif
    }

    private let globalDirectory: URL
    private let builtinProvider: @Sendable () -> [AgentSkill]

    // 锁保护的可变状态（store 非隔离，Runner 在主线程、工具在后台任务都会访问）
    private let lock = NSLock()
    private var _skills: [AgentSkill] = []
    private var _loadErrors: [String] = []
    private var _hasRefreshed = false
    private var _lastWorkspacePath: String? = nil

    init(
        globalDirectory: URL = AgentSkillStore.defaultGlobalDirectory,
        builtinProvider: @escaping @Sendable () -> [AgentSkill] = AgentSkillStore.defaultBuiltinProvider
    ) {
        self.globalDirectory  = globalDirectory
        self.builtinProvider  = builtinProvider
    }

    /// 当前目录快照（上次 refresh 的结果）
    var skills: [AgentSkill] {
        lock.lock(); defer { lock.unlock() }
        return _skills
    }

    /// 上次扫描跳过/失败的记录（供排查；坏文件不拖垮整体加载）
    var loadErrors: [String] {
        lock.lock(); defer { lock.unlock() }
        return _loadErrors
    }

    // MARK: - 刷新

    /// 全量重扫（每次 run 开始调用）。workspaceURL 为 nil 时只扫全局目录。
    func refresh(workspaceURL: URL?) {
        var errors: [String] = []
        let globalSkills = Self.scan(directory: globalDirectory, source: .global, errors: &errors)
        var workspaceSkills: [AgentSkill] = []
        if let workspaceURL {
            let dir = workspaceURL.appendingPathComponent(".meditor/skills", isDirectory: true)
            workspaceSkills = Self.scan(directory: dir, source: .workspace, errors: &errors)
        }

        // 合并：工作区级覆盖全局同名（大小写不敏感，APFS 默认大小写不敏感）
        var merged: [AgentSkill] = []
        var seen = Set<String>()
        for skill in workspaceSkills + globalSkills {
            let key = skill.name.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            merged.append(skill)
        }

        // 内置技能：同名用户技能优先并在目录标注；未覆盖的内置照常列出
        let builtins = builtinProvider()
        let builtinNames = Set(builtins.map { $0.name.lowercased() })
        for i in merged.indices where builtinNames.contains(merged[i].name.lowercased()) {
            merged[i].overridesBuiltin = true
        }
        merged.append(contentsOf: builtins.filter { !seen.contains($0.name.lowercased()) })

        lock.lock()
        _skills            = merged
        _loadErrors        = errors
        _hasRefreshed      = true
        _lastWorkspacePath = workspaceURL?.standardizedFileURL.path
        lock.unlock()
    }

    /// 惰性刷新：从未扫过或工作区变了才重扫（load_skill 在非 Runner 路径的兜底，
    /// 不替代 run 开始时的全量 refresh）。
    func refreshIfNeeded(workspaceURL: URL?) {
        lock.lock()
        let fresh = _hasRefreshed && _lastWorkspacePath == workspaceURL?.standardizedFileURL.path
        lock.unlock()
        if !fresh { refresh(workspaceURL: workspaceURL) }
    }

    // MARK: - 查询

    /// 按名查找（大小写不敏感）。名字只做内存目录匹配，不拼路径——无路径穿越面。
    func skill(named name: String) -> AgentSkill? {
        let key = name.lowercased()
        lock.lock(); defer { lock.unlock() }
        return _skills.first { $0.name.lowercased() == key }
    }

    /// 注入系统提示的技能目录段：只有 name + description + 来源标记，不含正文。
    /// 目录为空时返回 nil（调用方保证系统提示零改动）。
    func catalogPromptSection() -> String? {
        let skills = self.skills
        guard !skills.isEmpty else { return nil }
        var lines: [String] = [
            "",
            "",
            "---",
            "",
            "## Available Skills (load on demand)",
            "The following skills are available. Only names and descriptions are listed here; "
                + "when the task matches one, call the `load_skill` tool with its exact `name` "
                + "to load the full instructions before applying them.",
        ]
        for skill in skills {
            var tag: String
            switch skill.source {
            case .workspace: tag = "workspace"
            case .global:    tag = "user"
            case .builtin:   tag = "built-in"
            }
            if skill.overridesBuiltin { tag += ", overrides built-in" }
            let desc = skill.description.isEmpty ? "(no description)" : skill.description
            lines.append("- `\(skill.name)` — \(desc) [\(tag)]")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 扫描

    /// 扫描一个技能根目录：`<技能名>/SKILL.md`（目录型）与 `<技能名>.md`（平铺）两种布局。
    /// 坏文件跳过并记录到 errors，不中断其余技能的加载。
    private static func scan(
        directory: URL,
        source: AgentSkill.Source,
        errors: inout [String]
    ) -> [AgentSkill] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [AgentSkill] = []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            let skillFile: URL
            let skillDir: URL?
            let fallbackName: String
            if isDir {
                skillDir    = entry
                skillFile   = entry.appendingPathComponent("SKILL.md")
                fallbackName = entry.lastPathComponent
                // 目录里没有 SKILL.md 的不算技能，静默跳过（不是坏文件）
                guard fm.fileExists(atPath: skillFile.path) else { continue }
            } else {
                guard entry.pathExtension.lowercased() == "md" else { continue }
                skillDir    = nil
                skillFile   = entry
                fallbackName = entry.deletingPathExtension().lastPathComponent
            }

            if let size = try? skillFile.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size > maxSkillFileBytes {
                errors.append("\(skillFile.path)：超过 \(maxSkillFileBytes / 1024) KB 上限，已跳过")
                continue
            }
            guard let data = try? Data(contentsOf: skillFile), !data.isEmpty,
                  let content = String(data: data, encoding: .utf8),
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errors.append("\(skillFile.path)：空文件或非 UTF-8 文本，已跳过")
                continue
            }
            guard let parsed = parseSkillDocument(content: content, fallbackName: fallbackName) else {
                errors.append("\(skillFile.path)：技能名不合法，已跳过")
                continue
            }
            let attachments = skillDir.map { listAttachments(skillDir: $0) } ?? []
            found.append(AgentSkill(
                name: parsed.name, description: parsed.description, version: parsed.version,
                source: source, fileURL: skillFile, directoryURL: skillDir,
                content: content, attachments: attachments
            ))
        }
        return found
    }

    /// 列出技能目录内的附属文件（相对路径，不含 SKILL.md 本身；不读内容）。
    /// 递归枚举但跳过隐藏文件/包内容，条数封顶防呆。
    private static func listAttachments(skillDir: URL) -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: skillDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        let rootPath = skillDir.resolvingSymlinksInPath().path   // 枚举结果已解析符号链接（/var → /private/var），两侧口径须一致
        var rels: [String] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let path = url.resolvingSymlinksInPath().path
            // 只排除技能根部的 SKILL.md；子目录里的同名文件算附属文件
            if url.lastPathComponent == "SKILL.md",
               url.deletingLastPathComponent().resolvingSymlinksInPath().path == rootPath { continue }
            var rel = path
            if rel.hasPrefix(rootPath + "/") { rel = String(rel.dropFirst(rootPath.count + 1)) }
            rels.append(rel)
            if rels.count >= maxAttachments { break }
        }
        return rels.sorted()
    }

    // MARK: - SKILL.md 解析

    /// 解析技能文档：frontmatter（name/description/version）优先；
    /// 无 frontmatter 或缺字段时回退——name 用文件名/目录名，description 用正文首个内容行。
    /// frontmatter 规则与 SkillTransfer/PluginManager 对齐（首个 `---` 块、`key: value` 行、
    /// 值两侧引号剥离、容忍 CRLF）；SkillTransfer 不在 iOS 工程内，这里保留一份小实现，
    /// 避免共享文件反向依赖 macOS-only 类型。坏 YAML（未闭合的 ---、乱行）不报错，
    /// 按「无 frontmatter / 缺字段」的语义回退。
    static func parseSkillDocument(
        content: String,
        fallbackName: String
    ) -> (name: String, description: String, version: String?)? {
        var name = fallbackName
        var description = ""
        var version: String? = nil
        var body = content
        if let (frontMatter, rest) = splitFrontMatter(content) {
            if let v = frontMatterValue("name", in: frontMatter), !v.isEmpty { name = v }
            if let v = frontMatterValue("description", in: frontMatter), !v.isEmpty { description = v }
            if let v = frontMatterValue("version", in: frontMatter), !v.isEmpty { version = v }
            body = rest
        }
        if description.isEmpty { description = firstContentLine(body) }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidSkillName(name) else { return nil }
        return (name, description, version)
    }

    /// 技能名必须是单段纯文本：非空、≤100 字符、无路径分隔符/控制字符/换行、
    /// 不是 `.`/`..`、不以 `.` 开头（规则与 SkillTransfer.isSafeFolderName 对齐）。
    static func isValidSkillName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 100 else { return false }
        guard name != ".", name != "..", !name.hasPrefix(".") else { return false }
        let illegal = CharacterSet(charactersIn: "/\\:").union(.controlCharacters).union(.newlines)
        return name.rangeOfCharacter(from: illegal) == nil
    }

    /// 正文首个内容行作为 description 回退：跳过空行与 `---`，剥掉标题的 `#` 前缀，限长 120。
    private static func firstContentLine(_ body: String) -> String {
        for line in body.components(separatedBy: "\n") {
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed == "---" { continue }
            while trimmed.hasPrefix("#") { trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces) }
            if trimmed.isEmpty { continue }
            return trimmed.count > 120 ? String(trimmed.prefix(120)) : trimmed
        }
        return ""
    }

    /// 切出 `---` frontmatter 与正文；没有（或未闭合）frontmatter 返回 nil。
    private static func splitFrontMatter(_ content: String) -> (frontMatter: String, body: String)? {
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
    private static func frontMatterValue(_ key: String, in frontMatter: String) -> String? {
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
