import Foundation

// MARK: - AISlashCommand（斜杠 AI 命令注册表）

/// 命令的作用范围。
enum AISlashCommandScope: Equatable, Sendable {
    /// 选区优先；无选区时作用于光标所在段落（命令位于空行时取上一非空段落）。
    case paragraphOrSelection
    /// 整篇文档。
    case document
    /// 不需要文档目标（如 /ask 纯提问）。
    case none
}

/// 命令输出的去向。
enum AISlashCommandOutput: Equatable, Sendable {
    /// 改写文档：流式生成 → 段落 diff 确认 → 可撤销写回。
    case diffWriteBack
    /// 只读问答：带入 AI 面板输入框，以气泡形式回答（用户确认后发送）。
    case chatBubble
}

/// 斜杠 AI 命令：prompt preset + 既有写回/问答链路。
///
/// 本模型是纯数据 + prompt 构建，不感知 UI；菜单（SlashCommandHandler）
/// 与执行器（SlashAICommandExecutor）只消费注册表。
struct AISlashCommand: Identifiable, Equatable, Sendable {
    /// 稳定 id（如 "polish"），用于查找与本地化 key 拼接。
    let id: String
    /// 斜杠别名（含 "/"），第一个为主别名。
    let aliases: [String]
    let icon: String
    /// 菜单搜索关键词（中英文均可）。
    let keywords: [String]
    let scope: AISlashCommandScope
    let output: AISlashCommandOutput
    /// 是否接受参数（「/cmd 参数」）：是则空格不提交命令、作为参数分隔符放行。
    let takesArgument: Bool
    /// 目标为空时的静态插入兜底（如 /table 在空行插入表格骨架）；nil 表示无兜底。
    let emptyFallbackInsertion: String?

    var title: String { L("slash.\(id).title") }
    var subtitle: String { L("slash.\(id).subtitle") }

    // MARK: - Prompt 构建

    /// prompt 构建的输入上下文（由执行器准备）。
    struct Context: Equatable, Sendable {
        /// scope 解析出的目标文本（选区 / 当前段落）。
        var target: String = ""
        /// 命令后输入的参数（takesArgument 时），可为空。
        var argument: String = ""
        /// 删除命令文本后的文档全文。
        var document: String = ""
        /// 光标前的文档内容（/continue、/summarize 用）。
        var precedingContext: String = ""
        /// /fix 用：诊断发现的问题列表（已格式化）。
        var diagnostics: String = ""
    }

    /// 构建发给模型的 user 消息。
    func buildPrompt(_ ctx: Context) -> String {
        let body: String
        switch id {
        case "ask":
            // 与旧实现逐字一致：无参数时给占位提示，由用户在面板里补全
            return ctx.argument.isEmpty ? "请回答一个问题（在此输入）：" : ctx.argument
        case "continue":
            body = "请根据以下已有内容，继续写作（保持风格和语气一致，无缝衔接）：\n\n"
                + String(ctx.precedingContext.suffix(800))
        case "improve":
            body = "请改善以下段落的表达、逻辑和流畅度（保持核心意思不变）：\n\n"
                + ctx.target.trimmingCharacters(in: .whitespaces)
        case "summarize":
            body = "请总结以下内容，输出 3-5 条简洁要点：\n\n"
                + String(ctx.precedingContext.suffix(2000))
        case "polish":
            body = "请润色以下文本，改进用词、句式与节奏，保持原意与 Markdown 格式。"
                + "只输出润色后的文本，不要任何解释：\n\n" + ctx.target
        case "outline":
            body = "请重新组织以下文档的结构：调整章节顺序与标题层级使逻辑更清晰，"
                + "不丢失任何内容，保持 Markdown 格式。只输出完整的重排后文档：\n\n" + ctx.document
        case "translate":
            body = "请翻译以下文本（中文译为英文、英文译为中文），保持 Markdown 格式与结构。"
                + "只输出译文，不要任何解释：\n\n" + ctx.target
        case "summary":
            body = "请为以下文档生成摘要：一句话总览 + 3-5 条要点。\n\n" + ctx.document
        case "fix":
            body = "以下是对文档做静态诊断发现的问题：\n\n" + ctx.diagnostics
                + "\n\n请修复文档中的这些问题（只改必要之处，其余内容保持原样），"
                + "输出修复后的完整文档：\n\n" + ctx.document
        case "table":
            body = "请将以下内容转换为规范的 Markdown 表格：合理设计列头，每行一条记录，"
                + "不遗漏信息。只输出表格本身，不要任何解释：\n\n" + ctx.target
        default:
            body = ctx.argument
        }
        // 带参数命令：参数作为附加要求拼到 preset 之后（ask 的参数即问题本体，已直接返回）
        guard takesArgument, !ctx.argument.isEmpty else { return body }
        return body + "\n\n额外要求：\(ctx.argument)"
    }
}

