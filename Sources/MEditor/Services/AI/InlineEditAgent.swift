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

    var id: String { rawValue }

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
        }
    }

    @MainActor
    func buildMessages(for text: String, pluginManager: PluginManager) -> [AIMessage] {
        var system = BuiltinSkills.inlineEditor
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
        }
        var msg = "\(prefix)\n\n\(text)"
        if let doc = document, !doc.isEmpty, doc != text {
            msg += "\n\n---\n以下是完整文档上下文（仅供参考，只输出处理后的选中部分）：\n\n\(doc)"
        }
        return msg
    }
}

// MARK: - InlineEditAgent

/// Stateless service that processes a text selection via AI.
/// Streaming chunks arrive via `onChunk`; `onComplete` fires exactly once.
@MainActor
final class InlineEditAgent {

    func process(
        text: String,
        action: InlineEditAction,
        settings: AppSettings,
        pluginManager: PluginManager,
        onChunk: @escaping @MainActor (String) -> Void,
        onComplete: @escaping @MainActor (String?, Error?) -> Void
    ) -> Task<Void, Never> {
        guard pluginManager.isBuiltinEnabled(BuiltinSkills.ID.inlineEditor) else {
            onComplete(nil, AIError.notConfigured)
            return Task {}
        }

        let config   = AIConfig.current(settings, scene: .inline)
        let messages = action.buildMessages(for: text, pluginManager: pluginManager)

        return AIClient(config: config).streamTask(messages, onChunk: onChunk, onComplete: onComplete)
    }
}
