import SwiftUI
import AppKit
import os

// MARK: - EditorViewProtocol
// NativeEditorView 是 EditorViewProtocol 的 macOS 实现。
// 所有对外暴露的属性/回调均与 Protocols/EditorViewProtocol.swift 中的定义保持一致。
// 注意：NSViewRepresentable 与 protocol EditorViewProtocol: View 存在关联类型冲突，
// 无法在运行时做类型擦除，因此 NativeEditorView 以文档契约方式符合协议，
// 不做 Swift 静态 conformance 声明。未来 iOS/visionOS 实现请对照协议补齐全部成员。

/// A native NSTextView-based code editor with basic syntax highlighting.
/// Avoids WKWebView/CDN/JS bridge complexity.
struct NativeEditorView: NSViewRepresentable {
    /// Files larger than this threshold skip regex highlighting entirely.
    static let syntaxHighlightThreshold = 150 * 1024

    typealias Coordinator = EditorCoordinator

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
    /// Reports the currently selected text (empty when nothing is selected).
    var onSelectionChange: ((String) -> Void)? = nil
    /// Reports the current NSRange selection (used to save range before sheet opens).
    var onRangeChange: ((NSRange) -> Void)? = nil
    /// Text to insert at the caret / over the selection (driven by the AI panel).
    var insertText: String = ""
    /// Monotonic token so the same insert can be requested more than once.
    var insertRequestID: Int = 0
    /// Text to replace a saved NSRange (driven by InlineEdit accept).
    var replaceText: String = ""
    /// Monotonic token so the same replace can be requested more than once.
    var replaceRequestID: Int = 0
    /// The saved NSRange to replace (nil = use current selection).
    var pendingReplaceRange: NSRange? = nil
    /// Theme drives the text view's background and foreground colors so the
    /// editor pane visually matches the rest of the app.
    var theme: PreviewTheme = .github
    /// Editor font size in points. Defaults to the shared AppSettings value.
    var editorFontSize: Int = AppSettings.shared.editorFontSize

    func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(
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
        textView.font = NSFont.systemFont(ofSize: CGFloat(editorFontSize))

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

        // Line number gutter
        scrollView.rulersVisible = true
        scrollView.hasVerticalRuler = true
        if let ruler = LineNumberRulerView(textView: textView) {
            scrollView.verticalRulerView = ruler
        }

        // Accept image file drops
        textView.registerForDraggedTypes([.fileURL])

        // Observe scroll position changes for preview sync
        let center = NotificationCenter.default
        context.coordinator.scrollObserver = center.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak coordinator = context.coordinator] _ in
            guard let coordinator = coordinator,
                  let textView = coordinator.textView else { return }
            guard !coordinator.scrollSync.isProgrammaticScroll else { return }
            let line = coordinator.scrollSync.computeVisibleTopLine(textView: textView)
            // Throttle: only emit on line changes, not every pixel scroll.
            guard line != coordinator.scrollSync.lastReportedLine else { return }
            coordinator.scrollSync.lastReportedLine = line
            coordinator.onVisibleTopLineChange?(line)
            coordinator.highlighter.scheduleVisibleRangeHighlight()
        }

        if !content.isEmpty {
            textView.string = content
            context.coordinator.lastAcknowledgedContent = content
            context.coordinator.lastAcknowledgedRevision = contentRevision
            context.coordinator.highlighter.rebuildLineOffsets(for: content)
            context.coordinator.highlighter.scheduleHighlight()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onContentChange = onContentChange
        context.coordinator.onCursorChange = onCursorChange
        context.coordinator.onVisibleTopLineChange = onVisibleTopLineChange
        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.onRangeChange = onRangeChange
        context.coordinator.highlighter.language = language

        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Apply theme colors when theme changes.
        if context.coordinator.highlighter.theme != theme {
            context.coordinator.highlighter.theme = theme
            textView.backgroundColor = theme.editorBackgroundNSColor
            textView.textColor = theme.foregroundNSColor
            textView.insertionPointColor = theme.foregroundNSColor
            // Re-highlight to refresh attribute colors that depend on theme.
            context.coordinator.highlighter.scheduleHighlight()
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
            context.coordinator.highlighter.rebuildLineOffsets(for: content)
            context.coordinator.isProgrammaticChange = false
            context.coordinator.highlighter.scheduleHighlight()
        }

        // Sync editor scroll position from preview using source line.
        if scrollToLine >= 0 && scrollRequestID != context.coordinator.lastAppliedRequestID {
            context.coordinator.lastAppliedTargetLine = scrollToLine
            context.coordinator.lastAppliedRequestID = scrollRequestID
            context.coordinator.scrollToLine(scrollToLine)
        }

        // Insert text from the AI panel at the caret (replacing any selection).
        if insertRequestID != context.coordinator.lastInsertRequestID {
            context.coordinator.lastInsertRequestID = insertRequestID
            if insertRequestID > 0, !insertText.isEmpty {
                let range = textView.selectedRange()
                if textView.shouldChangeText(in: range, replacementString: insertText) {
                    textView.textStorage?.replaceCharacters(in: range, with: insertText)
                    textView.didChangeText()
                    let newCaret = range.location + (insertText as NSString).length
                    textView.setSelectedRange(NSRange(location: newCaret, length: 0))
                    let newContent = textView.string
                    context.coordinator.lastAcknowledgedContent = newContent
                    context.coordinator.highlighter.rebuildLineOffsets(for: newContent)
                    context.coordinator.onContentChange(newContent)
                    context.coordinator.highlighter.scheduleHighlight()
                    textView.scrollRangeToVisible(textView.selectedRange())
                }
            }
        }

        // Replace a saved selection range (driven by InlineEdit accept).
        if replaceRequestID != context.coordinator.lastReplaceNonce {
            context.coordinator.lastReplaceNonce = replaceRequestID
            if replaceRequestID > 0, !replaceText.isEmpty {
                let range = pendingReplaceRange ?? textView.selectedRange()
                if textView.shouldChangeText(in: range, replacementString: replaceText) {
                    textView.textStorage?.replaceCharacters(in: range, with: replaceText)
                    textView.didChangeText()
                    let newCaret = range.location + (replaceText as NSString).length
                    textView.setSelectedRange(NSRange(location: newCaret, length: 0))
                    let newContent = textView.string
                    context.coordinator.lastAcknowledgedContent = newContent
                    context.coordinator.highlighter.rebuildLineOffsets(for: newContent)
                    context.coordinator.onContentChange(newContent)
                    context.coordinator.highlighter.scheduleHighlight()
                    textView.scrollRangeToVisible(textView.selectedRange())
                }
            }
        }
    }
}

extension NSFont {
    var isBold: Bool {
        fontDescriptor.symbolicTraits.contains(.bold)
    }
}
