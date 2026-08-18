import AppKit

/// Owns syntax highlighting timers and the line-offset index.
/// Decoupled from Coordinator so scroll sync can query offsets independently.
final class EditorHighlightScheduler {
    weak var textView: NSTextView?
    var theme: PreviewTheme = .github
    var language: EditorLanguage = .markdown
    /// 正文基础字体（跟随设置页编辑器字体/字号），粗体/斜体/等宽都由此派生。
    var baseFont: NSFont = NSFont.systemFont(ofSize: 14)

    /// Cached line offset table: lineOffsets[i] = character index of line i's start.
    /// Invalidated on every content change for O(1) line lookups during scroll.
    var lineOffsets: [Int] = [0]
    private var lineOffsetsDirty = false

    private var highlightTimer: Timer?
    private var visibleHighlightTimer: Timer?

    deinit {
        highlightTimer?.invalidate()
        visibleHighlightTimer?.invalidate()
    }

    /// Rebuild the line offset cache from the current text content.
    func rebuildLineOffsets(for text: String) {
        let sid = PerformanceTracer.begin("RebuildLineOffsets", log: PerformanceTracer.editor)
        let ns = text as NSString
        let length = ns.length
        var offsets: [Int] = [0]
        offsets.reserveCapacity(length / 40)

        // NSString.range(of:) uses vectorized search internally,
        // ~3-5x faster than per-character loop for large strings.
        var searchStart = 0
        while searchStart < length {
            let found = ns.range(of: "\n", range: NSRange(location: searchStart, length: length - searchStart))
            if found.location == NSNotFound { break }
            offsets.append(found.location + 1)
            searchStart = found.location + 1
        }

        lineOffsets = offsets
        lineOffsetsDirty = false
        PerformanceTracer.end("RebuildLineOffsets", log: PerformanceTracer.editor, id: sid)
    }

    func ensureLineOffsets(for text: String) {
        if lineOffsetsDirty { rebuildLineOffsets(for: text) }
    }

    func lineIndex(for characterIndex: Int, in text: String) -> Int {
        ensureLineOffsets(for: text)
        var lo = 0
        var hi = lineOffsets.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if lineOffsets[mid] <= characterIndex { lo = mid + 1 }
            else { hi = mid }
        }
        return max(0, lo - 1)
    }

    /// Schedule syntax highlighting after `delay` seconds.
    /// Invalidates any previously pending highlight so keystrokes only
    /// trigger one pass after the user stops typing.
    func scheduleHighlight(after delay: TimeInterval = 0.0) {
        highlightTimer?.invalidate()
        highlightTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, let textView = self.textView else { return }
            self.applyHighlight(to: textView)
        }
    }

    /// Re-highlight after scrolling settles so newly visible text receives
    /// syntax colors without repainting on every scroll tick.
    func scheduleVisibleRangeHighlight() {
        visibleHighlightTimer?.invalidate()
        visibleHighlightTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
            guard let self, let textView = self.textView else { return }
            self.applyHighlight(to: textView)
        }
    }

    func applyHighlight(to textView: NSTextView) {
        let text = textView.string
        guard !text.isEmpty else { return }

        if text.utf8.count > NativeEditorView.syntaxHighlightThreshold {
            PerformanceTracer.event("HighlightSkipped_LargeFile", log: PerformanceTracer.editor)
            return
        }

        let sid = PerformanceTracer.begin("ApplyHighlighting", log: PerformanceTracer.editor)

        guard let storage = textView.textStorage,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            PerformanceTracer.end("ApplyHighlighting", log: PerformanceTracer.editor, id: sid)
            return
        }

        let nsText = text as NSString
        let fullLength = nsText.length

        // Compute visible character range + buffer (2000 chars above/below).
        let visibleRect = textView.enclosingScrollView?.contentView.bounds ?? textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        let bufferChars = 2000
        let rangeStart = max(0, visibleCharRange.location - bufferChars)
        let rangeEnd = min(fullLength, visibleCharRange.location + visibleCharRange.length + bufferChars)
        let highlightRange = NSRange(location: rangeStart, length: rangeEnd - rangeStart)

        let baseColor = theme.foregroundNSColor
        let baseFont = self.baseFont

        storage.beginEditing()
        // Reset only the highlight range
        storage.removeAttribute(.foregroundColor, range: highlightRange)
        storage.removeAttribute(.font, range: highlightRange)
        storage.removeAttribute(.backgroundColor, range: highlightRange)
        storage.removeAttribute(.paragraphStyle, range: highlightRange)
        storage.addAttribute(.foregroundColor, value: baseColor, range: highlightRange)
        storage.addAttribute(.font, value: baseFont, range: highlightRange)

        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = 1.18
        para.paragraphSpacing = 4
        storage.addAttribute(.paragraphStyle, value: para, range: highlightRange)

        guard let engine = HighlightService.shared.engine(for: language) else {
            storage.endEditing()
            PerformanceTracer.end("ApplyHighlighting", log: PerformanceTracer.editor, id: sid)
            return
        }
        engine.highlight(text: text, into: storage, range: highlightRange, baseFont: baseFont)
        storage.endEditing()
        PerformanceTracer.end("ApplyHighlighting", log: PerformanceTracer.editor, id: sid)
    }
}
