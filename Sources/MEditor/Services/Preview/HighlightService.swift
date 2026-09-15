import Foundation

/// 高亮引擎注册表。`engines` 只在 init/register 期写入，之后只读；
/// 标注 @unchecked Sendable 以便跨 actor 引用共享实例。
final class HighlightService: HighlightServiceProtocol, @unchecked Sendable {
    static let shared = HighlightService()

    private var engines: [EditorLanguage: SyntaxHighlightEngine] = [:]

    private init() {
        register(.markdown, engine: MarkdownHighlightEngine())
        register(.html, engine: HTMLHighlightEngine())
    }

    func register(_ language: EditorLanguage, engine: SyntaxHighlightEngine) {
        engines[language] = engine
    }

    func engine(for language: EditorLanguage) -> SyntaxHighlightEngine? {
        engines[language]
    }
}
