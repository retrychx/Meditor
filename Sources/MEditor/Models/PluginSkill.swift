import Foundation

enum SkillSource: String, Codable {
    case builtin  // 内置，随 App 发布
    case manual   // 用户手动添加
}

// MARK: - Skill Command (from SKILL.md commands: section)

struct SkillCommand: Identifiable, Codable, Sendable {
    var id: String { name }
    var name: String          // internal name
    var trigger: String       // button label shown in UI
    var icon: String          // SF Symbol name
    var description: String
    /// Which builtin tool names this command is allowed to use. Empty = all.
    var allowedTools: [String]

    init(name: String, trigger: String, icon: String = "sparkles",
         description: String = "", allowedTools: [String] = []) {
        self.name = name
        self.trigger = trigger
        self.icon = icon
        self.description = description
        self.allowedTools = allowedTools
    }
}

struct PluginSkill: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let skillPath: URL
    var isEnabled: Bool
    var source: SkillSource
    /// Commands defined in SKILL.md (commands: section). Empty for builtin skills.
    var commands: [SkillCommand]

    init(id: String, name: String, description: String,
         skillPath: URL, isEnabled: Bool, source: SkillSource = .manual,
         commands: [SkillCommand] = []) {
        self.id = id
        self.name = name
        self.description = description
        self.skillPath = skillPath
        self.isEnabled = isEnabled
        self.source = source
        self.commands = commands
    }

    // Custom decoder: `source` / `commands` may be absent in legacy data → use defaults
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(String.self,      forKey: .id)
        name        = try c.decode(String.self,      forKey: .name)
        description = try c.decode(String.self,      forKey: .description)
        skillPath   = try c.decode(URL.self,         forKey: .skillPath)
        isEnabled   = try c.decode(Bool.self,        forKey: .isEnabled)
        source      = (try? c.decode(SkillSource.self, forKey: .source)) ?? .manual
        commands    = (try? c.decode([SkillCommand].self, forKey: .commands)) ?? []
    }
}

// MARK: - Persisted state

struct PluginSkillState: Codable {
    let id: String
    var isEnabled: Bool
}

// MARK: - Manual entry (user-added paths, persisted)

struct ManualSkillEntry: Codable {
    let id: String
    let pathBookmark: Data  // security-scoped bookmark
    var isEnabled: Bool
}
