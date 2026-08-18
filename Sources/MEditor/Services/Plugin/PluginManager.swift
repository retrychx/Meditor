import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
final class PluginManager {

    // MARK: - State

    var skills: [PluginSkill] = []
    /// SKILL.md 解析失败的错误描述（用于 UI 展示警告）
    var loadErrors: [String] = []

    // MARK: - Persistence keys

    private enum Key {
        static let states  = "MEditor.pluginSkillStates"
        static let manual  = "MEditor.pluginManualSkills"
    }

    // MARK: - Manual add / remove

    @discardableResult
    func addManual(skillMDURL rawURL: URL) -> Bool {
        // 支持两种选择：① skill 文件夹（其中含 SKILL.md）② SKILL.md 文件本身
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: rawURL.path, isDirectory: &isDir)

        let skillMD: URL          // 实际的 SKILL.md
        let bookmarkTarget: URL   // 对 skill 根目录建书签，便于将来访问目录内 references/scripts
        if isDir.boolValue {
            skillMD = rawURL.appendingPathComponent("SKILL.md")
            guard FileManager.default.fileExists(atPath: skillMD.path) else { return false }
            bookmarkTarget = rawURL
        } else {
            guard rawURL.lastPathComponent == "SKILL.md" else { return false }
            skillMD = rawURL
            bookmarkTarget = rawURL.deletingLastPathComponent()
        }

        let id = persistentID(for: skillMD)
        guard !skills.contains(where: { $0.id == id }) else { return false }

        // 非沙盒应用：用普通书签即可。security-scoped 书签需要 sandbox entitlement，
        // 本 app 没有，会创建/解析失败导致技能加载不出来。
        guard let bookmark = try? bookmarkTarget.bookmarkData() else { return false }
        var entries = loadManualEntries()
        entries.append(ManualSkillEntry(id: id, pathBookmark: bookmark, isEnabled: true))
        saveManualEntries(entries)

