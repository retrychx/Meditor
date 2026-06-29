import AppKit

final class HTMLHighlightEngine: SyntaxHighlightEngine {
    private static let tagPattern         = regex("</?([a-zA-Z][a-zA-Z0-9]*)\\b[^>]*/?>")
    private static let attrNamePattern    = regex("\\b([a-zA-Z][a-zA-Z0-9-]*)\\s*=")
    private static let attrValuePattern   = regex("\"[^\"]*\"")
    private static let commentPattern     = regex("<!--.*?-->", options: .dotMatchesLineSeparators)
    private static let entityPattern      = regex("&[a-zA-Z0-9#]+;")
    private static let doctypePattern     = regex("<!DOCTYPE[^>]*>", options: .caseInsensitive)
    private static let styleBlockPattern  = regex("<style[^>]*>([\\s\\S]*?)</style>", options: .caseInsensitive)
    private static let scriptBlockPattern = regex("<script[^>]*>([\\s\\S]*?)</script>", options: .caseInsensitive)
    private static let cssSelectorPattern = regex("[.#:@]?[a-zA-Z][a-zA-Z0-9_-]*(?=\\s*[{,])")
    private static let cssPropPattern     = regex("([a-z-]{2,})\\s*:")
    private static let cssValuePattern    = regex(":\\s*([^;{}\\n]+)")
    private static let cssCommentPattern  = regex("/\\*.*?\\*/", options: .dotMatchesLineSeparators)
    private static let cssVarPattern      = regex("var\\(--[^)]+\\)|#[0-9a-fA-F]{3,8}\\b|\\b\\d+(\\.\\d+)?(px|em|rem|%|vh|vw|s|ms)?\\b")
    private static let jsStringPattern    = regex("\"[^\"\\n]*\"|'[^'\\n]*'|`[^`]*`")
    private static let jsKeywordPattern   = regex("\\b(const|let|var|function|return|if|else|for|while|class|import|export|default|new|this|typeof|async|await|=>)\\b")
    private static let jsCommentPattern   = regex("//[^\\n]*|/\\*[\\s\\S]*?\\*/")
    private static let jsNumberPattern    = regex("\\b\\d+(\\.\\d+)?\\b")

