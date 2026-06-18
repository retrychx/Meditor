import Foundation

enum SkillSource: String, Codable {
    case builtin  // 内置，随 App 发布
    case manual   // 用户手动添加
}

struct PluginSkill: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let skillPath: URL
    var isEnabled: Bool
    var source: SkillSource

    init(id: String, name: String, description: String,
         skillPath: URL, isEnabled: Bool, source: SkillSource = .manual) {
        self.id = id
        self.name = name
        self.description = description
        self.skillPath = skillPath
        self.isEnabled = isEnabled
        self.source = source
    }

    // Custom decoder: `source` may be absent in legacy data → default to .manual
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(String.self,      forKey: .id)
        name        = try c.decode(String.self,      forKey: .name)
        description = try c.decode(String.self,      forKey: .description)
        skillPath   = try c.decode(URL.self,         forKey: .skillPath)
        isEnabled   = try c.decode(Bool.self,        forKey: .isEnabled)
        source      = (try? c.decode(SkillSource.self, forKey: .source)) ?? .manual
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
