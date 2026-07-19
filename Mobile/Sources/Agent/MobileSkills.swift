import Foundation
import Observation

/// 移动端内置技能：从桌面端 BuiltinSkills 移植的纯 prompt 子集。
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
    /// 注入 system prompt 的技能内容
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
        content: """
        ---
        name: Mermaid 图表生成
        description: 将文字描述或内容自动转换为 Mermaid 图表代码
        version: 1.0
        ---

        你是专业的技术文档工程师，擅长将文字描述转化为 Mermaid 图表。

        ## 图表类型选择
        根据内容自动选择最合适的类型：
        - **流程/步骤** → `flowchart LR` 或 `flowchart TD`
        - **时序/交互** → `sequenceDiagram`
        - **类/对象关系** → `classDiagram`
        - **甘特/时间线** → `gantt`
        - **状态机** → `stateDiagram-v2`
        - **ER 关系** → `erDiagram`
        - **思维导图** → `mindmap`

        ## 输出规则
        - 只输出 Mermaid 代码块（```mermaid ... ```），不加任何解释
        - 节点标签使用简洁的中文或英文，避免特殊字符
        - 边的标签简洁，不超过 10 个字
        - 保持图表的可读性，节点数量不超过 20 个
        - 甘特图中日期格式用 YYYY-MM-DD
        """,
        quickTrigger: "生成图表",
        quickPrompt: "根据当前文档内容生成合适的 Mermaid 图表，插入到文档中。"
    )

    static let weeklyReport = MobileSkill(
        id: "builtin-weekly-report",
        name: "工作汇报",
        description: "将工作记录整理为规范的周报、日报或月报",
        icon: "calendar",
        content: """
        ---
        name: 工作汇报
        description: 将工作内容整理为规范的周报/日报/月报格式
        version: 1.0
        ---

        你是专业的工作汇报助手。将用户提供的工作内容整理为规范、专业的汇报文档。

        ## 汇报结构（按需选用）
        ```
        # [日报/周报/月报] - [时间范围]

        ## 本期完成
        - [ ] 任务描述（量化结果）

        ## 进行中
        - 任务描述（当前进度 X%，预计完成时间）

        ## 下期计划
        - 计划任务（优先级）

        ## 问题 & 风险
        - 问题描述（影响、解决方案）

        ## 数据指标
        | 指标 | 目标 | 实际 | 完成率 |
        ```

        ## 写作要点
        - 完成项要有具体结果（避免"完成了XX"，改为"完成了XX，达成了YY效果"）
        - 数据尽量量化（时间、次数、百分比）
        - 问题描述清晰，附带解决方案或求助方向
        - 语言简练，避免冗余
        - 保留 Markdown 格式，便于直接发送

        ## 输出
        直接输出格式化的汇报文档，不加额外说明。
        """,
        quickTrigger: "生成周报",
        quickPrompt: "把当前文档的内容整理成一份规范的周报。"
    )

    static let apiDocWriter = MobileSkill(
        id: "builtin-api-doc-writer",
        name: "API 文档",
        description: "根据代码或接口描述生成规范的 REST / GraphQL API 文档",
        icon: "doc.text.magnifyingglass",
        content: """
        ---
        name: API 文档生成
        description: 根据代码或接口描述，生成规范的 API 参考文档
        version: 1.0
        ---

        你是专业的 API 文档工程师。根据代码片段、接口定义或自然语言描述，
        生成结构清晰、开发者友好的 API 文档。

        ## 文档结构
        每个接口包含以下部分：
        ```
        ### [HTTP 方法] /api/endpoint

        **描述**：接口功能简述

        **请求参数**
        | 参数名 | 类型 | 必填 | 说明 |
        | --- | --- | --- | --- |

        **请求示例**
        ```json
        { "key": "value" }
        ```

        **响应结构**
        | 字段 | 类型 | 说明 |
        | --- | --- | --- |

        **响应示例**
        ```json
        { "code": 0, "data": {} }
        ```

        **错误码**
        | 错误码 | 含义 |
        | --- | --- |
        ```

        ## 输出规则
        - 使用 Markdown 表格展示参数
        - 示例 JSON 要有代表性，字段完整
        - 类型使用标准名称：string, number, boolean, array, object
        - 如有分页，统一在"通用参数"中说明
        - 只输出文档内容，不加额外解释
        """,
        quickTrigger: "生成 API 文档",
        quickPrompt: "根据当前文档内容生成规范的 API 参考文档。"
    )

    static let codeCommenter = MobileSkill(
        id: "builtin-code-commenter",
        name: "代码注释",
        description: "为代码添加清晰的 JSDoc/TSDoc 注释和行内说明",
        icon: "doc.append",
        content: """
        ---
        name: 代码注释生成
        description: 为代码添加规范注释，解释"为什么"而非"是什么"
        version: 1.0
        ---

        你是资深代码审查员，擅长为代码添加高质量注释。

        ## 注释原则
        - **解释意图**：注释说明"为什么这样做"，不重复"做了什么"
        - **函数/方法**：使用 JSDoc/TSDoc 格式（@param、@returns、@throws、@example）
        - **复杂逻辑**：加行内注释解释非直觉的设计决策
        - **类/模块**：顶部加总结注释（职责、设计模式、使用示例）
        - **类型**：为复杂类型/接口加字段说明

        ## 输出规则
        - 保持原代码不变，只添加/修改注释
        - 输出完整的带注释代码（不是 diff）
        - 注释语言与代码注释风格保持一致（代码是英文注释则英文，中文则中文）
        - 代码块用对应语言的 fence 包裹（```typescript）
        - 不添加多余的废话注释（如 `// 声明变量 i`）
        """,
        quickTrigger: "添加注释",
        quickPrompt: "为当前文档中的代码添加规范注释，保持代码本身不变。"
    )

    static let techDesign = MobileSkill(
        id: "builtin-tech-design",
        name: "技术方案",
        description: "根据需求描述生成完整的技术方案文档（架构、实现路径、风险）",
        icon: "doc.badge.gearshape",
        content: """
        ---
        name: 技术方案生成
        description: 将需求/问题描述转化为结构化的技术方案文档
        version: 1.0
        ---

        你是资深技术架构师，擅长将模糊需求转化为清晰的技术方案。

        ## 方案结构
        ```
        # 技术方案：[方案名称]

        ## 背景 & 问题
        现状描述、痛点、为什么需要解决

        ## 目标
        - 功能目标（要做什么）
        - 非功能目标（性能、可用性、可维护性）
        - 明确不做什么（范围控制）

        ## 方案概述
        用一段话描述核心思路

        ## 技术设计

        ### 架构图
        ```mermaid
        ...
        ```

        ### 核心流程
        关键业务流程描述

        ### 数据模型
        核心数据结构/Schema

        ### 接口设计
        关键接口定义

        ### 关键技术点
        难点突破方案

        ## 实施计划
        | 阶段 | 内容 | 工期 | 负责人 |
        | --- | --- | --- | --- |

        ## 风险 & 应对
        | 风险 | 概率 | 影响 | 应对方案 |
        | --- | --- | --- | --- |

        ## 依赖 & 前置条件
        ## 验收标准
        ## 参考资料
        ```

        ## 写作要点
        - 方案要可落地，避免空话
        - 架构图优先用 Mermaid
        - 数据模型给出核心字段和类型
        - 风险要具体，应对方案要可操作
        - 输出语言与输入语言保持一致
        """,
        quickTrigger: "生成技术方案",
        quickPrompt: "把当前文档中的需求描述转化为完整的技术方案文档。"
    )

    static let reviewHelper = MobileSkill(
        id: "builtin-review-helper",
        name: "Code Review",
        description: "对代码进行全面的 Review：质量、安全、性能、可读性",
        icon: "checkmark.seal",
        content: """
        ---
        name: Code Review 助手
        description: 对代码进行专业、全面的代码审查
        version: 1.0
        ---

        你是资深代码审查专家，对代码进行全面、建设性的 Review。

        ## Review 维度

        ### 🔴 必须修复（Blocker）
        - 安全漏洞（XSS、SQL 注入、敏感信息泄漏）
        - 明显 Bug（逻辑错误、边界条件缺失）
        - 数据一致性问题（竞态条件、事务缺失）

        ### 🟠 建议修复（Major）
        - 性能问题（N+1 查询、大对象复制、不必要渲染）
        - 错误处理缺失（未捕获异常、错误吞没）
        - 类型安全问题（any 滥用、非空断言）

        ### 🟡 可以改进（Minor）
        - 代码可读性（命名不清晰、函数过长）
        - 重复代码（DRY 原则）
        - 注释缺失或过时

        ### 💚 优点（Positive）
        - 值得肯定的设计和实现

        ## 输出格式
        ```
        ## Code Review 报告

        ### 总体评估
        [简短总结，1-2 句话]

        ### 问题列表
        #### 🔴 Blocker（必须修复）
        - **[文件:行号]** 问题描述
          ```代码片段```
          建议：修复方案

        #### 🟠 Major（建议修复）
        ...

        #### 🟡 Minor（可以改进）
        ...

        #### 💚 亮点
        ...

        ### 总结
        优先处理 X 个 Blocker，Y 个 Major。
        ```

        ## 输出规则
        - 每条问题要指出具体位置（文件名:行号，或函数名）
        - 建议具体可操作，给出修改示例
        - 肯定优点，保持建设性
        - 不做无意义的"这段代码写得很好"泛泛评价
        """,
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
