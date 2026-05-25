import SwiftUI
import MarkdownUI
import Splash

struct SplashHighlighter: CodeSyntaxHighlighter {
    private let syntaxHighlighter: SyntaxHighlighter<AttributedStringOutputFormat>

    init(theme: Splash.Theme) {
        self.syntaxHighlighter = SyntaxHighlighter(format: AttributedStringOutputFormat(theme: theme))
    }

    func highlightCode(_ code: String, language: String?) -> Text {
        let highlighted = syntaxHighlighter.highlight(code)
        return Text(AttributedString(highlighted))
    }
}

extension CodeSyntaxHighlighter where Self == SplashHighlighter {
    static func splash(theme: Splash.Theme) -> SplashHighlighter {
        SplashHighlighter(theme: theme)
    }
}
