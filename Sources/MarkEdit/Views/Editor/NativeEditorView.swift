import SwiftUI
import AppKit

/// A native NSTextView-based code editor with basic syntax highlighting.
/// Avoids WKWebView/CDN/JS bridge complexity.
struct NativeEditorView: NSViewRepresentable {
    let content: String
    let language: EditorLanguage
    let onContentChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onContentChange: onContentChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollablePlainDocumentContentTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 8, height: 12)
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = NSColor.controlBackgroundColor
        textView.drawsBackground = true

        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        // Turn off scrollView border
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        if !content.isEmpty {
            textView.string = content
            context.coordinator.lastAcknowledgedContent = content
            applyHighlighting(to: textView, language: language)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onContentChange = onContentChange
        context.coordinator.currentLanguage = language

        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Only push content to the editor if it changed externally (e.g., tab switch)
        if context.coordinator.lastAcknowledgedContent != content {
            textView.string = content
            context.coordinator.lastAcknowledgedContent = content
            applyHighlighting(to: textView, language: language)
        }
    }

    // MARK: - Syntax Highlighting

    private static let mdHeadingPattern = try! NSRegularExpression(pattern: "^(#{1,6})\\s+(.*)$", options: .anchorsMatchLines)
    private static let mdBoldPattern = try! NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*", options: [])
    private static let mdItalicPattern = try! NSRegularExpression(pattern: "(?<!\\*)\\*([^*]+)\\*(?!\\*)", options: [])
    private static let mdCodePattern = try! NSRegularExpression(pattern: "`([^`]+)`", options: [])
    private static let mdLinkPattern = try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)", options: [])
    private static let htmlTagPattern = try! NSRegularExpression(pattern: "</?([a-zA-Z][a-zA-Z0-9]*)\\b[^>]*/?>", options: [])
    private static let htmlAttrNamePattern = try! NSRegularExpression(pattern: "\\b([a-zA-Z][a-zA-Z0-9-]*)\\s*=", options: [])
    private static let htmlAttrValuePattern = try! NSRegularExpression(pattern: "\"[^\"]*\"", options: [])
    private static let htmlCommentPattern = try! NSRegularExpression(pattern: "<!--.*?-->", options: .dotMatchesLineSeparators)
    private static let htmlEntityPattern = try! NSRegularExpression(pattern: "&[a-zA-Z]+;", options: [])
    private static let htmlDoctypePattern = try! NSRegularExpression(pattern: "<!DOCTYPE[^>]*>", options: .caseInsensitive)

    private func applyHighlighting(to textView: NSTextView, language: EditorLanguage) {
        let text = textView.string
        guard !text.isEmpty else { return }

        let storage = textView.textStorage!
        let fullRange = NSRange(location: 0, length: (text as NSString).length)

        // Reset to base style
        storage.removeAttribute(.foregroundColor, range: fullRange)
        storage.removeAttribute(.font, range: fullRange)
        storage.removeAttribute(.backgroundColor, range: fullRange)

        let baseColor = NSColor.labelColor
        let baseFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        storage.addAttribute(.foregroundColor, value: baseColor, range: fullRange)
        storage.addAttribute(.font, value: baseFont, range: fullRange)

        if language == .markdown {
            highlightMarkdown(storage: storage, text: text, fullRange: fullRange, baseFont: baseFont)
        } else {
            highlightHTML(storage: storage, text: text, fullRange: fullRange, baseFont: baseFont)
        }
    }

    private func highlightMarkdown(storage: NSTextStorage, text: String, fullRange: NSRange, baseFont: NSFont) {
        let nsText = text as NSString
        let headingColor = NSColor.systemBlue
        let boldFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
        let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
        let codeBg = NSColor.quaternaryLabelColor
        let linkColor = NSColor.systemTeal
        let boldItalicFont = NSFontManager.shared.convert(boldFont, toHaveTrait: .italicFontMask)

        // Headings
        Self.mdHeadingPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.foregroundColor, value: headingColor, range: match.range)
            // Make heading text slightly larger
            let level = nsText.substring(with: match.range(at: 1)).count
            let size: CGFloat = level <= 2 ? 17 : 15
            let hsFont = NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
            storage.addAttribute(.font, value: hsFont, range: match.range)
        }

        // Bold
        Self.mdBoldPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.font, value: boldFont, range: match.range)
        }

        // Italic (must run after bold to avoid conflicts)
        Self.mdItalicPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            let range = match.range
            // Check if this range already has bold applied
            let existingFont = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            if !(existingFont?.isBold ?? false) {
                storage.addAttribute(.font, value: italicFont, range: range)
            } else {
                storage.addAttribute(.font, value: boldItalicFont, range: range)
            }
        }

        // Inline code
        Self.mdCodePattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.backgroundColor, value: codeBg, range: match.range)
        }

        // Links
        Self.mdLinkPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.foregroundColor, value: linkColor, range: match.range(at: 1))
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: match.range(at: 2))
        }
    }

    private func highlightHTML(storage: NSTextStorage, text: String, fullRange: NSRange, baseFont: NSFont) {
        let tagColor = NSColor.systemBlue
        let attrNameColor = NSColor.systemTeal
        let attrValueColor = NSColor.systemOrange
        let commentColor = NSColor.tertiaryLabelColor
        let entityColor = NSColor.systemPink
        let doctypeColor = NSColor.systemGray

        // Comments (must be first so tags don't override)
        Self.htmlCommentPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.foregroundColor, value: commentColor, range: match.range)
        }

        // DOCTYPE
        Self.htmlDoctypePattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.foregroundColor, value: doctypeColor, range: match.range)
        }

        // HTML tags (whole tag gets blue, tag name also bold)
        Self.htmlTagPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.foregroundColor, value: tagColor, range: match.range)
            // Bold the tag name within the tag
            if match.numberOfRanges >= 2 {
                let tagNameRange = match.range(at: 1)
                if let boldFont = NSFont(descriptor: baseFont.fontDescriptor.withSymbolicTraits(.bold), size: 14) {
                    storage.addAttribute(.font, value: boldFont, range: tagNameRange)
                    storage.addAttribute(.foregroundColor, value: NSColor.systemIndigo, range: tagNameRange)
                }
            }
        }

        // HTML entities
        Self.htmlEntityPattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.foregroundColor, value: entityColor, range: match.range)
        }

        // Attribute names
        Self.htmlAttrNamePattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.foregroundColor, value: attrNameColor, range: match.range(at: 1))
        }

        // Attribute values (quoted strings)
        Self.htmlAttrValuePattern.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match = match else { return }
            storage.addAttribute(.foregroundColor, value: attrValueColor, range: match.range)
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var onContentChange: (String) -> Void
        var currentLanguage: EditorLanguage = .markdown
        var lastAcknowledgedContent: String = ""
        weak var textView: NSTextView?

        private var debounceTimer: Timer?
        private var isProgrammaticChange = false

        init(onContentChange: @escaping (String) -> Void) {
            self.onContentChange = onContentChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView, !isProgrammaticChange else { return }

            let newContent = textView.string
            lastAcknowledgedContent = newContent

            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.onContentChange(newContent)
                }
            }
        }
    }
}

private extension NSFont {
    var isBold: Bool {
        fontDescriptor.symbolicTraits.contains(.bold)
    }
}
