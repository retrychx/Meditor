import AppKit

/// Source-view markdown highlighter.
///
/// Design principle: this is an editor for the *raw markdown text*. The base
/// font is the system UI font (proportional) so Chinese/Japanese/Korean
/// glyphs render with their natural widths. Code-related regions (inline
/// `code` and ```fenced``` blocks) switch to the monospaced system font so
/// programs read like programs and tables of code align.
///
/// All other styling (headings, bold, italic, lists, quotes, links) is done
/// via color and weight only — never by changing font size — so row height
/// stays uniform.
final class MarkdownHighlightEngine: SyntaxHighlightEngine {
    private static let headingPattern = regex(
        "^(#{1,6})\\s+(.*)$",
        options: .anchorsMatchLines
    )
    private static let boldPattern = regex("\\*\\*(.+?)\\*\\*")
    private static let italicPattern = regex("(?<!\\*)\\*([^*]+)\\*(?!\\*)")
    private static let inlineCodePattern = regex("`([^`\\n]+)`")
    private static let fencedCodePattern = regex("```[^\\n]*\\n[\\s\\S]*?\\n```")
    private static let linkPattern = regex("\\[([^\\]]+)\\]\\(([^)]+)\\)")
    private static let blockquotePattern = regex(
        "^>\\s+.*$",
        options: .anchorsMatchLines
    )
    private static let listPattern = regex(
        "^(\\s*)([*+-]|\\d+\\.)\\s",
        options: .anchorsMatchLines
    )
    private static let hrPattern = regex(
        "^(---+|\\*\\*\\*+|___+)\\s*$",
        options: .anchorsMatchLines
    )

    func highlight(text: String, into storage: NSTextStorage, range fullRange: NSRange, baseFont: NSFont) {
        let headingColor = NSColor.systemIndigo
        let bulletColor = NSColor.systemOrange.withAlphaComponent(0.85)
        let codeBg = NSColor(white: 0.5, alpha: 0.10)
        let linkColor = NSColor.systemTeal
        let blockquoteColor = NSColor.secondaryLabelColor

        let boldFont = NSFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.bold), size: 0)
            ?? NSFont.boldSystemFont(ofSize: baseFont.pointSize)
        let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
        let boldItalicFont = NSFontManager.shared.convert(boldFont, toHaveTrait: .italicFontMask)

        let monoFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize - 0.5, weight: .regular)

        let codeBlockStyle = NSMutableParagraphStyle()
        codeBlockStyle.lineHeightMultiple = 1.2
        codeBlockStyle.paragraphSpacingBefore = 8
        codeBlockStyle.paragraphSpacing = 8
        codeBlockStyle.headIndent = 4
        codeBlockStyle.firstLineHeadIndent = 4

        let headingStyle = NSMutableParagraphStyle()
        headingStyle.lineHeightMultiple = 1.25
        headingStyle.paragraphSpacingBefore = 12
        headingStyle.paragraphSpacing = 6

        Self.fencedCodePattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.font, value: monoFont, range: match.range)
            storage.addAttribute(.backgroundColor, value: codeBg, range: match.range)
            storage.addAttribute(.paragraphStyle, value: codeBlockStyle, range: match.range)
        }

        Self.inlineCodePattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.font, value: monoFont, range: match.range)
            storage.addAttribute(.backgroundColor, value: codeBg, range: match.range)
        }

        Self.headingPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.foregroundColor, value: headingColor, range: match.range)
            storage.addAttribute(.font, value: boldFont, range: match.range)
            storage.addAttribute(.paragraphStyle, value: headingStyle, range: match.range)
        }

        Self.blockquotePattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.foregroundColor, value: blockquoteColor, range: match.range)
        }

        Self.listPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            if match.numberOfRanges >= 3 {
                storage.addAttribute(.foregroundColor, value: bulletColor, range: match.range(at: 2))
            }
        }

        Self.hrPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.foregroundColor, value: blockquoteColor, range: match.range)
        }

        Self.boldPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            let existingFont = storage.attribute(.font, at: match.range.location, effectiveRange: nil) as? NSFont
            if existingFont?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true { return }
            storage.addAttribute(.font, value: boldFont, range: match.range)
        }

        Self.italicPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            let range = match.range
            let existingFont = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            if existingFont?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true { return }
            let target = (existingFont?.isBold ?? false) ? boldItalicFont : italicFont
            storage.addAttribute(.font, value: target, range: range)
        }

        Self.linkPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            if match.numberOfRanges >= 3 {
                storage.addAttribute(.foregroundColor, value: linkColor, range: match.range(at: 1))
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: match.range(at: 2))
            }
        }
    }
}
