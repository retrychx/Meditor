import SwiftUI
import AppKit

/// A native NSTextView-based code editor with basic syntax highlighting.
/// Avoids WKWebView/CDN/JS bridge complexity.
struct NativeEditorView: NSViewRepresentable {
    /// Files larger than this threshold (in bytes) skip regex-based highlighting
    /// to avoid performance issues on large documents.
    static let largeFileThreshold = 500 * 1024

    let content: String
    let language: EditorLanguage
    let onContentChange: (String) -> Void
    let onCursorChange: ((Int, Int) -> Void)?
    /// Reports the 0-based line index visible at the top of the editor.
    /// Used to drive editor→preview scroll sync.
    let onVisibleTopLineChange: ((Int) -> Void)?
    /// Target line to scroll the editor to (preview→editor sync). -1 = none.
    let scrollToLine: Int
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
        }

        if !content.isEmpty {
            textView.string = content
            context.coordinator.lastAcknowledgedContent = content
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
        if context.coordinator.lastAcknowledgedContent != content {
            context.coordinator.isProgrammaticChange = true
            textView.string = content
            context.coordinator.lastAcknowledgedContent = content
            context.coordinator.rebuildLineOffsets(for: content)
            context.coordinator.isProgrammaticChange = false
            context.coordinator.scheduleHighlight()
        }

        // Sync editor scroll position from preview using source line.
        if scrollToLine >= 0 && scrollToLine != context.coordinator.lastAppliedTargetLine {
            context.coordinator.lastAppliedTargetLine = scrollToLine
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
        weak var textView: NSTextView?
        var scrollObserver: NSObjectProtocol?
        var lastReportedLine: Int = -1
        var lastAppliedTargetLine: Int = -1
        var isProgrammaticScroll = false

        private var debounceTimer: Timer?
        private var highlightTimer: Timer?
        fileprivate var isProgrammaticChange = false

        /// Cached line offset table: lineOffsets[i] = character index of line i's start.
        /// Invalidated on every content change for O(1) line lookups during scroll.
        private var lineOffsets: [Int] = [0]

        init(onContentChange: @escaping (String) -> Void,
             onCursorChange: ((Int, Int) -> Void)?,
             onVisibleTopLineChange: ((Int) -> Void)?) {
            self.onContentChange = onContentChange
            self.onCursorChange = onCursorChange
            self.onVisibleTopLineChange = onVisibleTopLineChange
        }

        deinit {
            if let observer = scrollObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        /// Rebuild the line offset cache from the current text content.
        func rebuildLineOffsets(for text: String) {
            let ns = text as NSString
            var offsets: [Int] = [0]
            offsets.reserveCapacity(ns.length / 40) // rough estimate
            for i in 0..<ns.length {
                if ns.character(at: i) == 0x0A {
                    offsets.append(i + 1)
                }
            }
            lineOffsets = offsets
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView, !isProgrammaticChange else { return }

            let newContent = textView.string
            lastAcknowledgedContent = newContent
            rebuildLineOffsets(for: newContent)

            // Content update debounce (50ms) - keeps preview reactive during typing
            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                DispatchQueue.main.async {
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
            let nsText = textView.string as NSString
            let range = textView.selectedRange()
            let lineRange = nsText.lineRange(for: NSRange(location: range.location, length: 0))
            let line = nsText.substring(to: range.location).components(separatedBy: "\n").count
            let column = range.location - lineRange.location + 1
            onCursorChange(line, column)
        }

        /// Compute the 0-based line index of the first visible character at
        /// the top of the editor's viewport. Uses cached line offsets for O(log n).
        func computeVisibleTopLine(textView: NSTextView) -> Int {
            guard let scrollView = textView.enclosingScrollView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return 0 }

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
            let nsText = textView.string as NSString

            // Walk to find the character index of the start of the target line.
            var currentLine = 0
            var charIndex = 0
            while currentLine < line && charIndex < nsText.length {
                if nsText.character(at: charIndex) == 0x0A { currentLine += 1 }
                charIndex += 1
            }
            // Lay out and find the rect.
            let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 0), actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let targetY = rect.origin.y + textView.textContainerInset.height

            isProgrammaticScroll = true
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
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

        func applyHighlighting() {
            guard let textView = textView else { return }
            let text = textView.string
            guard !text.isEmpty else { return }

            // Large files: skip both regex highlighting AND full-range attribute
            // resets. The text view's typingAttributes (set during makeNSView)
            // already render the body with the right font/color, so doing
            // nothing is the correct fast path. Touching the full NSTextStorage
            // would defeat `allowsNonContiguousLayout`.
            if text.utf8.count > NativeEditorView.largeFileThreshold {
                return
            }

            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            let baseColor = lastTheme.foregroundNSColor
            let baseFont = NSFont.systemFont(ofSize: 14)

            // Reset to base style
            storage.beginEditing()
            storage.removeAttribute(.foregroundColor, range: fullRange)
            storage.removeAttribute(.font, range: fullRange)
            storage.removeAttribute(.backgroundColor, range: fullRange)
            storage.removeAttribute(.paragraphStyle, range: fullRange)
            storage.addAttribute(.foregroundColor, value: baseColor, range: fullRange)
            storage.addAttribute(.font, value: baseFont, range: fullRange)

            // Apply comfortable line spacing across the whole document.
            let para = NSMutableParagraphStyle()
            para.lineHeightMultiple = 1.18
            para.paragraphSpacing = 4
            storage.addAttribute(.paragraphStyle, value: para, range: fullRange)

            guard let engine = HighlightService.shared.engine(for: currentLanguage) else {
                storage.endEditing()
                return
            }
            engine.highlight(text: text, into: storage, range: fullRange, baseFont: baseFont)
            storage.endEditing()
        }
    }
}

extension NSFont {
    var isBold: Bool {
        fontDescriptor.symbolicTraits.contains(.bold)
    }
}
