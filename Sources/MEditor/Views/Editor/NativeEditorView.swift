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
    let onScrollChange: ((Double) -> Void)?
    let previewScrollPercent: Double

    func makeCoordinator() -> Coordinator {
        Coordinator(onContentChange: onContentChange, onCursorChange: onCursorChange, onScrollChange: onScrollChange)
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
                  let textView = coordinator.textView,
                  let scrollView = textView.enclosingScrollView else { return }
            let docHeight = scrollView.documentView!.bounds.height
            let visibleHeight = scrollView.contentView.bounds.height
            let maxScroll = max(0, docHeight - visibleHeight)
            let percent = maxScroll > 0 ? scrollView.contentView.bounds.origin.y / maxScroll : 0
            guard !coordinator.isProgrammaticScroll else { return }
            coordinator.onScrollChange?(min(1, max(0, percent)))
        }

        if !content.isEmpty {
            textView.string = content
            context.coordinator.lastAcknowledgedContent = content
            context.coordinator.scheduleHighlight()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onContentChange = onContentChange
        context.coordinator.onCursorChange = onCursorChange
        context.coordinator.onScrollChange = onScrollChange
        context.coordinator.currentLanguage = language

        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Only push content to the editor if it changed externally (e.g., tab switch).
        // Highlighting is deferred to the next runloop tick so the user sees plain
        // text instantly, with syntax colors fading in shortly after.
        if context.coordinator.lastAcknowledgedContent != content {
            context.coordinator.isProgrammaticChange = true
            textView.string = content
            context.coordinator.lastAcknowledgedContent = content
            context.coordinator.isProgrammaticChange = false
            context.coordinator.scheduleHighlight()
        }

        // Sync editor scroll position from preview
        let lastPct = context.coordinator.lastPreviewScrollPercent
        if abs(previewScrollPercent - lastPct) > 0.005 {
            context.coordinator.lastPreviewScrollPercent = previewScrollPercent
            context.coordinator.isProgrammaticScroll = true
            let docHeight = scrollView.documentView!.bounds.height
            let visibleHeight = scrollView.contentView.bounds.height
            let maxScroll = max(0, docHeight - visibleHeight)
            let targetY = maxScroll * CGFloat(previewScrollPercent)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                context.coordinator.isProgrammaticScroll = false
            }
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var onContentChange: (String) -> Void
        var onCursorChange: ((Int, Int) -> Void)?
        var onScrollChange: ((Double) -> Void)?
        var currentLanguage: EditorLanguage = .markdown
        var lastAcknowledgedContent: String = ""
        weak var textView: NSTextView?
        var scrollObserver: NSObjectProtocol?
        var lastPreviewScrollPercent: Double = -1
        var isProgrammaticScroll = false

        private var debounceTimer: Timer?
        private var highlightTimer: Timer?
        fileprivate var isProgrammaticChange = false

        init(onContentChange: @escaping (String) -> Void, onCursorChange: ((Int, Int) -> Void)?, onScrollChange: ((Double) -> Void)?) {
            self.onContentChange = onContentChange
            self.onCursorChange = onCursorChange
            self.onScrollChange = onScrollChange
        }

        deinit {
            if let observer = scrollObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView, !isProgrammaticChange else { return }

            let newContent = textView.string
            lastAcknowledgedContent = newContent

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

            let storage = textView.textStorage!
            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            let baseColor = NSColor.labelColor
            let baseFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)

            // Reset to base style
            storage.removeAttribute(.foregroundColor, range: fullRange)
            storage.removeAttribute(.font, range: fullRange)
            storage.removeAttribute(.backgroundColor, range: fullRange)
            storage.addAttribute(.foregroundColor, value: baseColor, range: fullRange)
            storage.addAttribute(.font, value: baseFont, range: fullRange)

            guard let engine = HighlightService.shared.engine(for: currentLanguage) else { return }
            engine.highlight(text: text, into: storage, range: fullRange, baseFont: baseFont)
        }
    }
}

extension NSFont {
    var isBold: Bool {
        fontDescriptor.symbolicTraits.contains(.bold)
    }
}