    func highlight(text: String, into storage: NSTextStorage, range fullRange: NSRange, baseFont: PlatformFont) {
        let isDark: Bool = {
            let appearance = NSApp.keyWindow?.effectiveAppearance ?? NSAppearance(named: .aqua)!
            return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }()

        let tagBracketColor  = isDark ? PlatformColor(hex: "#89DDFF") : PlatformColor(hex: "#0550AE")
        let tagNameColor     = isDark ? PlatformColor(hex: "#F07178") : PlatformColor(hex: "#116329")
        let attrNameColor    = isDark ? PlatformColor(hex: "#FFCB6B") : PlatformColor(hex: "#953800")
        let attrValueColor   = isDark ? PlatformColor(hex: "#C3E88D") : PlatformColor(hex: "#0A3069")
        let commentColor     = isDark ? PlatformColor(hex: "#546E7A") : PlatformColor(hex: "#8B949E")
        let entityColor      = isDark ? PlatformColor(hex: "#F78C6C") : PlatformColor(hex: "#CF222E")
        let doctypeColor     = isDark ? PlatformColor(hex: "#546E7A") : PlatformColor(hex: "#8B949E")

        let cssSelectorColor = isDark ? PlatformColor(hex: "#82AAFF") : PlatformColor(hex: "#8250DF")
        let cssPropColor     = isDark ? PlatformColor(hex: "#89DDFF") : PlatformColor(hex: "#0550AE")
        let cssValueColor    = isDark ? PlatformColor(hex: "#C3E88D") : PlatformColor(hex: "#116329")
        let cssSpecialColor  = isDark ? PlatformColor(hex: "#F78C6C") : PlatformColor(hex: "#CF222E")
        let cssCommentColor  = isDark ? PlatformColor(hex: "#546E7A") : PlatformColor(hex: "#8B949E")

        let jsKeywordColor   = isDark ? PlatformColor(hex: "#C792EA") : PlatformColor(hex: "#8250DF")
        let jsStringColor    = isDark ? PlatformColor(hex: "#C3E88D") : PlatformColor(hex: "#0A3069")
        let jsNumberColor    = isDark ? PlatformColor(hex: "#F78C6C") : PlatformColor(hex: "#CF222E")
        let jsCommentColor   = isDark ? PlatformColor(hex: "#546E7A") : PlatformColor(hex: "#8B949E")

        let boldFont = PlatformFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.bold),
                              size: baseFont.pointSize) ?? baseFont

        Self.commentPattern.enumerateMatches(in: text, range: fullRange) { m, _, _ in
            guard let m = m else { return }
            storage.addAttribute(.foregroundColor, value: commentColor, range: m.range)
        }
        Self.doctypePattern.enumerateMatches(in: text, range: fullRange) { m, _, _ in
            guard let m = m else { return }
            storage.addAttribute(.foregroundColor, value: doctypeColor, range: m.range)
        }
        Self.tagPattern.enumerateMatches(in: text, range: fullRange) { m, _, _ in
            guard let m = m else { return }
            storage.addAttribute(.foregroundColor, value: tagBracketColor, range: m.range)
            if m.numberOfRanges >= 2 {
                storage.addAttribute(.foregroundColor, value: tagNameColor, range: m.range(at: 1))
                storage.addAttribute(.font, value: boldFont, range: m.range(at: 1))
            }
        }
        Self.attrNamePattern.enumerateMatches(in: text, range: fullRange) { m, _, _ in
            guard let m = m, m.numberOfRanges >= 2 else { return }
            storage.addAttribute(.foregroundColor, value: attrNameColor, range: m.range(at: 1))
        }
        Self.attrValuePattern.enumerateMatches(in: text, range: fullRange) { m, _, _ in
            guard let m = m else { return }
            storage.addAttribute(.foregroundColor, value: attrValueColor, range: m.range)
        }
        Self.entityPattern.enumerateMatches(in: text, range: fullRange) { m, _, _ in
            guard let m = m else { return }
            storage.addAttribute(.foregroundColor, value: entityColor, range: m.range)
        }

        Self.styleBlockPattern.enumerateMatches(in: text, range: fullRange) { m, _, _ in
            guard let m = m, m.numberOfRanges >= 2 else { return }
            let r = m.range(at: 1)
            Self.cssCommentPattern.enumerateMatches(in: text, range: r) { cm, _, _ in
                guard let cm = cm else { return }
                storage.addAttribute(.foregroundColor, value: cssCommentColor, range: cm.range)
            }
            Self.cssSelectorPattern.enumerateMatches(in: text, range: r) { cm, _, _ in
                guard let cm = cm else { return }
                storage.addAttribute(.foregroundColor, value: cssSelectorColor, range: cm.range)
            }
            Self.cssPropPattern.enumerateMatches(in: text, range: r) { cm, _, _ in
                guard let cm = cm, cm.numberOfRanges >= 2 else { return }
                storage.addAttribute(.foregroundColor, value: cssPropColor, range: cm.range(at: 1))
            }
            Self.cssValuePattern.enumerateMatches(in: text, range: r) { cm, _, _ in
                guard let cm = cm, cm.numberOfRanges >= 2 else { return }
                storage.addAttribute(.foregroundColor, value: cssValueColor, range: cm.range(at: 1))
            }
            Self.cssVarPattern.enumerateMatches(in: text, range: r) { cm, _, _ in
                guard let cm = cm else { return }
                storage.addAttribute(.foregroundColor, value: cssSpecialColor, range: cm.range)
            }
        }

        Self.scriptBlockPattern.enumerateMatches(in: text, range: fullRange) { m, _, _ in
            guard let m = m, m.numberOfRanges >= 2 else { return }
            let r = m.range(at: 1)
            Self.jsCommentPattern.enumerateMatches(in: text, range: r) { cm, _, _ in
                guard let cm = cm else { return }
                storage.addAttribute(.foregroundColor, value: jsCommentColor, range: cm.range)
            }
            Self.jsStringPattern.enumerateMatches(in: text, range: r) { cm, _, _ in
                guard let cm = cm else { return }
                storage.addAttribute(.foregroundColor, value: jsStringColor, range: cm.range)
            }
            Self.jsKeywordPattern.enumerateMatches(in: text, range: r) { cm, _, _ in
                guard let cm = cm else { return }
                storage.addAttribute(.foregroundColor, value: jsKeywordColor, range: cm.range)
                storage.addAttribute(.font, value: boldFont, range: cm.range)
            }
            Self.jsNumberPattern.enumerateMatches(in: text, range: r) { cm, _, _ in
                guard let cm = cm else { return }
                storage.addAttribute(.foregroundColor, value: jsNumberColor, range: cm.range)
            }
        }
    }
}

private extension PlatformColor {
    convenience init(hex: String) {
        var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let v = UInt64(s, radix: 16) ?? 0
        self.init(
            red:   CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8)  & 0xFF) / 255,
            blue:  CGFloat( v        & 0xFF) / 255,
            alpha: 1
        )
    }
}