// MARK: - 注册表

enum AISlashCommandRegistry {

    /// 全部 AI 命令（菜单展示顺序）。含既有的 ask/continue/improve/summarize，
    /// 以及命令库新增的 polish/outline/translate/summary/fix/table。
    static let all: [AISlashCommand] = [
        // ── 问答类（chatBubble）──
        AISlashCommand(
            id: "ask",
            aliases: ["/ask"],
            icon: "bubble.left.and.bubble.right.fill",
            keywords: ["ai", "ask", "问", "回答"],
            scope: .none,
            output: .chatBubble,
            takesArgument: true,
            emptyFallbackInsertion: nil
        ),
        AISlashCommand(
            id: "summary",
            aliases: ["/summary"],
            icon: "text.quote",
            keywords: ["ai", "summary", "abstract", "摘要", "总结"],
            scope: .document,
            output: .chatBubble,
            takesArgument: false,
            emptyFallbackInsertion: nil
        ),
        // ── 旧命令（预填聊天面板，行为保持不变）──
        AISlashCommand(
            id: "continue",
            aliases: ["/continue", "/ai-continue"],
            icon: "arrow.right.circle.fill",
            keywords: ["ai", "continue", "继续", "写作"],
            scope: .none,
            output: .chatBubble,
            takesArgument: false,
            emptyFallbackInsertion: nil
        ),
        AISlashCommand(
            id: "improve",
            aliases: ["/improve", "/ai-improve"],
            icon: "wand.and.stars",
            keywords: ["ai", "improve", "优化", "改善"],
            scope: .paragraphOrSelection,
            output: .chatBubble,
            takesArgument: false,
            emptyFallbackInsertion: nil
        ),
        AISlashCommand(
            id: "summarize",
            aliases: ["/summarize", "/ai-summarize"],
            icon: "text.redaction",
            keywords: ["ai", "summarize", "总结"],
            scope: .none,
            output: .chatBubble,
            takesArgument: false,
            emptyFallbackInsertion: nil
        ),
        // ── 写回类（diff 确认写回）──
        AISlashCommand(
            id: "polish",
            aliases: ["/polish"],
            icon: "sparkles",
            keywords: ["ai", "polish", "润色", "打磨"],
            scope: .paragraphOrSelection,
            output: .diffWriteBack,
            takesArgument: true,
            emptyFallbackInsertion: nil
        ),
        AISlashCommand(
            id: "outline",
            aliases: ["/outline"],
            icon: "list.bullet.rectangle",
            keywords: ["ai", "outline", "structure", "大纲", "结构", "重排"],
            scope: .document,
            output: .diffWriteBack,
            takesArgument: false,
            emptyFallbackInsertion: nil
        ),
        AISlashCommand(
            id: "translate",
            aliases: ["/translate"],
            icon: "globe",
            keywords: ["ai", "translate", "翻译", "中英"],
            scope: .paragraphOrSelection,
            output: .diffWriteBack,
            takesArgument: true,
            emptyFallbackInsertion: nil
        ),
        AISlashCommand(
            id: "fix",
            aliases: ["/fix"],
            icon: "stethoscope",
            keywords: ["ai", "fix", "diagnostics", "修复", "诊断", "检查"],
            scope: .document,
            output: .diffWriteBack,
            takesArgument: false,
            emptyFallbackInsertion: nil
        ),
        AISlashCommand(
            id: "table",
            aliases: ["/table"],
            icon: "tablecells",
            keywords: ["ai", "table", "grid", "data", "表格"],
            scope: .paragraphOrSelection,
            output: .diffWriteBack,
            takesArgument: true,
            // 空行上的 /table 不消耗 AI：直接插入两列骨架（承接原静态 /table 命令）
            emptyFallbackInsertion: "| Column | Column |\n| --- | --- |\n|  |  |"
        ),
    ]

    /// 按别名查找（大小写不敏感，需含 "/" 前缀）。
    static func command(forAlias alias: String) -> AISlashCommand? {
        let lower = alias.lowercased()
        return all.first { $0.aliases.contains(lower) }
    }

    /// 按 id 查找。
    static func command(id: String) -> AISlashCommand? {
        all.first { $0.id == id }
    }
}