        Task { await reloadAll() }
        return true
    }

    /// 从用户选择的 URL 发现并添加 skill，返回成功添加的数量：
    /// - 选中 SKILL.md 文件 → 添加它
    /// - 选中"单 skill 目录"（直接含 SKILL.md）→ 添加
    /// - 选中"插件目录"（含 `skills/<name>/SKILL.md`）→ 添加其中所有 skill
    @discardableResult
    func addSkills(from url: URL) -> Int {
        var added = 0
        for md in discoverSkillMDs(in: url) where addManual(skillMDURL: md) {
            added += 1
        }
        return added
    }

    private func discoverSkillMDs(in url: URL) -> [URL] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return [] }

        if !isDir.boolValue {
            return url.lastPathComponent == "SKILL.md" ? [url] : []
        }
        // ① 目录直接含 SKILL.md（单 skill 目录）
        let direct = url.appendingPathComponent("SKILL.md")
        if fm.fileExists(atPath: direct.path) { return [direct] }

        // ② 插件结构：<url>/skills/<name>/SKILL.md
        let skillsDir = url.appendingPathComponent("skills")
        guard let subs = try? fm.contentsOfDirectory(
            at: skillsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return subs.compactMap { sub -> URL? in
            var subIsDir: ObjCBool = false
            guard fm.fileExists(atPath: sub.path, isDirectory: &subIsDir), subIsDir.boolValue else { return nil }
            let md = sub.appendingPathComponent("SKILL.md")
            return fm.fileExists(atPath: md.path) ? md : nil
        }
    }

    func remove(id: String) {
        guard skills.first(where: { $0.id == id })?.source != .builtin else { return }
        skills.removeAll { $0.id == id }
        var entries = loadManualEntries()
        entries.removeAll { $0.id == id }
        saveManualEntries(entries)
        persistStates()
    }

    func setEnabled(_ id: String, enabled: Bool) {
        guard let idx = skills.firstIndex(where: { $0.id == id }) else { return }
        skills[idx].isEnabled = enabled
        persistStates()

        if skills[idx].source == .manual {
            var entries = loadManualEntries()
            if let entryIdx = entries.firstIndex(where: { $0.id == id }) {
                entries[entryIdx].isEnabled = enabled
                saveManualEntries(entries)
            }
        }
    }

    // MARK: - Prompt injection

    /// 查询某个内置 skill 是否已启用
    func isBuiltinEnabled(_ id: String) -> Bool {
        skills.first { $0.id == id }?.isEnabled ?? true
    }

    /// 返回用户手动添加的已启用 skill 的 prompt（不含内置）
    func userSkillsPrompt() -> String {
        skills
            .filter { $0.source == .manual && $0.isEnabled }
            .compactMap { skill -> String? in
                guard let content = try? String(contentsOf: skill.skillPath, encoding: .utf8) else { return nil }
                let skillDir = skill.skillPath.deletingLastPathComponent().path
                // 注入 SKILL_DIR 绝对路径：技能脚本/资源都在此目录下。
                // 否则 AI 看到 SKILL.md 里的相对路径/占位符无法解析，会去工作区瞎搜脚本。
                let header = """
                ## User Skill: \(skill.name)

                SKILL_DIR = \(skillDir)
                （这是本技能的安装目录绝对路径。SKILL.md 中出现的 SKILL_DIR、脚本或资源相对路径，
                都以此目录为根解析。用 run_command 执行本技能脚本时，命令里的路径请拼成
                \(skillDir)/… 的绝对路径，并把 cwd 设为该目录，不要在工作区里搜索脚本。）

                """
                return header + content
            }
            .joined(separator: "\n\n---\n\n")
    }

    func enabledSkillsPrompt() -> String {
        skills
            .filter { $0.isEnabled }
            .compactMap { skill -> String? in
                if skill.source == .builtin {
                    guard let item = BuiltinSkills.all.first(where: { $0.id == skill.id }) else { return nil }
                    return "## Skill: \(skill.name)\n\n\(item.content)"
                } else {
                    guard let content = try? String(contentsOf: skill.skillPath, encoding: .utf8) else { return nil }
                    return "## Skill: \(skill.name)\n\n\(content)"
                }
            }
            .joined(separator: "\n\n---\n\n")
    }

    // MARK: - Persistence

    func save() { persistStates() }

    func load() {
        Task {
            await reloadAll()
        }
    }

    /// 重新加载手动技能 + 内置技能（可被测试 await）。
    func reloadAll() async {
        await loadManual()
        loadBuiltins()
    }

    // MARK: - Private helpers

    private func loadBuiltins() {
        let states = loadStates()
        let builtins = BuiltinSkills.all.map { def in
            PluginSkill(
                id:          def.id,
                name:        def.name,
                description: def.description,
                skillPath:   URL(fileURLWithPath: "/builtin/\(def.id)"),
                isEnabled:   states[def.id] ?? true,
                source:      .builtin,
                commands:    def.commands
            )
        }
        // Builtins go first; existing manual skills follow
        skills = builtins + skills.filter { $0.source == .manual }
    }

    private func loadManual() async {
        let states = loadStates()
        var found:  [PluginSkill] = []
        var errors: [String]      = []
        for entry in loadManualEntries() {
            if let url = resolveBookmark(entry.pathBookmark) {
                // 书签可能指向 skill 根目录（新）或 SKILL.md 文件（旧），统一解析出 SKILL.md
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                let skillMD = isDir.boolValue ? url.appendingPathComponent("SKILL.md") : url
                let isEnabled = states[entry.id] ?? entry.isEnabled
                if let skill = await parseSkill(at: skillMD, id: entry.id, isEnabled: isEnabled) {
                    found.append(skill)
                } else {
                    let path = skillMD.path
                    errors.append("\(skillMD.deletingLastPathComponent().lastPathComponent): 无法解析 SKILL.md（\(path)）")
                }
            } else {
                errors.append("ID \(entry.id): 书签失效，请重新添加技能")
            }
        }
        skills     = found
        loadErrors = errors
    }

    private func parseSkill(at url: URL, id: String, isEnabled: Bool) async -> PluginSkill? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let name = url.deletingLastPathComponent().lastPathComponent
        let description = extractDescription(from: content)
        let commands = extractCommands(from: content)
        return PluginSkill(id: id, name: name, description: description,
                           skillPath: url, isEnabled: isEnabled, source: .manual,
                           commands: commands)
    }

    private func extractCommands(from content: String) -> [SkillCommand] {
        // Parse YAML front-matter for a commands: list
        // Format:
        // commands:
        //   - name: seo_optimize
        //     trigger: "SEO 优化"
        //     icon: magnifyingglass
        //     description: ...
        //     tools: [read_document, write_document]
        var commands: [SkillCommand] = []
        guard let frontMatter = extractFrontMatter(from: content) else { return commands }

        let lines = frontMatter.components(separatedBy: "\n")
        var inCommands = false
        var currentCmd: [String: String] = [:]
        var currentTools: [String]    = []
        var currentAllowedCmds: [String] = []
        /// tracks which inline list is being filled: "tools" or "allowedCommands"
        var currentListKey: String? = nil

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "commands:" { inCommands = true; continue }
            if inCommands {
                // 缩进层级区分结构（必须看原始行的前导空白，不能看 trimmed）：
                //   "  - name:"      → 新命令条目（2 格）
                //   "    trigger:"   → 条目字段（4 格）
                //   "      - git …"  → 字段的多行列表项（6 格）
                let leadingSpaces = line.prefix(while: { $0 == " " }).count
                let insideEntry = leadingSpaces >= 4 || line.hasPrefix("\t")
                if (trimmed.hasPrefix("- ") || trimmed.hasPrefix("-\t")) && !insideEntry {
                    // New command entry — flush previous
                    if !currentCmd.isEmpty {
                        commands.append(makeCommand(from: currentCmd,
                                                    tools: currentTools,
                                                    allowedCommands: currentAllowedCmds))
                    }
                    currentCmd = [:]; currentTools = []; currentAllowedCmds = []; currentListKey = nil
                    let rest = String(trimmed.dropFirst(2))
                    if let kv = parseYAMLLine(rest) { currentCmd[kv.0] = kv.1 }
                } else if insideEntry {
                    let inner = trimmed.trimmingCharacters(in: .whitespaces)

                    if inner.hasPrefix("tools:") {
                        currentListKey = "tools"
                        let inline = inner.dropFirst("tools:".count).trimmingCharacters(in: .whitespaces)
                        if !inline.isEmpty {
                            currentTools = parseInlineList(inline)
                            currentListKey = nil   // inline list completed on same line
                        }
                    } else if inner.hasPrefix("allowedCommands:") {
                        currentListKey = "allowedCommands"
                        let inline = inner.dropFirst("allowedCommands:".count).trimmingCharacters(in: .whitespaces)
                        if !inline.isEmpty {
                            currentAllowedCmds = parseInlineList(inline)
                            currentListKey = nil
                        }
                    } else if inner.hasPrefix("- ") || inner.hasPrefix("-\t") {
                        // Multi-line list item
                        let item = String(inner.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                        switch currentListKey {
                        case "tools":           currentTools.append(item)
                        case "allowedCommands": currentAllowedCmds.append(item)
                        default: break
                        }
                    } else {
                        currentListKey = nil
                        if let kv = parseYAMLLine(inner) { currentCmd[kv.0] = kv.1 }
                    }
                } else {
                    // End of commands block
                    break
                }
            }
        }
        if !currentCmd.isEmpty {
            commands.append(makeCommand(from: currentCmd,
                                        tools: currentTools,
                                        allowedCommands: currentAllowedCmds))
        }
        return commands
    }

    private func makeCommand(from dict: [String: String],
                              tools: [String],
                              allowedCommands: [String]) -> SkillCommand {
        SkillCommand(
            name:            dict["name"]    ?? "command",
            trigger:         dict["trigger"] ?? dict["name"] ?? "操作",
            icon:            dict["icon"]    ?? "sparkles",
            description:     dict["description"] ?? "",
            allowedTools:    tools,
            allowedCommands: allowedCommands
        )
    }

    /// 解析内联 YAML 列表：`[git log, git status]` 或裸逗号分隔值
    private func parseInlineList(_ raw: String) -> [String] {
        let cleaned = raw.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return cleaned.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func parseYAMLLine(_ line: String) -> (String, String)? {
        let parts = line.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let key = parts[0].trimmingCharacters(in: .whitespaces)
        let value = parts[1].trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"\'" ))
        return (key, value)
    }

    private func extractFrontMatter(from content: String) -> String? {
        guard content.hasPrefix("---") else { return nil }
        let lines = content.components(separatedBy: "\n")
        var end = -1
        for (i, line) in lines.dropFirst().enumerated() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { end = i + 1; break }
        }
        guard end > 0 else { return nil }
        return lines[1..<end].joined(separator: "\n")
    }

    private func extractDescription(from content: String) -> String {
        let lines = content.components(separatedBy: "\n")

        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            for line in lines.dropFirst() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed == "---" { break }
                if trimmed.lowercased().hasPrefix("description:") {
                    let value = trimmed.dropFirst("description:".count).trimmingCharacters(in: .whitespaces)
                    if !value.isEmpty { return value }
                }
            }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !trimmed.hasPrefix("#") && !trimmed.hasPrefix("---") {
                return String(trimmed.prefix(120))
            }
        }
        return ""
    }

    /// 跨启动稳定的技能 ID：SHA256(标准化路径) 的前 16 个 hex 字符。
    /// 旧实现用 Swift Hasher（进程级随机种子），跨启动去重失效导致技能重复。
    private func persistentID(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }

    private func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        // 非沙盒应用：普通书签解析，不使用 .withSecurityScope（否则解析普通书签会失败）
        return try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    // MARK: - UserDefaults I/O

    private func loadStates() -> [String: Bool] {
        guard let data = UserDefaults.standard.data(forKey: Key.states),
              let decoded = try? JSONDecoder().decode([PluginSkillState].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0.isEnabled) })
    }

    private func persistStates() {
        let states = skills.map { PluginSkillState(id: $0.id, isEnabled: $0.isEnabled) }
        if let data = try? JSONEncoder().encode(states) {
            UserDefaults.standard.set(data, forKey: Key.states)
        }
    }

    private func loadManualEntries() -> [ManualSkillEntry] {
        guard let data = UserDefaults.standard.data(forKey: Key.manual),
              let decoded = try? JSONDecoder().decode([ManualSkillEntry].self, from: data)
        else { return [] }
        return decoded
    }

    private func saveManualEntries(_ entries: [ManualSkillEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Key.manual)
        }
    }
}
