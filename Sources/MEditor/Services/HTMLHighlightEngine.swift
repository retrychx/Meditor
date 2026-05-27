import AppKit

final class HTMLHighlightEngine: SyntaxHighlightEngine {
    private static let tagPattern         = try! NSRegularExpression(pattern: "</?([a-zA-Z][a-zA-Z0-9]*)\\b[^>]*/?>")
    private static let attrNamePattern    = try! NSRegularExpression(pattern: "\\b([a-zA-Z][a-zA-Z0-9-]*)\\s*=")
    private static let attrValuePattern   = try! NSRegularExpression(pattern: "\"[^\"]*\"")
    private static let commentPattern     = try! NSRegularExpression(pattern: "<!--.*?-->", options: .dotMatchesLineSeparators)
    private static let entityPattern      = try! NSRegularExpression(pattern: "&[a-zA-Z0-9#]+;")
    private static let doctypePattern     = try! NSRegularExpression(pattern: "<!DOCTYPE[^>]*>", options: .caseInsensitive)
    private static let styleBlockPattern  = try! NSRegularExpression(pattern: "<style[^>]*>([\\s\\S]*?)</style>", options: .caseInsensitive)
    private static let scriptBlockPattern = try! NSRegularExpression(pattern: "<script[^>]*>([\\s\\S]*?)</script>", options: .caseInsensitive)
    private static let cssSelectorPattern = try! NSRegularExpression(pattern: "[.#:@]?[a-zA-Z][a-zA-Z0-9_-]*(?=\\s*[{,])")
    private static let cssPropPattern     = try! NSRegularExpression(pattern: "([a-z-]{2,})\\s*:")
    private static let cssValuePattern    = try! NSRegularExpression(pattern: ":\\s*([^;{}\\n]+)")
    private static let cssCommentPattern  = try! NSRegularExpression(pattern: "/\\*.*?\\*/", options: .dotMatchesLineSeparators)
    private static let cssVarPattern      = try! NSRegularExpression(pattern: "var\\(--[^)]+\\)|#[0-9a-fA-F]{3,8}\\b|\\b\\d+(\\.\\d+)?(px|em|rem|%|vh|vw|s|ms)?\\b")
    // JS inside <script>
    private static let jsStringPattern    = try! NSRegularExpression(pattern: "\"[^\"\\n]*\"|'[^'\\n]*'|`[^`]*`")
    private static let jsKeywordPattern   = try! NSRegularExpression(pattern: "\\b(const|let|var|function|return|if|else|for|while|class|import|export|default|new|this|typeof|async|await|=>)\\b")
    private static let jsCommentPattern   = try! NSRegularExpression(pattern: "//[^\\n]*|/\\*[\\s\\S]*?\\*/")
    private static let jsNumberPattern    = try! NSRegularExpression(pattern: "\\b\\d+(\\.\\d+)?\\b")

    func highlight(text: String, into storage: NSTextStorage, range fullRange: NSRange, baseFont: NSFont) {
        // Detect dark mode via the effective appearance of the key window.
        let isDark: Bool = {
            let appearance = NSApp.keyWindow?.effectiveAppearance ?? NSAppearance(named: .aqua)!
            return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }()

        // Palette — light vs dark
        let tagBracketColor  = isDark ? NSColor(hex: "#89DDFF") : NSColor(hex: "#0550AE")  // angle brackets
        let tagNameColor     = isDark ? NSColor(hex: "#F07178") : NSColor(hex: "#116329")  // element names
        let attrNameColor    = isDark ? NSColor(hex: "#FFCB6B") : NSColor(hex: "#953800")  // attr names
        let attrValueColor   = isDark ? NSColor(hex: "#C3E88D") : NSColor(hex: "#0A3069")  // attr values
        let commentColor     = isDark ? NSColor(hex: "#546E7A") : NSColor(hex: "#8B949E")  // comments
        let entityColor      = isDark ? NSColor(hex: "#F78C6C") : NSColor(hex: "#CF222E")  // &amp;
        let doctypeColor     = isDark ? NSColor(hex: "#546E7A") : NSColor(hex: "#8B949E")

        // CSS palette
        let cssSelectorColor = isDark ? NSColor(hex: "#82AAFF") : NSColor(hex: "#8250DF")
        let cssPropColor     = isDark ? NSColor(hex: "#89DDFF") : NSColor(hex: "#0550AE")
        let cssValueColor    = isDark ? NSColor(hex: "#C3E88D") : NSColor(hex: "#116329")
        let cssSpecialColor  = isDark ? NSColor(hex: "#F78C6C") : NSColor(hex: "#CF222E")
        let cssCommentColor  = isDark ? NSColor(hex: "#546E7A") : NSColor(hex: "#8B949E")

        // JS palette
        let jsKeywordColor   = isDark ? NSColor(hex: "#C792EA") : NSColor(hex: "#8250DF")
        let jsStringColor    = isDark ? NSColor(hex: "#C3E88D") : NSColor(hex: "#0A3069")
        let jsNumberColor    = isDark ? NSColor(hex: "#F78C6C") : NSColor(hex: "#CF222E")
        let jsCommentColor   = isDark ? NSColor(hex: "#546E7A") : NSColor(hex: "#8B949E")

        // Bold font for tag names
        let boldFont = NSFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.bold),
                              size: baseFont.pointSize) ?? baseFont

        // HTML comments
        Self.commentPattern.enumerateMatches(in: text, range: fullRange) { m, _, _ in
            guard let m = m else { return }
            storage.addAttribute(.foregroundColor, value: commentColor, range: m.range)
        }
        // DOCTYPE
        Self.doctypePattern.enumerateMatches(in: text, range: fullRange) { m, _, _ in
            guard let m = m else { return }
            storage.addAttribute(.foregroundColor, value: doctypeColor, range: m.range)
        }
        // Tags
        Self.tagPattern.enumerateMatches(in: text, range: fullRange) { m, _, _ in
            guard let m = m else { return }
            storage.addAttribute(.foregroundColor, value: tagBracketColor, range: m.range)
            if m.numberOfRanges >= 2 {
                storage.addAttribute(.foregroundColor, value: tagNameColor, range: m.range(at: 1))
                storage.addAttribute(.font, value: boldFont, range: m.range(at: 1))
            }
        }
        // Attr names
        Self.attrNamePattern.enumerateMatches(in: text, range: fullRange) { m, _, _ in
            guard let m = m, m.numberOfRanges >= 2 else { return }
            storage.addAttribute(.foregroundColor, value: attrNameColor, range: m.range(at: 1))
        }
        // Attr values
        Self.attrValuePattern.enumerateMatches(in: text, range: fullRange) { m, _, _ in
            guard let m = m else { return }
            storage.addAttribute(.foregroundColor, value: attrValueColor, range: m.range)
        }
        // Entities
        Self.entityPattern.enumerateMatches(in: text, range: fullRange) { m, _, _ in
            guard let m = m else { return }
            storage.addAttribute(.foregroundColor, value: entityColor, range: m.range)
        }

        // CSS inside <style>
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

        // JS inside <script>
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

private extension NSColor {
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
