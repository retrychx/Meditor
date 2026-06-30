import Foundation

// MARK: - BuiltinSkillDef

/// 内置 Skill 的完整定义。
/// 使用结构体而非元组，以便携带 commands 字段（与 PluginSkill 对齐）。
struct BuiltinSkillDef: Sendable {
    let id:          String
    let name:        String
    let description: String
    let content:     String
    /// 工具按钮（与 SkillCommand 格式一致），显示在 Settings → Skills 的快捷操作区。
    let commands:    [SkillCommand]

    init(
        id:          String,
        name:        String,
        description: String,
        content:     String,
        commands:    [SkillCommand] = []
    ) {
        self.id          = id
        self.name        = name
        self.description = description
        self.content     = content
        self.commands    = commands
    }
}

// MARK: - BuiltinSkills

/// 内置 skill 注册表。内容镜像 SKILL.md 结构，随 App 发布，始终可用。
///
/// ## 扩展方式
/// 1. 在 `BuiltinSkills.ID` 里添加新 ID 常量。
/// 2. 添加对应的 `static var xxx: BuiltinSkillDef { ... }` 属性。
/// 3. 将其加入 `all` 数组（注意顺序影响 Settings 列表展示顺序）。
enum BuiltinSkills {

    // MARK: - ID 常量

    enum ID {
        static let htmlBeautifier  = "builtin-html-beautifier"
        static let inlineEditor    = "builtin-inline-editor"
        static let mermaidDiagram  = "builtin-mermaid-diagram"
        static let weeklyReport    = "builtin-weekly-report"
        static let apiDocWriter    = "builtin-api-doc-writer"
        static let codeCommenter   = "builtin-code-commenter"
        static let techDesign      = "builtin-tech-design"
        static let reviewHelper    = "builtin-review-helper"
    }

    // MARK: - Skill 定义

    // ── 美化 ────────────────────────────────────────────────────────────────

    static var htmlBeautifier: BuiltinSkillDef {
        BuiltinSkillDef(
            id:   ID.htmlBeautifier,
            name: "美化",
            description: "美化当前文档：Markdown 智能排版规整 / HTML 生成精美文档",
            content: """
            ---
            name: HTML 美化
            description: 将 Markdown 文档转换为精美的 self-contained HTML 文档
            version: 1.1
            ---

            你是一个专业的 HTML 文档美化师。给定 Markdown 内容和 CSS 主题，生成完整的 self-contained HTML 文档。

            ## 规则
            - 输出必须是完整的 HTML 文档，从 <!DOCTYPE html> 开始，到 </html> 结束
            - 不引用任何外部资源（字体、CDN、图片均不可用）
            - 使用语义化 HTML5：article, section, h1-h3, blockquote, figure, pre>code, table
            - 代码块用 <pre><code class="language-xxx"> 包裹，保留缩进和换行
            - 标题层级严格对应 Markdown 的 # ## ### → h1 h2 h3
            - 把提供的 CSS 完整嵌入 <style> 标签内，不要修改主题 CSS
            - 只输出 HTML 代码，不加任何解释或 markdown 代码块标记
            """,
            commands: [
                SkillCommand(
                    name: "to_html",
                    trigger: "转 HTML 文档",
                    icon: "doc.richtext.fill",
                    description: "将当前 Markdown 文档生成精美 HTML",
                    allowedTools: ["read_document", "write_document"]
                ),
                SkillCommand(
                    name: "to_html_doc",
                    trigger: "转带侧边栏 HTML",
                    icon: "sidebar.left",
                    description: "生成含侧边栏导航的 HTML 文档",
                    allowedTools: ["read_document", "write_document", "get_html_template"]
                ),
            ]
        )
    }

    // ── 内联编辑 ─────────────────────────────────────────────────────────────

