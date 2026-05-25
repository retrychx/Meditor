import AppKit

final class HTMLHighlightEngine: SyntaxHighlightEngine {
    private static let tagPattern = try! NSRegularExpression(pattern: "</?([a-zA-Z][a-zA-Z0-9]*)\\b[^>]*/?>", options: [])
    private static let attrNamePattern = try! NSRegularExpression(pattern: "\\b([a-zA-Z][a-zA-Z0-9-]*)\\s*=", options: [])
    private static let attrValuePattern = try! NSRegularExpression(pattern: "\"[^\"]*\"", options: [])
    private static let commentPattern = try! NSRegularExpression(pattern: "<!--.*?-->", options: .dotMatchesLineSeparators)
    private static let entityPattern = try! NSRegularExpression(pattern: "&[a-zA-Z]+;", options: [])
    private static let doctypePattern = try! NSRegularExpression(pattern: "<!DOCTYPE[^>]*>", options: .caseInsensitive)

    func highlight(text: String, into storage: NSTextStorage, range fullRange: NSRange, baseFont: NSFont) {
        let tagColor = NSColor.systemBlue
        let attrNameColor = NSColor.systemTeal
        let attrValueColor = NSColor.systemOrange
        let commentColor = NSColor.tertiaryLabelColor
        let entityColor = NSColor.systemPink
        let doctypeColor = NSColor.systemGray

        Self.commentPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.foregroundColor, value: commentColor, range: match.range)
        }

        Self.doctypePattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.foregroundColor, value: doctypeColor, range: match.range)
        }

        Self.tagPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.foregroundColor, value: tagColor, range: match.range)
            if match.numberOfRanges >= 2 {
                let tagNameRange = match.range(at: 1)
                if let boldFont = NSFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.bold), size: 14) {
                    storage.addAttribute(.font, value: boldFont, range: tagNameRange)
                    storage.addAttribute(.foregroundColor, value: NSColor.systemIndigo, range: tagNameRange)
                }
            }
        }

        Self.entityPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.foregroundColor, value: entityColor, range: match.range)
        }

        Self.attrNamePattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.foregroundColor, value: attrNameColor, range: match.range(at: 1))
        }

        Self.attrValuePattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.foregroundColor, value: attrValueColor, range: match.range)
        }
    }
}
