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
        textView.font = NSFont.systemFont(ofSize: CGFloat(AppSettings.shared.editorFontSize))

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
        private var isApplyingSlashCommand = false
        private var slashPopover: NSPopover?
        private var slashQueryRange: NSRange?
        private var slashItems: [SlashCommandItem] = []
        private var slashSelectedIndex = 0

        /// Pending auto-close character to insert after the current edit completes.
        private var pendingAutoClose: Character?
        private static let autoPairs: [Character: Character] = [
            "(": ")", "[": "]", "{": "}",
            "\"": "\"", "'": "'", "`": "`"
        ]

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
            closeSlashMenu()
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

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
            guard !isProgrammaticChange else { return true }

            if isApplyingSlashCommand { return true }

            if let text,
               (text == " " || text == "\n"),
               range.length == 0 {
                if isSlashMenuVisible {
                    return !commitSlashSelection()
                }
                if applySlashCommandIfNeeded(in: textView, at: range.location) {
                    return false
                }
            }

            guard let text, text.count == 1,
                  let char = text.first,
                  let close = Self.autoPairs[char] else { return true }
            // Only auto-close when inserting (not replacing selection with a pair char)
            // For quotes/backtick: skip if the char before cursor is alphanumeric (likely closing)
            if char == close { // symmetric pair (", ', `)
                let ns = textView.string as NSString
                if range.location > 0 {
                    let prev = ns.character(at: range.location - 1)
                    if let scalar = Unicode.Scalar(prev),
                       CharacterSet.alphanumerics.contains(scalar) {
                        return true
                    }
                }
            }
            if range.length == 0 {
                pendingAutoClose = close
            }
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView, !isProgrammaticChange else { return }

            // Handle auto-close bracket that was deferred from shouldChangeText
            if let close = pendingAutoClose {
                pendingAutoClose = nil
                let pos = textView.selectedRange().location
                isProgrammaticChange = true
                textView.insertText(String(close), replacementRange: NSRange(location: pos, length: 0))
                textView.setSelectedRange(NSRange(location: pos, length: 0))
                isProgrammaticChange = false
            }

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

            updateSlashMenu(in: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = textView, let onCursorChange = onCursorChange else { return }
            let range = textView.selectedRange()
            let lineIndex = lineIndex(for: range.location, in: textView.string)
            let lineStart = lineOffsets[safe: lineIndex] ?? 0
            let column = max(1, range.location - lineStart + 1)
            onCursorChange(lineIndex + 1, column)
            updateSlashMenu(in: textView)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard isSlashMenuVisible else { return false }

            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                moveSlashSelection(-1)
                return true
            case #selector(NSResponder.moveDown(_:)):
                moveSlashSelection(1)
                return true
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
                 #selector(NSResponder.insertTab(_:)):
                return commitSlashSelection()
            case #selector(NSResponder.cancelOperation(_:)):
                closeSlashMenu()
                return true
            default:
                return false
            }
        }

        // MARK: - Slash commands

        private static let slashCommands: [SlashCommandItem] = [
            SlashCommandItem(
                title: "Heading 1",
                subtitle: "Large section title",
                icon: "textformat.size.larger",
                aliases: ["/h1", "/heading1", "/title"],
                keywords: ["heading", "title"],
                expansion: SlashCommandExpansion(text: "# ", cursorOffset: nil)
            ),
            SlashCommandItem(
                title: "Heading 2",
                subtitle: "Medium section title",
                icon: "textformat.size",
                aliases: ["/h2", "/heading2"],
                keywords: ["heading", "section"],
                expansion: SlashCommandExpansion(text: "## ", cursorOffset: nil)
            ),
            SlashCommandItem(
                title: "Heading 3",
                subtitle: "Small section title",
                icon: "textformat",
                aliases: ["/h3", "/heading3"],
                keywords: ["heading", "subsection"],
                expansion: SlashCommandExpansion(text: "### ", cursorOffset: nil)
            ),
            SlashCommandItem(
                title: "Todo",
                subtitle: "Checklist item",
                icon: "checklist",
                aliases: ["/todo", "/task"],
                keywords: ["task", "checkbox", "checklist"],
                expansion: SlashCommandExpansion(text: "- [ ] ", cursorOffset: nil)
            ),
            SlashCommandItem(
                title: "Bullet List",
                subtitle: "Unordered list item",
                icon: "list.bullet",
                aliases: ["/bullet", "/bulleted"],
                keywords: ["list", "unordered"],
                expansion: SlashCommandExpansion(text: "- ", cursorOffset: nil)
            ),
            SlashCommandItem(
                title: "Numbered List",
                subtitle: "Ordered list item",
                icon: "list.number",
                aliases: ["/numbered", "/num"],
                keywords: ["list", "ordered"],
                expansion: SlashCommandExpansion(text: "1. ", cursorOffset: nil)
            ),
            SlashCommandItem(
                title: "Quote",
                subtitle: "Block quote",
                icon: "quote.opening",
                aliases: ["/quote"],
                keywords: ["blockquote", "callout"],
                expansion: SlashCommandExpansion(text: "> ", cursorOffset: nil)
            ),
            SlashCommandItem(
                title: "Divider",
                subtitle: "Horizontal rule",
                icon: "minus",
                aliases: ["/hr", "/divider"],
                keywords: ["horizontal", "rule", "separator"],
                expansion: SlashCommandExpansion(text: "---\n", cursorOffset: nil)
            ),
            SlashCommandItem(
                title: "Code Block",
                subtitle: "Fenced code block",
                icon: "curlybraces.square",
                aliases: ["/code"],
                keywords: ["fence", "pre", "snippet"],
                expansion: SlashCommandExpansion(text: "```\n\n```", cursorOffset: 4)
            ),
            SlashCommandItem(
                title: "Table",
                subtitle: "Two-column Markdown table",
                icon: "tablecells",
                aliases: ["/table"],
                keywords: ["grid", "data"],
                expansion: SlashCommandExpansion(
                    text: "| Column | Column |\n| --- | --- |\n|  |  |",
                    cursorOffset: 36
                )
            )
        ]

        private var isSlashMenuVisible: Bool {
            slashPopover?.isShown == true && !slashItems.isEmpty
        }

        private func applySlashCommandIfNeeded(in textView: NSTextView, at location: Int) -> Bool {
            guard let context = slashContext(in: textView, at: location),
                  let item = Self.slashCommands.first(where: { $0.aliases.contains(context.command) }) else { return false }
            return applySlashCommand(item, in: textView, range: context.range)
        }

        private func updateSlashMenu(in textView: NSTextView) {
            guard !isApplyingSlashCommand,
                  let context = slashContext(in: textView, at: textView.selectedRange().location) else {
                closeSlashMenu()
                return
            }

            let matches = filteredSlashCommands(for: context.command)
            guard !matches.isEmpty else {
                closeSlashMenu()
                return
            }

            slashQueryRange = context.range
            slashItems = matches
            slashSelectedIndex = min(slashSelectedIndex, matches.count - 1)
            showSlashMenu(relativeTo: context.range, in: textView)
        }

        private func slashContext(in textView: NSTextView, at location: Int) -> (range: NSRange, command: String)? {
            let selectedRange = textView.selectedRange()
            guard selectedRange.length == 0, selectedRange.location == location else { return nil }

            let nsText = textView.string as NSString
            guard location <= nsText.length else { return nil }

            var lineStart = 0
            if location > 0 {
                let prefixRange = NSRange(location: 0, length: location)
                let newline = nsText.range(of: "\n", options: .backwards, range: prefixRange)
                if newline.location != NSNotFound {
                    lineStart = newline.location + 1
                }
            }

            let typedLength = location - lineStart
            guard typedLength >= 1 else { return nil }

            let typed = nsText.substring(with: NSRange(location: lineStart, length: typedLength))
            let indentLength = typed.prefix { $0 == " " || $0 == "\t" }.count
            let command = String(typed.dropFirst(indentLength)).lowercased()
            guard command.hasPrefix("/"),
                  !command.dropFirst().contains(where: { $0.isWhitespace }) else { return nil }

            let commandStart = lineStart + indentLength
            return (NSRange(location: commandStart, length: location - commandStart), command)
        }

        private func filteredSlashCommands(for command: String) -> [SlashCommandItem] {
            let query = String(command.dropFirst()).lowercased()
            guard !query.isEmpty else { return Self.slashCommands }

            return Self.slashCommands.filter { item in
                if item.aliases.contains(where: { $0.dropFirst().hasPrefix(query) }) { return true }
                if item.title.lowercased().contains(query) { return true }
                if item.subtitle.lowercased().contains(query) { return true }
                return item.keywords.contains { $0.lowercased().contains(query) }
            }
        }

        private func showSlashMenu(relativeTo range: NSRange, in textView: NSTextView) {
            let popover = slashPopover ?? NSPopover()
            popover.behavior = .semitransient
            popover.animates = false
            popover.contentSize = NSSize(width: 260, height: min(280, 48 + slashItems.count * 43))
            popover.contentViewController = NSHostingController(rootView: SlashCommandMenuView(
                items: slashItems,
                selectedIndex: slashSelectedIndex
            ))
            slashPopover = popover

            let rect = caretRect(for: range, in: textView)
            if popover.isShown {
                popover.positioningRect = rect
            } else {
                popover.show(relativeTo: rect, of: textView, preferredEdge: .maxY)
            }
        }

        private func caretRect(for range: NSRange, in textView: NSTextView) -> NSRect {
            guard let window = textView.window else {
                return textView.visibleRect
            }

            let screenRect = textView.firstRect(forCharacterRange: range, actualRange: nil)
            guard !screenRect.isEmpty else {
                return textView.visibleRect
            }

            let windowRect = window.convertFromScreen(screenRect)
            var viewRect = textView.convert(windowRect, from: nil)
            viewRect.size.width = max(2, viewRect.size.width)
            viewRect.size.height = max(18, viewRect.size.height)
            return viewRect
        }

        private func moveSlashSelection(_ delta: Int) {
            guard !slashItems.isEmpty else { return }
            slashSelectedIndex = min(max(0, slashSelectedIndex + delta), slashItems.count - 1)
            if let textView {
                showSlashMenu(relativeTo: slashQueryRange ?? textView.selectedRange(), in: textView)
            }
        }

        private func commitSlashSelection() -> Bool {
            guard let textView,
                  !slashItems.isEmpty,
                  slashSelectedIndex < slashItems.count,
                  let range = slashQueryRange else { return false }
            return applySlashCommand(slashItems[slashSelectedIndex], in: textView, range: range)
        }

        private func applySlashCommand(_ item: SlashCommandItem, in textView: NSTextView, range: NSRange) -> Bool {
            isApplyingSlashCommand = true
            textView.insertText(item.expansion.text, replacementRange: range)
            let replacementLength = (item.expansion.text as NSString).length
            let selectionLocation = range.location + (item.expansion.cursorOffset ?? replacementLength)
            textView.setSelectedRange(NSRange(location: selectionLocation, length: 0))
            isApplyingSlashCommand = false
            closeSlashMenu()
            return true
        }

        private func closeSlashMenu() {
            slashPopover?.close()
            slashPopover = nil
            slashQueryRange = nil
            slashItems = []
            slashSelectedIndex = 0
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

        // MARK: - Image drag & drop

        private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "svg", "webp", "bmp", "tiff"]

        func textView(_ textView: NSTextView, performDragOperation draggingInfo: NSDraggingInfo) -> Bool {
            guard let items = draggingInfo.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
                .urlReadingFileURLsOnly: true
            ]) as? [URL] else { return false }

            let images = items.filter { Self.imageExtensions.contains($0.pathExtension.lowercased()) }
            guard !images.isEmpty else { return false }

            let dropPoint = textView.convert(draggingInfo.draggingLocation, from: nil)
            let charIndex = textView.characterIndexForInsertion(at: dropPoint)
            var insertText = ""
            for url in images {
                let name = url.lastPathComponent
                // Try relative path if we have a source file context
                let path = url.path
                insertText += "![\(name)](\(path))\n"
            }
            textView.insertText(insertText, replacementRange: NSRange(location: charIndex, length: 0))
            return true
        }

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

private struct SlashCommandExpansion {
    let text: String
    let cursorOffset: Int?
}

private struct SlashCommandItem: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let aliases: [String]
    let keywords: [String]
    let expansion: SlashCommandExpansion

    static func == (lhs: SlashCommandItem, rhs: SlashCommandItem) -> Bool {
        lhs.id == rhs.id
    }
}

private struct SlashCommandMenuView: View {
    let items: [SlashCommandItem]
    let selectedIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "command")
                    .font(.system(size: 10, weight: .semibold))
                Text("Insert")
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                Spacer()
                Text("↑↓ ↵")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 5)

            Divider().opacity(0.45)

            VStack(spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    SlashCommandMenuRow(
                        item: item,
                        isSelected: index == selectedIndex
                    )
                }
            }
            .padding(5)
        }
        .frame(width: 260, alignment: .topLeading)
        .background(.regularMaterial)
    }
}

private struct SlashCommandMenuRow: View {
    let item: SlashCommandItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.icon)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)

                Text(item.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(item.aliases.first ?? "")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.13) : Color.clear)
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
