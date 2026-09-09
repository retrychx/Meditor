import Foundation

// MARK: - Load Skill（渐进披露：按名加载技能全文）

/// 按需加载技能正文的工具。系统提示里只有技能目录（name + description + 来源），
/// 模型判断任务命中某个技能后调本工具拉取全文；目录型技能的附属文件（脚本/模板）
/// 只列出相对路径清单与绝对路径，模型用 read_file 按需读取——不为每个技能预支上下文。
struct LoadSkillTool: AgentTool {
    let spec = AgentToolSpec(
        name: "load_skill",
        description: "Load the full instructions of a skill from the Available Skills catalog by name. Returns the skill body plus a list of its bundled files (scripts/templates) with absolute paths — read those with read_file when the skill references them.",
        parameters: ToolParameterSchema(
            properties: [
                (key: "name", schema: ToolPropertySchema(
                    type: "string",
                    description: "Skill name exactly as listed in the Available Skills catalog."
                ))
            ],
            required: ["name"]
        )
    )

    private let store: AgentSkillStore

    init(store: AgentSkillStore = .shared) {
        self.store = store
    }

    func execute(arguments: [String: AnySendableValue], context: any AgentContextProtocol) async throws -> String {
        guard let raw = arguments["name"]?.stringValue else {
            throw AgentError.executionError("缺少 name 参数")
        }
        // 兜底刷新：正常路径下 Runner 已在 run 开始时 refresh；这里只在「从未扫过
        // 或工作区变了」时重扫，保证非 Runner 路径（如直接使用工具）也能拿到目录。
        store.refreshIfNeeded(workspaceURL: await context.workspaceURL)

        // 名字清洗：技能名只允许单段纯文本（查找只命中内存目录、不拼路径，
        // 这里再挡一层路径分隔符/穿越片段，双保险防路径穿越）。
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AgentSkillStore.isValidSkillName(name) else {
            return "[!] 无效的技能名：\(raw)。请使用系统提示技能目录里列出的 name 原样调用。"
        }
        guard let skill = store.skill(named: name) else {
            let available = store.skills.map(\.name).joined(separator: ", ")
            if available.isEmpty {
                return "[!] 未找到技能「\(name)」：当前没有任何可用技能。"
            }
            return "[!] 未找到技能「\(name)」。可用技能：\(available)。请使用目录中的 name 原样调用。"
        }
        return render(skill)
    }

    /// 组织返回给模型的技能全文：正文（经提示注入轻净化，与 read_file 同一防护级别）
    /// + 目录型技能的 SKILL_DIR 与附属文件清单（只列路径，不读内容）。
    private func render(_ skill: AgentSkill) -> String {
        var out = "# Skill: \(skill.name)\n"
        if let dir = skill.directoryURL {
            // 注入 SKILL_DIR 绝对路径（同 PluginManager.userSkillsPrompt 的思路）：
            // 否则模型看到正文里的相对路径/脚本名无法解析，会去工作区瞎搜。
            out += "\nSKILL_DIR = \(dir.path)"
            out += "\n（本技能目录的绝对路径。正文与下方附属文件中的相对路径都以此目录为根；用 read_file 读取附属文件时传拼接后的绝对路径。）\n"
        }
        let (safeContent, flagged) = PromptInjectionSanitizer.sanitize(skill.content)
        out += "\n" + PromptInjectionSanitizer.guardrailNote(flagged: flagged) + safeContent
        if !skill.attachments.isEmpty, let dir = skill.directoryURL {
            out += "\n\n## 附属文件（仅列出路径，未加载内容；按需用 read_file 读取）"
            for rel in skill.attachments {
                out += "\n- \(rel) → \(dir.appendingPathComponent(rel).path)"
            }
        }
        return out
    }
}
