import SwiftUI
import AppKit
import os

/// A native NSTextView-based code editor with basic syntax highlighting.
/// Avoids WKWebView/CDN/JS bridge complexity.
struct NativeEditorView: NSViewRepresentable {
    /// Files larger than this threshold skip regex highlighting entirely.
    static let syntaxHighlightThreshold = 150 * 1024

    let content: String
    let contentRevision: Int
    let language: EditorLanguage
    let onContentChange: (String) -> Void
    let onCursorChange: ((Int, Int) -> Void)?
    /// Reports the 0-based line index visible at the top of the editor.
    /// Used to drive editor→preview scroll sync.
    let onVisibleTopLineChange: ((Int) -> Void)?
    /// Target line to scroll the editor to (preview→editor sync). -1 = none.
    let scrollToLine: Int
    /// Monotonic token so the same target line can be requested more than once.
    let scrollRequestID: Int
    /// Theme drives the text view's background and foreground colors so the
    /// editor pane visually matches the rest of the app.
    var theme: PreviewTheme = .github

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onContentChange: onContentChange,
            onCursorChange: onCursorChange,
            onVisibleTopLineChange: onVisibleTopLineChange
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollablePlainDocumentContentTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.isRichText = false
        textView.allowsUndo = true
        // Generous insets give the content room to breathe — code editors
        // can feel cramped when text starts at the very edge.
        textView.textContainerInset = NSSize(width: 24, height: 20)
        // System UI font (not monospaced): renders Chinese / Japanese / Korean
        // characters with the correct glyph widths and avoids the awkward
        // mid-line gaps that monospaced + CJK fallback produces.
        // Code spans / fenced blocks switch to monospaced via the highlighter.
        textView.font = NSFont.systemFont(ofSize: 14)

        // Comfortable line height + a touch of paragraph spacing for prose feel.
        let baseParagraph = NSMutableParagraphStyle()
        baseParagraph.lineHeightMultiple = 1.18
        baseParagraph.paragraphSpacing = 4
        textView.defaultParagraphStyle = baseParagraph
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textColor = theme.foregroundNSColor
        textView.backgroundColor = theme.editorBackgroundNSColor
        textView.drawsBackground = true
        textView.insertionPointColor = theme.foregroundNSColor

