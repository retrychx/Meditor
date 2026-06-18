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

        let config   = AIConfig.current(settings)
        let css      = BuiltinTemplates.css(for: template.id)
        let messages = buildMessages(markdown: markdown, css: css,
                                     tokenOverrides: tokenOverrides,
                                     pluginManager: pluginManager)

        return AIClient(config: config).streamTask(messages, onChunk: onChunk, onComplete: onComplete)
    }

    private func buildMessages(
        markdown: String,
        css: String,
        tokenOverrides: [String: String],
        pluginManager: PluginManager
    ) -> [AIMessage] {
        let overrideBlock: String
        if tokenOverrides.isEmpty {
            overrideBlock = ""
        } else {
            let props = tokenOverrides
                .sorted { $0.key < $1.key }
                .map { "  --\($0.key): \($0.value);" }
                .joined(separator: "\n")
            overrideBlock = "\n:root {\n\(props)\n}"
        }
        let effectiveCSS = css + overrideBlock

        var system = BuiltinSkills.htmlBeautifier
            + "\n\nCSS（必须原样内联，不要修改）：\n\(effectiveCSS)"
        let extra = pluginManager.userSkillsPrompt()
        if !extra.isEmpty { system += "\n\n---\n\n# 附加技能\n\n" + extra }

        let user = "请将以下 Markdown 转换为美化的 HTML：\n\n\(markdown)"
        return [
            AIMessage(role: .system, content: system),
            AIMessage(role: .user,   content: user),
        ]
    }
}
