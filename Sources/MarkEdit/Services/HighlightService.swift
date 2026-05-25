import AppKit

final class HighlightService {
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
