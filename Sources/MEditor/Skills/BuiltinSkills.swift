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
            name: 美化
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
            - 若未提供 CSS 主题，则使用简洁清晰的内置默认样式（system 字体、合理行距与留白、浅色代码块背景）
            - 只输出 HTML 代码，不加任何解释或 markdown 代码块标记
            """,
            commands: [
                SkillCommand(
                    name: "to_html",
                    trigger: "转 HTML 文档",
                    icon: "doc.richtext.fill",
                    description: "将当前 Markdown 文档生成精美 HTML",
                    allowedTools: ["read_document", "create_file"]
                ),
                SkillCommand(
                    name: "to_html_doc",
                    trigger: "转带侧边栏 HTML",
                    icon: "sidebar.left",
                    description: "生成含侧边栏导航的 HTML 文档",
                    allowedTools: ["read_document", "create_file", "get_html_template"]
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
            content: SharedSkillPrompts.mermaidDiagram,
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
            content: SharedSkillPrompts.weeklyReport,
            commands: [
                SkillCommand(name: "daily",   trigger: "生成日报", icon: "sun.max",        allowedTools: ["read_document", "create_file"]),
                SkillCommand(name: "weekly",  trigger: "生成周报", icon: "calendar",        allowedTools: ["read_document", "create_file"]),
                SkillCommand(name: "monthly", trigger: "生成月报", icon: "calendar.badge.clock", allowedTools: ["read_document", "create_file"]),
            ]
        )
    }

    // ── API 文档生成 ──────────────────────────────────────────────────────────

    static var apiDocWriter: BuiltinSkillDef {
        BuiltinSkillDef(
            id:   ID.apiDocWriter,
            name: "API 文档",
            description: "根据代码或接口描述生成规范的 REST / GraphQL API 文档",
            content: SharedSkillPrompts.apiDocWriter,
            commands: [
                SkillCommand(name: "from_code",  trigger: "代码转文档",  icon: "doc.text.magnifyingglass", allowedTools: ["read_document", "create_file"]),
                SkillCommand(name: "from_desc",  trigger: "描述转文档",  icon: "text.badge.plus",          allowedTools: ["read_document", "create_file"]),
            ]
        )
    }

    // ── 代码注释生成 ──────────────────────────────────────────────────────────

    static var codeCommenter: BuiltinSkillDef {
        BuiltinSkillDef(
            id:   ID.codeCommenter,
            name: "代码注释",
            description: "为代码添加清晰的 JSDoc/TSDoc 注释和行内说明",
            content: SharedSkillPrompts.codeCommenter,
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
            content: SharedSkillPrompts.techDesign,
            commands: [
                SkillCommand(
                    name: "from_requirement",
                    trigger: "生成技术方案",
                    icon: "doc.badge.gearshape",
                    description: "将当前文档的需求描述转化为技术方案",
                    allowedTools: ["read_document", "create_file"]
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
            content: SharedSkillPrompts.reviewHelper,
            commands: [
                SkillCommand(
                    name: "review_all",
                    trigger: "全面 Review",
                    icon: "checkmark.seal",
                    description: "对当前文档代码进行全维度 Review",
                    allowedTools: ["read_document", "create_file"]
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
    - 侧边栏 <nav> 根据正文的 h2（必要时 h3）生成对应的 <a href="#锚点">，并给每个 <section> 设置匹配的 id；第一个导航项加 class="active"
    - 正文放入 <main class="main">，按 h2 分 <section id="...">；标题层级严格对应 Markdown：# → h1、## → h2、### → h3
    - 文档标题（<title>、侧边栏 brand、首个 h1）使用 Markdown 的一级标题
    - 可酌情使用模板自带组件 class：表格用 <div class="tbl"><table>…，提示用 .alert / .alert-info，标签用 .tag / .tag-g / .tag-o / .tag-r，卡片用 .card，代码块用 <pre><code>
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
