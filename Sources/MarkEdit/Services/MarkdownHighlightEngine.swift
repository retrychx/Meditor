import AppKit

final class MarkdownHighlightEngine: SyntaxHighlightEngine {
    private static let headingPattern = try! NSRegularExpression(pattern: "^(#{1,6})\\s+(.*)$", options: .anchorsMatchLines)
    private static let boldPattern = try! NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*", options: [])
    private static let italicPattern = try! NSRegularExpression(pattern: "(?<!\\*)\\*([^*]+)\\*(?!\\*)", options: [])
    private static let codePattern = try! NSRegularExpression(pattern: "`([^`]+)`", options: [])
    private static let linkPattern = try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)", options: [])

    func highlight(text: String, into storage: NSTextStorage, range fullRange: NSRange, baseFont: NSFont) {
        let nsText = text as NSString
        let headingColor = NSColor.systemBlue
        let boldFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
        let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
        let codeBg = NSColor.quaternaryLabelColor
        let linkColor = NSColor.systemTeal
        let boldItalicFont = NSFontManager.shared.convert(boldFont, toHaveTrait: .italicFontMask)

        Self.headingPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.foregroundColor, value: headingColor, range: match.range)
            let level = nsText.substring(with: match.range(at: 1)).count
            let size: CGFloat = level <= 2 ? 17 : 15
            let hsFont = NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
            storage.addAttribute(.font, value: hsFont, range: match.range)
        }

        Self.boldPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.font, value: boldFont, range: match.range)
        }

        Self.italicPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            let range = match.range
            let existingFont = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            if !(existingFont?.isBold ?? false) {
                storage.addAttribute(.font, value: italicFont, range: range)
            } else {
                storage.addAttribute(.font, value: boldItalicFont, range: range)
            }
        }

        Self.codePattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.backgroundColor, value: codeBg, range: match.range)
        }

        Self.linkPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.foregroundColor, value: linkColor, range: match.range(at: 1))
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: match.range(at: 2))
        }
    }
}
