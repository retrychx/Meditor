import AppKit

/// A vertical ruler that displays line numbers alongside an NSTextView.
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private let textColor = NSColor.tertiaryLabelColor

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView!, orientation: .verticalRuler)
        self.ruleThickness = 36
        self.clientView = textView

        NotificationCenter.default.addObserver(
            self, selector: #selector(textDidChange(_:)),
            name: NSText.didChangeNotification, object: textView
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: textView.enclosingScrollView?.contentView
        )
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func textDidChange(_ n: Notification) { needsDisplay = true }
    @objc private func boundsDidChange(_ n: Notification) { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let visibleRect = scrollView?.contentView.bounds ?? .zero
        let visibleGlyphs = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleChars = layoutManager.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)

        let text = textView.string as NSString
        let inset = textView.textContainerInset.height

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]

        var lineNumber = 1
        // Fast line count before visible range using vectorized search
        var searchStart = 0
        while searchStart < visibleChars.location {
            let found = text.range(of: "\n", range: NSRange(location: searchStart, length: visibleChars.location - searchStart))
            if found.location == NSNotFound { break }
            lineNumber += 1
            searchStart = found.location + 1
        }

        // Draw line numbers for visible lines
        var glyphIdx = visibleGlyphs.location
        while glyphIdx < NSMaxRange(visibleGlyphs) {
            let charRange = layoutManager.characterRange(forGlyphRange: NSRange(location: glyphIdx, length: 1), actualGlyphRange: nil)
            var lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
            lineRect.origin.y += inset - visibleRect.origin.y

            let numStr = "\(lineNumber)" as NSString
            let strSize = numStr.size(withAttributes: attrs)
            let drawPoint = NSPoint(
                x: ruleThickness - strSize.width - 6,
                y: lineRect.origin.y + (lineRect.height - strSize.height) / 2
            )
            numStr.draw(at: drawPoint, withAttributes: attrs)

            // Advance to next line
            let lineEnd = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIdx, effectiveRange: nil)
            _ = lineEnd
            var nextGlyphIdx = NSMaxRange(layoutManager.glyphRange(forCharacterRange: NSRange(location: charRange.location, length: max(1, charRange.length)), actualCharacterRange: nil))
            // Find start of next visual line
            let rangeEnd = NSMaxRange(charRange)
            if rangeEnd < text.length {
                let nextLineRange = (text as NSString).lineRange(for: NSRange(location: rangeEnd, length: 0))
                nextGlyphIdx = layoutManager.glyphRange(forCharacterRange: nextLineRange, actualCharacterRange: nil).location
            } else {
                nextGlyphIdx = NSMaxRange(visibleGlyphs)
            }

            lineNumber += 1
            if nextGlyphIdx <= glyphIdx { break }
            glyphIdx = nextGlyphIdx
        }
    }
}
