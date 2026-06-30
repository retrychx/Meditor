import Foundation

// MARK: - BeautifyAgent

/// Stateless service that asks the AI to turn Markdown into a self-contained
/// HTML document.  Streaming chunks arrive via `onChunk`; `onComplete` fires
/// exactly once with the full accumulated text or an error.
@MainActor
final class BeautifyAgent {

    func generate(
        markdown: String,
        template: DocumentTemplate,
        tokenOverrides: [String: String] = [:],
        settings: AppSettings,
        pluginManager: PluginManager,
        onChunk: @escaping @MainActor (String) -> Void,
        onComplete: @escaping @MainActor (String?, Error?) -> Void
    ) -> Task<Void, Never> {
        guard pluginManager.isBuiltinEnabled(BuiltinSkills.ID.htmlBeautifier) else {
            onComplete(nil, AIError.notConfigured)
            return Task {}
        }

        let config   = AIConfig.current(settings, scene: .beautify)
        let messages = buildMessages(markdown: markdown, template: template,
                                     tokenOverrides: tokenOverrides,
                                     pluginManager: pluginManager)

        return AIClient(config: config).streamTask(messages, onChunk: onChunk, onComplete: onComplete)
    }

    private func buildMessages(
        markdown: String,
        template: DocumentTemplate,
        tokenOverrides: [String: String],
        pluginManager: PluginManager
    ) -> [AIMessage] {
        let overrideBlock = Self.makeOverrideBlock(tokenOverrides)
        let extra = pluginManager.userSkillsPrompt()

        // html-doc 是富样式模板（侧边栏 + 组件），不能只内联 CSS —— 把整份模板当骨架让 AI 填充
        if template.id == "html-doc" {
            var templateHTML = template.content
            // 自定义样式确定生效：把覆盖的 :root 注入到模板 </style> 之前，而非依赖 AI 合并
            if !overrideBlock.isEmpty,
               let r = templateHTML.range(of: "</style>", options: .caseInsensitive) {
                templateHTML.replaceSubrange(r, with: overrideBlock + "\n</style>")
            }
            var system = BuiltinSkills.htmlDocBeautifier
            if !extra.isEmpty { system += "\n\n---\n\n# 附加技能\n\n" + extra }
            let user = """
            HTML 模板（保留其 <style> 与结构）：

            \(templateHTML)

            请把以下 Markdown 内容填充进上面的模板：

            \(markdown)
            """
            return [
                AIMessage(role: .system, content: system),
                AIMessage(role: .user,   content: user),
            ]
        }

        // tufte / craft / dark：内联各自的主题 CSS
        let css = BuiltinTemplates.css(for: template.id)
        let effectiveCSS = css + overrideBlock
        var system = BuiltinSkills.htmlBeautifier
            + "\n\nCSS（必须原样内联，不要修改）：\n\(effectiveCSS)"
        if !extra.isEmpty { system += "\n\n---\n\n# 附加技能\n\n" + extra }

        let user = "请将以下 Markdown 转换为美化的 HTML：\n\n\(markdown)"
        return [
            AIMessage(role: .system, content: system),
            AIMessage(role: .user,   content: user),
        ]
    }

    /// 把自定义样式 token 转成可追加的 `:root { … }` 覆盖块。
    private static func makeOverrideBlock(_ tokenOverrides: [String: String]) -> String {
        guard !tokenOverrides.isEmpty else { return "" }
        let props = tokenOverrides
            .sorted { $0.key < $1.key }
            .map { "  --\($0.key): \($0.value);" }
            .joined(separator: "\n")
        return "\n:root {\n\(props)\n}"
    }
}
