import Foundation
import Observation

/// 移动端内置技能：桌面端 BuiltinSkills 的纯 prompt 子集。
///
/// prompt 正文统一来自共享层 SharedSkillPrompts（与桌面端同源，勿再复制文本）；
/// 本文件只保留移动端平台壳：chip 图标、quickTrigger / quickPrompt。
///
/// 与桌面版的差异：
/// - 不含绑定桌面 UI 的技能（美化 → BeautifySheet、内联编辑 → 编辑器选区）；
/// - 手动导入 SKILL.md 不在本期范围（iOS 无 shell，脚本类技能跑不了）。
///
/// 技能内容即注入 system prompt 的文本，每个技能带一条快捷指令，
/// 在 AI 输入栏上方以 chip 形式一键触发。
struct MobileSkill: Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    /// 快捷指令 chip 的 SF Symbol
    let icon: String
    /// 注入 system prompt 的技能内容（共享层 SharedSkillPrompts）
    let content: String
    /// 快捷指令：chip 标题 + 点击后直接发送的指令
    let quickTrigger: String
    let quickPrompt: String
}

// MARK: - 技能注册表

enum MobileSkills {

    static let mermaidDiagram = MobileSkill(
        id: "builtin-mermaid-diagram",
        name: "图表生成",
        description: "将文字描述转换为 Mermaid 图表（流程图、时序图、甘特图等）",
        icon: "chart.xyaxis.line",
        content: SharedSkillPrompts.mermaidDiagram,
        quickTrigger: "生成图表",
        quickPrompt: "根据当前文档内容生成合适的 Mermaid 图表，插入到文档中。"
    )

    static let weeklyReport = MobileSkill(
        id: "builtin-weekly-report",
        name: "工作汇报",
        description: "将工作记录整理为规范的周报、日报或月报",
        icon: "calendar",
        content: SharedSkillPrompts.weeklyReport,
        quickTrigger: "生成周报",
        quickPrompt: "把当前文档的内容整理成一份规范的周报。"
    )

    static let apiDocWriter = MobileSkill(
        id: "builtin-api-doc-writer",
        name: "API 文档",
        description: "根据代码或接口描述生成规范的 REST / GraphQL API 文档",
        icon: "doc.text.magnifyingglass",
        content: SharedSkillPrompts.apiDocWriter,
        quickTrigger: "生成 API 文档",
        quickPrompt: "根据当前文档内容生成规范的 API 参考文档。"
    )

    static let codeCommenter = MobileSkill(
        id: "builtin-code-commenter",
        name: "代码注释",
        description: "为代码添加清晰的 JSDoc/TSDoc 注释和行内说明",
        icon: "doc.append",
        content: SharedSkillPrompts.codeCommenter,
        quickTrigger: "添加注释",
        quickPrompt: "为当前文档中的代码添加规范注释，保持代码本身不变。"
    )

    static let techDesign = MobileSkill(
        id: "builtin-tech-design",
        name: "技术方案",
        description: "根据需求描述生成完整的技术方案文档（架构、实现路径、风险）",
        icon: "doc.badge.gearshape",
        content: SharedSkillPrompts.techDesign,
        quickTrigger: "生成技术方案",
        quickPrompt: "把当前文档中的需求描述转化为完整的技术方案文档。"
    )

    static let reviewHelper = MobileSkill(
        id: "builtin-review-helper",
        name: "Code Review",
        description: "对代码进行全面的 Review：质量、安全、性能、可读性",
        icon: "checkmark.seal",
        content: SharedSkillPrompts.reviewHelper,
        quickTrigger: "全面 Review",
        quickPrompt: "对当前文档中的代码进行全面 Code Review。"
    )

    /// 所有内置技能的有序列表（顺序影响设置页与 chips 展示顺序）。
    static let all: [MobileSkill] = [
        mermaidDiagram,
        weeklyReport,
        apiDocWriter,
        codeCommenter,
        techDesign,
        reviewHelper,
    ]
}

// MARK: - 启停状态

/// 技能启停：UserDefaults 持久化，默认全部启用。
/// 单例即可——设置页开关、AI 页 chips、ChatModel 注入三处共用。
@MainActor
@Observable
final class MobileSkillStore {

    static let shared = MobileSkillStore()

    private static let defaultsKey = "MEditor.mobileSkillStates"

    private var states: [String: Bool] {
        didSet { UserDefaults.standard.set(states, forKey: Self.defaultsKey) }
    }

    private init() {
        states = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: Bool] ?? [:]
    }

    func isEnabled(_ id: String) -> Bool { states[id] ?? true }

    func setEnabled(_ id: String, _ enabled: Bool) {
        states[id] = enabled
    }

    var enabledSkills: [MobileSkill] {
        MobileSkills.all.filter { isEnabled($0.id) }
    }

    /// 注入 system prompt 的技能段；无启用技能时为空串。
    var promptSection: String {
        let section = enabledSkills
            .map { "## Skill: \($0.name)\n\n\($0.content)" }
            .joined(separator: "\n\n---\n\n")
        guard !section.isEmpty else { return "" }
        return "用户已启用以下技能，当用户请求与之相关时严格遵循对应技能的规则：\n\n" + section
    }
}