    static var inlineEditor: BuiltinSkillDef {
        BuiltinSkillDef(
            id:   ID.inlineEditor,
            name: "内联编辑",
            description: "改写、扩写、精简、翻译选中文本",
            content: """
            ---
            name: 内联编辑
            description: 对选中文本进行改写、扩写、精简、翻译等精准编辑操作
            version: 1.0
            ---

            你是一个专业的文字编辑助手，对用户提供的文本进行精准的编辑操作。

            ## 操作说明
            - **改写**：保持原意，改善表达方式、逻辑结构和用词，使文章更流畅
            - **扩写**：在原有基础上补充细节、例子或背景信息，丰富内容
            - **精简**：去除冗余表达，保留核心信息，使文章更简洁有力
            - **翻译**：中英互译，保持原文风格、语气和 Markdown 格式

            ## 输出规则
            - 只返回处理后的文本，不加任何解释、前缀或代码块标记
            - 保持原文的 Markdown 格式（标题、列表、粗体、代码等）
            - 不改变原文的核心意图和事实内容
            - 输出语言：改写/扩写/精简保持原文语言；翻译则切换语言
            """,
            commands: [
                SkillCommand(name: "rewrite",   trigger: "改写",   icon: "text.badge.checkmark",       allowedTools: ["read_document", "patch_document"]),
                SkillCommand(name: "expand",    trigger: "扩写",   icon: "arrow.up.left.and.arrow.down.right", allowedTools: ["read_document", "patch_document"]),
                SkillCommand(name: "shorten",   trigger: "精简",   icon: "arrow.down.right.and.arrow.up.left", allowedTools: ["read_document", "patch_document"]),
                SkillCommand(name: "translate", trigger: "翻译",   icon: "globe",                       allowedTools: ["read_document", "patch_document"]),
            ]
        )
    }

    // ── Mermaid 图表生成 ──────────────────────────────────────────────────────

    static var mermaidDiagram: BuiltinSkillDef {
        BuiltinSkillDef(
            id:   ID.mermaidDiagram,
            name: "图表生成",
            description: "将文字描述转换为 Mermaid 图表（流程图、时序图、甘特图等）",
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
            commands: [
                SkillCommand(
                    name: "generate_diagram",
                    trigger: "生成图表",
                    icon: "chart.xyaxis.line",
                    description: "根据当前文档内容生成 Mermaid 图表",
                    allowedTools: ["read_document", "patch_document"]
                ),
                SkillCommand(
                    name: "flowchart",
                    trigger: "流程图",
                    icon: "arrow.triangle.branch",
                    description: "生成流程图",
                    allowedTools: ["read_document", "patch_document"]
                ),
                SkillCommand(
                    name: "sequence",
                    trigger: "时序图",
                    icon: "list.number",
                    description: "生成时序图",
                    allowedTools: ["read_document", "patch_document"]
                ),
            ]
        )
    }

    // ── 周报/日报 ─────────────────────────────────────────────────────────────

    static var weeklyReport: BuiltinSkillDef {
        BuiltinSkillDef(
            id:   ID.weeklyReport,
            name: "工作汇报",
            description: "将工作记录整理为规范的周报、日报或月报",
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
            commands: [
                SkillCommand(name: "daily",   trigger: "生成日报", icon: "sun.max",        allowedTools: ["read_document", "write_document"]),
                SkillCommand(name: "weekly",  trigger: "生成周报", icon: "calendar",        allowedTools: ["read_document", "write_document"]),
                SkillCommand(name: "monthly", trigger: "生成月报", icon: "calendar.badge.clock", allowedTools: ["read_document", "write_document"]),
            ]
        )
    }

    // ── API 文档生成 ──────────────────────────────────────────────────────────

    static var apiDocWriter: BuiltinSkillDef {
        BuiltinSkillDef(
            id:   ID.apiDocWriter,
            name: "API 文档",
            description: "根据代码或接口描述生成规范的 REST / GraphQL API 文档",
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
            commands: [
                SkillCommand(name: "from_code",  trigger: "代码转文档",  icon: "doc.text.magnifyingglass", allowedTools: ["read_document", "write_document"]),
                SkillCommand(name: "from_desc",  trigger: "描述转文档",  icon: "text.badge.plus",          allowedTools: ["read_document", "write_document"]),
            ]
        )
    }

    // ── 代码注释生成 ──────────────────────────────────────────────────────────

