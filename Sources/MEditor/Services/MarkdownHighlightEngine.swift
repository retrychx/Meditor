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
    private static let headingPattern = try! NSRegularExpression(
        pattern: "^(#{1,6})\\s+(.*)$",
        options: .anchorsMatchLines
    )
    private static let boldPattern = try! NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*", options: [])
    private static let italicPattern = try! NSRegularExpression(pattern: "(?<!\\*)\\*([^*]+)\\*(?!\\*)", options: [])
    private static let inlineCodePattern = try! NSRegularExpression(pattern: "`([^`\\n]+)`", options: [])
    /// Fenced code block: ```[lang]?\n ... \n```
    /// We don't anchor on `^` / `$` because NSRegularExpression's
    /// `.anchorsMatchLines` interaction with `[\s\S]*?` is unreliable in
    /// practice. Plain character-class matching is sufficient and robust.
    private static let fencedCodePattern = try! NSRegularExpression(
        pattern: "```[^\\n]*\\n[\\s\\S]*?\\n```",
        options: []
    )
    private static let linkPattern = try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)", options: [])
    private static let blockquotePattern = try! NSRegularExpression(
        pattern: "^>\\s+.*$",
        options: .anchorsMatchLines
    )
    private static let listPattern = try! NSRegularExpression(
        pattern: "^(\\s*)([*+-]|\\d+\\.)\\s",
        options: .anchorsMatchLines
    )
    private static let hrPattern = try! NSRegularExpression(
        pattern: "^(---+|\\*\\*\\*+|___+)\\s*$",
        options: .anchorsMatchLines
    )

    func highlight(text: String, into storage: NSTextStorage, range fullRange: NSRange, baseFont: NSFont) {
        // Color palette — tuned for both light and dark mode via system colors.
        // We pick muted accent colors so the editor doesn't compete visually
        // with the content; preview is the place for vibrant rendering.
        let headingColor = NSColor.systemIndigo                                // muted heading accent
        let bulletColor = NSColor.systemOrange.withAlphaComponent(0.85)
        let codeBg = NSColor(white: 0.5, alpha: 0.10)                          // subtle, theme-neutral
        let linkColor = NSColor.systemTeal
        let blockquoteColor = NSColor.secondaryLabelColor

        // Same point size as base font; just add bold trait.
        let boldFont = NSFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.bold), size: 0)
            ?? NSFont.boldSystemFont(ofSize: baseFont.pointSize)
        let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
        let boldItalicFont = NSFontManager.shared.convert(boldFont, toHaveTrait: .italicFontMask)

        // Monospaced font for code regions, slightly smaller so it doesn't
        // tower over surrounding prose due to wider glyph metrics.
        let monoFont = NSFont.monospacedSystemFont(ofSize: baseFont.pointSize - 0.5, weight: .regular)

        // Block-level paragraph styles
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

        // Order matters: code blocks first so heading/bold rules inside them
        // don't accidentally trigger.

        // 1. Fenced code blocks: monospaced + subtle background + extra spacing
        Self.fencedCodePattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.font, value: monoFont, range: match.range)
            storage.addAttribute(.backgroundColor, value: codeBg, range: match.range)
            storage.addAttribute(.paragraphStyle, value: codeBlockStyle, range: match.range)
        }

        // 2. Inline code: monospaced + soft background
        Self.inlineCodePattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.font, value: monoFont, range: match.range)
            storage.addAttribute(.backgroundColor, value: codeBg, range: match.range)
        }

        // 3. Headings: muted accent color + bold + breathing room above
        Self.headingPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.foregroundColor, value: headingColor, range: match.range)
            storage.addAttribute(.font, value: boldFont, range: match.range)
            storage.addAttribute(.paragraphStyle, value: headingStyle, range: match.range)
        }

        // 4. Block quotes
        Self.blockquotePattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.foregroundColor, value: blockquoteColor, range: match.range)
        }

        // 5. List bullets
        Self.listPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            if match.numberOfRanges >= 3 {
                storage.addAttribute(.foregroundColor, value: bulletColor, range: match.range(at: 2))
            }
        }

        // 6. Horizontal rule
        Self.hrPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.foregroundColor, value: blockquoteColor, range: match.range)
        }

        // 7. Bold inline (skip ranges already inside code, since code overwrites)
        Self.boldPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            // Don't override monospaced font set by code rules.
            let existingFont = storage.attribute(.font, at: match.range.location, effectiveRange: nil) as? NSFont
            if existingFont?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true { return }
            storage.addAttribute(.font, value: boldFont, range: match.range)
        }

        // 8. Italic inline (preserve bold/code if present)
        Self.italicPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            let range = match.range
            let existingFont = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            if existingFont?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true { return }
            let target = (existingFont?.isBold ?? false) ? boldItalicFont : italicFont
            storage.addAttribute(.font, value: target, range: range)
        }

        // 9. Links: color the label, dim the URL
        Self.linkPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            if match.numberOfRanges >= 3 {
                storage.addAttribute(.foregroundColor, value: linkColor, range: match.range(at: 1))
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: match.range(at: 2))
            }
        }
    }
}
