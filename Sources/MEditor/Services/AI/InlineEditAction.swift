import Foundation

// MARK: - InlineEditAction

enum InlineEditAction: String, CaseIterable, Identifiable {
    // 通用操作
    case rewrite       = "改写"
    case expand        = "扩写"
    case condense      = "精简"
    case translate     = "翻译"
    // 代码类内容
    case explainCode   = "解释"
    case addComments   = "加注释"
    // 标题类内容
    case expandSection = "扩写章节"
    // 列表类内容
    case organizeList  = "整理"
    // 结构化内容
    case convertToTable = "转表格"

    var id: String { rawValue }

    /// 面向用户的展示名。rawValue 保持中文作为稳定 id（CaseIterable / 持久化兼容），
    /// UI 一律用 displayName，随语言切换。
    var displayName: String {
        switch self {
        case .rewrite:       return L("ai.inline.rewrite")
        case .expand:        return L("ai.inline.expand")
        case .condense:      return L("ai.inline.condense")
        case .translate:     return L("ai.suggest.translate")
        case .explainCode:   return L("ai.inline.explain")
        case .addComments:   return L("ai.inline.addComments")
        case .expandSection: return L("ai.inline.expandSection")
        case .organizeList:  return L("ai.inline.organizeList")
        case .convertToTable: return L("ai.inline.toTable")
        }
    }

    var icon: String {
        switch self {
        case .rewrite:       return "pencil.and.outline"
        case .expand:        return "arrow.up.left.and.arrow.down.right"
        case .condense:      return "arrow.down.right.and.arrow.up.left"
        case .translate:     return "globe"
        case .explainCode:   return "text.magnifyingglass"
        case .addComments:   return "text.bubble"
        case .expandSection: return "doc.text.below.ecg"
        case .organizeList:  return "list.bullet.indent"
        case .convertToTable: return "tablecells"
        }
    }

    @MainActor
    func buildMessages(for text: String, pluginManager: PluginManager) -> [AIMessage] {
        var system = BuiltinSkills.inlineEditor.content
        let extra = pluginManager.userSkillsPrompt()
        if !extra.isEmpty { system += "\n\n---\n\n# 附加技能\n\n" + extra }
        return [
            AIMessage(role: .system, content: system),
            AIMessage(role: .user,   content: userInstruction(for: text)),
        ]
    }

    private func userInstruction(for text: String) -> String {
        userInstruction(for: text, document: nil)
    }

    /// 带完整文档上下文的指令（供 AgentRunner 调用）。
    func userInstruction(for text: String, document: String?) -> String {
        let prefix: String
        switch self {
        case .rewrite:       prefix = "改写以下文本，改善表达方式和逻辑，保持原意："
        case .expand:        prefix = "扩写以下文本，补充细节和例子，丰富内容："
        case .condense:      prefix = "精简以下文本，去除冗余，保留核心信息："
        case .translate:     prefix = "翻译以下文本（中英互译），保持原有 Markdown 格式和风格："
        case .explainCode:   prefix = "解释以下代码的功能、逻辑和关键点，用通信语言："
        case .addComments:   prefix = "为以下代码添加详尽的内联注释，注释用相应语言（中文中文注释）："
        case .expandSection: prefix = "以下标题为开头，展开内容并写出该章节的完整内容："
        case .organizeList:  prefix = "整理以下列表，排除重复、按逻辑顺序重新排列、补充遗漏项："
        case .convertToTable: prefix = "将以下内容转换为规范的 Markdown 表格（合理设计列头，每行一条记录，不遗漏信息），只输出表格："
        }
        var msg = "\(prefix)\n\n\(text)"
        if let doc = document, !doc.isEmpty, doc != text {
            // 8K 门控（与聊天面板一致），大文档不整篇内联
            let capped = doc.count > 8000
                ? String(doc.prefix(8000)) + "\n…（文档过长已截断）"
                : doc
            msg += "\n\n---\n以下是完整文档上下文（仅供参考，只输出处理后的选中部分）：\n\n\(capped)"
        }
        return msg
    }
}

// MARK: - InlineEditBarPlan

/// 选区浮动操作条（InlineEditBar）的展示规则：出条门控 + 按内容类型的动作分组。
/// 纯函数，供 InlineEditBar / EditorView 与单元测试复用。
enum InlineEditBarPlan {
    /// 选区是否值得出条：去首尾空白/换行后不足 2 字符（含纯空行选区）不出条。
    static func shouldShow(for selection: String) -> Bool {
        selection.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    /// 按选中内容类型返回（主行动作, 「更多」收纳动作）。主行最多 4 个，超出进「更多」。
    static func actions(for selection: String) -> (primary: [InlineEditAction], overflow: [InlineEditAction]) {
        let t = selection.trimmingCharacters(in: .whitespaces)

        // 代码块：解释 + 注释 + 精简；改写/翻译进「更多」
        if t.hasPrefix("```") || t.hasPrefix("    ") {
            return ([.explainCode, .addComments, .condense], [.rewrite, .translate])
        }

        // 标题：扩写章节 + 改写；其余进「更多」
        if t.hasPrefix("#") {
            return ([.expandSection, .rewrite], [.expand, .condense, .translate])
        }

        // 列表：转表格优先，整理 + 扩写 + 精简随行；改写/翻译进「更多」
        let lines = t.components(separatedBy: "\n").filter { !$0.isEmpty }
        let isListLike = lines.count >= 2 && lines.prefix(3).allSatisfy {
            $0.hasPrefix("- ") || $0.hasPrefix("* ") || $0.hasPrefix("+ ") ||
            $0.range(of: #"^\d+\. "#, options: .regularExpression) != nil
        }
        if isListLike {
            return ([.convertToTable, .organizeList, .expand, .condense], [.rewrite, .translate])
        }

        // 默认：核心四动作全部放得下，无需「更多」
        return ([.rewrite, .expand, .condense, .translate], [])
    }
}