    static var codeCommenter: BuiltinSkillDef {
        BuiltinSkillDef(
            id:   ID.codeCommenter,
            name: "代码注释",
            description: "为代码添加清晰的 JSDoc/TSDoc 注释和行内说明",
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
            commands: [
                SkillCommand(name: "add_jsdoc", trigger: "加 JSDoc",    icon: "doc.append",     allowedTools: ["read_document", "patch_document"]),
                SkillCommand(name: "add_inline", trigger: "加行内注释", icon: "text.insert",     allowedTools: ["read_document", "patch_document"]),
            ]
        )
    }

    // ── 技术方案 ──────────────────────────────────────────────────────────────

    static var techDesign: BuiltinSkillDef {
        BuiltinSkillDef(
            id:   ID.techDesign,
            name: "技术方案",
            description: "根据需求描述生成完整的技术方案文档（架构、实现路径、风险）",
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
            commands: [
                SkillCommand(
                    name: "from_requirement",
                    trigger: "生成技术方案",
                    icon: "doc.badge.gearshape",
                    description: "将当前文档的需求描述转化为技术方案",
                    allowedTools: ["read_document", "write_document"]
                ),
                SkillCommand(
                    name: "add_risks",
                    trigger: "补充风险分析",
                    icon: "exclamationmark.triangle",
                    description: "为当前技术方案补充风险评估",
                    allowedTools: ["read_document", "patch_document"]
                ),
            ]
        )
    }

    // ── Code Review 助手 ──────────────────────────────────────────────────────

    static var reviewHelper: BuiltinSkillDef {
        BuiltinSkillDef(
            id:   ID.reviewHelper,
            name: "Code Review",
            description: "对代码进行全面的 Review：质量、安全、性能、可读性",
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
            commands: [
                SkillCommand(
                    name: "review_all",
                    trigger: "全面 Review",
                    icon: "checkmark.seal",
                    description: "对当前文档代码进行全维度 Review",
                    allowedTools: ["read_document", "write_document"]
                ),
                SkillCommand(
                    name: "review_security",
                    trigger: "安全检查",
                    icon: "lock.shield",
                    description: "专注安全漏洞扫描",
                    allowedTools: ["read_document"]
                ),
                SkillCommand(
                    name: "review_perf",
                    trigger: "性能分析",
                    icon: "gauge.with.needle",
                    description: "专注性能问题分析",
                    allowedTools: ["read_document"]
                ),
            ]
        )
    }

    // MARK: - Internal Prompts（不注册到 all，仅供 Agent 内部使用）

    /// BeautifyAgent 内部使用的 HTML 模板填充 prompt。
    /// 不是用户可见的技能，因此不加入 all 数组。
    static let htmlDocBeautifierContent: String = """
    你是专业的 HTML 文档排版师。给定一份完整的 HTML 模板（含 <style> 和「侧边栏 + 主区」布局）和一段 Markdown 内容，把内容填充进模板，产出完整的 self-contained HTML 文档。

    ## 规则
    - 严格保留模板的 <style> 块与整体结构（侧边栏 <aside class="sidebar"> + 主区 <main class="main">），不要修改样式
    - 用 Markdown 的真实内容替换模板里的所有示例占位（示例章节、示例表格/流程图等占位都要替换或删除，不要保留“章节二/示例”这类占位文字）
    - 侧边栏 <nav> 根据正文的 h2（必要时 h3）生成对应的 <a href="#锴点">，并给每个 <section> 设置匹配的 id；第一个导航项加 class="active"
    - 正文放入 <main class="main">，按 h2 分 <section id="...">；标题层级严格对应 Markdown：# → h1、## → h2、### → h3
    - 文档标题（<title>、侧边栏 brand、首个 h1）使用 Markdown 的一级标题
    - 可酥情使用模板自带组件 class：表格用 <div class="tbl"><table>…，提示用 .alert / .alert-info，标签用 .tag / .tag-g / .tag-o / .tag-r，卡片用 .card，代码块用 <pre><code>
    - 只输出完整 HTML（从 <!DOCTYPE html> 到 </html>），不加任何解释或 markdown 代码块标记
    """

    // MARK: - Registry

    /// 所有内置 skill 的有序列表（顺序影响 Settings 展示顺序）。
    static var all: [BuiltinSkillDef] {[
        htmlBeautifier,
        inlineEditor,
        mermaidDiagram,
        weeklyReport,
        apiDocWriter,
        codeCommenter,
        techDesign,
        reviewHelper,
    ]}
}