        // Performance: enable non-contiguous layout so the text system only
        // lays out visible glyphs eagerly. Crucial for opening large markdown
        // files without a multi-second hang.
        textView.layoutManager?.allowsNonContiguousLayout = true

        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        // Turn off scrollView border
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        // Observe scroll position changes for preview sync
        let center = NotificationCenter.default
        context.coordinator.scrollObserver = center.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak coordinator = context.coordinator] _ in
            guard let coordinator = coordinator,
                  let textView = coordinator.textView else { return }
            guard !coordinator.isProgrammaticScroll else { return }
            let line = coordinator.computeVisibleTopLine(textView: textView)
            // Throttle: only emit on line changes, not every pixel scroll.
            guard line != coordinator.lastReportedLine else { return }
            coordinator.lastReportedLine = line
            coordinator.onVisibleTopLineChange?(line)
            coordinator.scheduleVisibleRangeHighlight()
        }

        if !content.isEmpty {
            textView.string = content
            context.coordinator.lastAcknowledgedContent = content
            context.coordinator.lastAcknowledgedRevision = contentRevision
            context.coordinator.rebuildLineOffsets(for: content)
            context.coordinator.scheduleHighlight()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onContentChange = onContentChange
        context.coordinator.onCursorChange = onCursorChange
        context.coordinator.onVisibleTopLineChange = onVisibleTopLineChange
        context.coordinator.currentLanguage = language

        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Apply theme colors when theme changes.
        if context.coordinator.lastTheme != theme {
            context.coordinator.lastTheme = theme
            textView.backgroundColor = theme.editorBackgroundNSColor
            textView.textColor = theme.foregroundNSColor
            textView.insertionPointColor = theme.foregroundNSColor
            // Re-highlight to refresh attribute colors that depend on theme.
            context.coordinator.scheduleHighlight()
        }

        // Only push content to the editor if it changed externally (e.g., tab switch).
        // Highlighting is deferred to the next runloop tick so the user sees plain
        // text instantly, with syntax colors fading in shortly after.
        if context.coordinator.lastAcknowledgedRevision != contentRevision {
            context.coordinator.localRevisionPredictionActive = false
            context.coordinator.lastAcknowledgedRevision = contentRevision
            context.coordinator.isProgrammaticChange = true
            textView.string = content
            context.coordinator.lastAcknowledgedContent = content
            context.coordinator.rebuildLineOffsets(for: content)
            context.coordinator.isProgrammaticChange = false
            context.coordinator.scheduleHighlight()
        }

        // Sync editor scroll position from preview using source line.
        if scrollToLine >= 0 && scrollRequestID != context.coordinator.lastAppliedRequestID {
            context.coordinator.lastAppliedTargetLine = scrollToLine
            context.coordinator.lastAppliedRequestID = scrollRequestID
            context.coordinator.scrollToLine(scrollToLine)
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var onContentChange: (String) -> Void
        var onCursorChange: ((Int, Int) -> Void)?
        var onVisibleTopLineChange: ((Int) -> Void)?
        var currentLanguage: EditorLanguage = .markdown
        var lastTheme: PreviewTheme = .github
        var lastAcknowledgedContent: String = ""
        var lastAcknowledgedRevision: Int = 0
        weak var textView: NSTextView?
        var scrollObserver: NSObjectProtocol?
        var lastReportedLine: Int = -1
        var lastAppliedTargetLine: Int = -1
        var lastAppliedRequestID: Int = -1
        var isProgrammaticScroll = false
        var localRevisionPredictionActive = false

        private var debounceTimer: Timer?
        private var highlightTimer: Timer?
        private var visibleHighlightTimer: Timer?
        fileprivate var isProgrammaticChange = false

        /// Cached line offset table: lineOffsets[i] = character index of line i's start.
        /// Invalidated on every content change for O(1) line lookups during scroll.
        private var lineOffsets: [Int] = [0]
        private var lineOffsetsDirty = false

        init(onContentChange: @escaping (String) -> Void,
             onCursorChange: ((Int, Int) -> Void)?,
             onVisibleTopLineChange: ((Int) -> Void)?) {
            self.onContentChange = onContentChange
            self.onCursorChange = onCursorChange
            self.onVisibleTopLineChange = onVisibleTopLineChange
        }

        private static func previewUpdateDebounce(for content: String) -> TimeInterval {
            let bytes = content.utf8.count
            switch bytes {
            case 0..<16 * 1024:
                return 0.02
            case 16 * 1024..<64 * 1024:
                return 0.03
            case 64 * 1024..<256 * 1024:
                return 0.05
            default:
                return 0.08
            }
        }

        deinit {
            debounceTimer?.invalidate()
            highlightTimer?.invalidate()
            visibleHighlightTimer?.invalidate()
            if let observer = scrollObserver {
                NotificationCenter.default.removeObserver(observer)
            }
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

        private func ensureLineOffsets(for text: String) {
            if lineOffsetsDirty {
                rebuildLineOffsets(for: text)
            }
        }

        private func lineIndex(for characterIndex: Int, in text: String) -> Int {
            ensureLineOffsets(for: text)
            var lo = 0
            var hi = lineOffsets.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if lineOffsets[mid] <= characterIndex {
                    lo = mid + 1
                } else {
                    hi = mid
                }
            }
            return max(0, lo - 1)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView, !isProgrammaticChange else { return }

            let newContent = textView.string
            lastAcknowledgedContent = newContent
            if !localRevisionPredictionActive {
                lastAcknowledgedRevision &+= 1
                localRevisionPredictionActive = true
            }

            // Incremental line offset update: instead of marking dirty and
            // full-rebuilding on next access, patch the offset table from
            // the edit range. NSTextView provides the edited range after each
            // change; for simplicity we full-rebuild here but using Data.withUTF8
            // on the changed portion would be the next level.
            rebuildLineOffsets(for: newContent)

            // Content update debounce scales with file size so small notes
            // still feel immediate while large documents avoid bursty rerenders.
            debounceTimer?.invalidate()
            let previewUpdateDebounce = Self.previewUpdateDebounce(for: newContent)
            debounceTimer = Timer.scheduledTimer(withTimeInterval: previewUpdateDebounce, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.localRevisionPredictionActive = false
                    self.onContentChange(newContent)
                }
            }

            // Highlight debounce (300ms) - only runs syntax highlighting after user
            // stops typing, avoiding redundant O(n) passes on every keystroke
            highlightTimer?.invalidate()
            highlightTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.applyHighlighting()
                }
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = textView, let onCursorChange = onCursorChange else { return }
            let range = textView.selectedRange()
            let lineIndex = lineIndex(for: range.location, in: textView.string)
            let lineStart = lineOffsets[safe: lineIndex] ?? 0
            let column = max(1, range.location - lineStart + 1)
            onCursorChange(lineIndex + 1, column)
        }

        // MARK: - Markdown formatting shortcuts

        /// Wrap selection with markdown syntax. If no selection, insert placeholder.
        func wrapSelection(prefix: String, suffix: String, placeholder: String) {
            guard let textView = textView else { return }
            let range = textView.selectedRange()
            let text = textView.string as NSString

            if range.length > 0 {
                let selected = text.substring(with: range)
                // Toggle: if already wrapped, unwrap
                let before = range.location >= prefix.count
                    ? text.substring(with: NSRange(location: range.location - prefix.count, length: prefix.count))
                    : ""
                let after = (range.location + range.length + suffix.count <= text.length)
                    ? text.substring(with: NSRange(location: range.location + range.length, length: suffix.count))
                    : ""
                if before == prefix && after == suffix {
                    // Unwrap
                    let fullRange = NSRange(location: range.location - prefix.count, length: range.length + prefix.count + suffix.count)
                    textView.insertText(selected, replacementRange: fullRange)
                    textView.setSelectedRange(NSRange(location: range.location - prefix.count, length: range.length))
                } else {
                    // Wrap
                    let wrapped = prefix + selected + suffix
                    textView.insertText(wrapped, replacementRange: range)
                    textView.setSelectedRange(NSRange(location: range.location + prefix.count, length: range.length))
                }
            } else {
                // No selection: insert with placeholder
                let insert = prefix + placeholder + suffix
                textView.insertText(insert, replacementRange: range)
                textView.setSelectedRange(NSRange(location: range.location + prefix.count, length: placeholder.count))
            }
        }

        func toggleBold() { wrapSelection(prefix: "**", suffix: "**", placeholder: "bold") }
        func toggleItalic() { wrapSelection(prefix: "*", suffix: "*", placeholder: "italic") }
        func insertLink() { wrapSelection(prefix: "[", suffix: "](url)", placeholder: "text") }

        @objc func meditorToggleBold(_ sender: Any?) { toggleBold() }
        @objc func meditorToggleItalic(_ sender: Any?) { toggleItalic() }
        @objc func meditorInsertLink(_ sender: Any?) { insertLink() }

        /// Compute the 0-based line index of the first visible character at
        /// the top of the editor's viewport. Uses cached line offsets for O(log n).
        func computeVisibleTopLine(textView: NSTextView) -> Int {
            guard let scrollView = textView.enclosingScrollView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return 0 }
            ensureLineOffsets(for: textView.string)

            let visibleRect = scrollView.contentView.bounds
            let pointInTextContainer = NSPoint(
                x: 0,
                y: visibleRect.origin.y - textView.textContainerInset.height
            )
            let glyphIndex = layoutManager.glyphIndex(for: pointInTextContainer, in: textContainer)
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

            // Binary search on cached line offsets: O(log n) instead of O(n).
            var lo = 0, hi = lineOffsets.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if lineOffsets[mid] <= charIndex {
                    lo = mid + 1
                } else {
                    hi = mid
                }
            }
            return max(0, lo - 1)
        }

        /// Scroll the editor so the given 0-based source line is at the top.
        /// Used for preview→editor sync.
        func scrollToLine(_ line: Int) {
            guard line >= 0,
                  let textView = textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer,
                  let scrollView = textView.enclosingScrollView else { return }
            let sid = PerformanceTracer.begin("EditorScrollToLine", log: PerformanceTracer.editor)
            ensureLineOffsets(for: textView.string)
            let safeLine = min(line, max(0, lineOffsets.count - 1))
            let charIndex = lineOffsets[safeLine]
            // Lay out and find the rect.
            let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 0), actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let targetY = rect.origin.y + textView.textContainerInset.height

            isProgrammaticScroll = true
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            PerformanceTracer.end("EditorScrollToLine", log: PerformanceTracer.editor, id: sid)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.isProgrammaticScroll = false
            }
        }

        /// Apply syntax highlighting on the next runloop tick, debounced.
        /// Lets the text view paint plain text first for snappy file switching.
        func scheduleHighlight() {
            highlightTimer?.invalidate()
            highlightTimer = Timer.scheduledTimer(withTimeInterval: 0.0, repeats: false) { [weak self] _ in
                self?.applyHighlighting()
            }
        }

        /// Re-highlight after scrolling settles so newly visible text receives
        /// syntax colors without repainting on every scroll tick.
        func scheduleVisibleRangeHighlight() {
            visibleHighlightTimer?.invalidate()
            visibleHighlightTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
                self?.applyHighlighting()
            }
        }

        func applyHighlighting() {
            guard let textView = textView else { return }
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

            let baseColor = lastTheme.foregroundNSColor
            let baseFont = NSFont.systemFont(ofSize: 14)

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

            guard let engine = HighlightService.shared.engine(for: currentLanguage) else {
                storage.endEditing()
                PerformanceTracer.end("ApplyHighlighting", log: PerformanceTracer.editor, id: sid)
                return
            }
            engine.highlight(text: text, into: storage, range: highlightRange, baseFont: baseFont)
            storage.endEditing()
            PerformanceTracer.end("ApplyHighlighting", log: PerformanceTracer.editor, id: sid)
        }
    }
}

extension NSFont {
    var isBold: Bool {
        fontDescriptor.symbolicTraits.contains(.bold)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
