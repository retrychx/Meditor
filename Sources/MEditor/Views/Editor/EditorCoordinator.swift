import AppKit

/// Core coordinator for NativeEditorView. Handles NSTextViewDelegate, scroll sync,
/// AI text insertion, and drag & drop. Slash command logic delegates to SlashCommandHandler;
/// markdown shortcuts live in EditorMarkdownShortcuts.swift.
final class EditorCoordinator: NSObject, NSTextViewDelegate {
    var onContentChange: (String) -> Void
    var onCursorChange: ((Int, Int) -> Void)?
    var onVisibleTopLineChange: ((Int) -> Void)?
    var onSelectionChange: ((String) -> Void)?
    var onRangeChange: ((NSRange) -> Void)?
    var lastAcknowledgedContent: String = ""
    var lastAcknowledgedRevision: Int = 0
    var lastReplaceNonce: Int = 0
    var lastWriteBackNonce: Int = 0

    weak var textView: NSTextView? {
        didSet {
            highlighter.textView = textView
            slashHandler.textView = textView
        }
    }

    var scrollObserver: NSObjectProtocol?
    var lastAppliedTargetLine: Int = -1
    var lastAppliedRequestID: Int = -1
    var lastInsertRequestID: Int = 0
    var localRevisionPredictionActive = false
    var isProgrammaticChange = false

    let highlighter: EditorHighlightScheduler
    let scrollSync: EditorScrollSyncHandler
    let slashHandler = SlashCommandHandler()

    /// Slash AI 命令回调：由 NativeEditorView 在 makeCoordinator 后设置。
    var onSlashAIAction: ((SlashAIAction, String, NSRange) -> Void)? {
        get { slashHandler.onAIAction }
        set { slashHandler.onAIAction = newValue }
    }

    private var debounceTimer: Timer?
    private var pendingAutoClose: Character?
    private static let autoPairs: [Character: Character] = [
        "(": ")", "[": "]", "{": "}",
        "\"": "\"", "'": "'", "`": "`"
    ]

    init(onContentChange: @escaping (String) -> Void,
         onCursorChange: ((Int, Int) -> Void)?,
         onVisibleTopLineChange: ((Int) -> Void)?) {
        let hs = EditorHighlightScheduler()
        self.highlighter = hs
        self.scrollSync = EditorScrollSyncHandler(highlighter: hs)
        self.onContentChange = onContentChange
        self.onCursorChange = onCursorChange
        self.onVisibleTopLineChange = onVisibleTopLineChange
    }

    deinit {
        debounceTimer?.invalidate()
        slashHandler.closeMenu()
        if let observer = scrollObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Scroll the editor so the given 0-based source line is at the top (preview→editor sync).
    /// select = true 时（全局搜索跳转）额外把光标放到目标行行首，并用系统 Find 指示器
    /// 闪烁高亮整行——一次性视觉提示，不留持久选区。
    func scrollToLine(_ line: Int, select: Bool = false) {
        guard line >= 0,
              let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let scrollView = textView.enclosingScrollView else { return }
        let sid = PerformanceTracer.begin("EditorScrollToLine", log: PerformanceTracer.editor)
        highlighter.ensureLineOffsets(for: textView.string)
        let safeLine = min(line, max(0, highlighter.lineOffsets.count - 1))
        let charIndex = highlighter.lineOffsets[safeLine]
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: charIndex, length: 0),
            actualCharacterRange: nil
        )
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let targetY = rect.origin.y + textView.textContainerInset.height
        scrollSync.isProgrammaticScroll = true
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        if select {
            let nsString = textView.string as NSString
            let lineEnd = safeLine + 1 < highlighter.lineOffsets.count
                ? highlighter.lineOffsets[safeLine + 1]
                : nsString.length
            let lineRange = NSRange(location: charIndex, length: max(0, lineEnd - charIndex))
            textView.setSelectedRange(NSRange(location: charIndex, length: 0))
            textView.showFindIndicator(for: lineRange)
        }
        PerformanceTracer.end("EditorScrollToLine", log: PerformanceTracer.editor, id: sid)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.scrollSync.isProgrammaticScroll = false
        }
    }

    // MARK: - NSTextViewDelegate

    /// AI 写回前冲刷在途击键：击键后的预览防抖 Timer 捕获的是当时的旧文本，
    /// 若写回落在防抖窗口内，Timer 触发会把「不含写回」的旧文本回推给
    /// updateTabContent（两边 revision 恰好相等，updateNSView 不纠正），
    /// 导致 tab.content 回退、AI 改写静默丢失。这里作废旧 Timer 并回滚
    /// revision 预测增量——击键内容已在 textView 里，由写回自己的
    /// onContentChange 一并携带，不会丢。
    func flushPendingKeystroke() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        if localRevisionPredictionActive {
            localRevisionPredictionActive = false
            lastAcknowledgedRevision &-= 1
        }
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
        guard !isProgrammaticChange else { return true }
        if slashHandler.isApplyingCommand { return true }

        if let text, (text == " " || text == "\n"), range.length == 0 {
            if slashHandler.isMenuVisible {
                // /ask 的空格是 query 分隔符（「/ask 问题」），放行插入不提交命令；
                // Enter 提交路径不变
                if text == " ", slashHandler.isAskContext(in: textView, at: range.location) {
                    return true
                }
                return !slashHandler.commitSelection()
            }
            if slashHandler.applyIfNeeded(in: textView, at: range.location) {
                return false
            }
        }

        guard let text, text.count == 1,
              let char = text.first,
              let close = Self.autoPairs[char] else { return true }
        // Skip auto-close for symmetric pairs when preceded by an alphanumeric
        // (avoids inserting a closing quote/backtick when the user is finishing a word).
        if char == close {
            let ns = textView.string as NSString
            if range.location > 0 {
                let prev = ns.character(at: range.location - 1)
                if let scalar = Unicode.Scalar(prev), CharacterSet.alphanumerics.contains(scalar) {
                    return true
                }
            }
        }
        if range.length == 0 { pendingAutoClose = close }
        return true
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = textView, !isProgrammaticChange else { return }

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
        highlighter.rebuildLineOffsets(for: newContent)

        debounceTimer?.invalidate()
        let delay = Self.previewUpdateDebounce(for: newContent)
        debounceTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.localRevisionPredictionActive = false
                self.onContentChange(newContent)
            }
        }

        highlighter.scheduleHighlight(after: 0.3)
        slashHandler.updateMenu(in: textView)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let textView = textView else { return }
        let range = textView.selectedRange()
        onRangeChange?(range)
        if let onCursorChange = onCursorChange {
            let lineIdx = highlighter.lineIndex(for: range.location, in: textView.string)
            let lineStart = highlighter.lineOffsets[safe: lineIdx] ?? 0
            let column = max(1, range.location - lineStart + 1)
            onCursorChange(lineIdx + 1, column)
        }
        if let onSelectionChange = onSelectionChange {
            let text = range.length > 0
                ? (textView.string as NSString).substring(with: range)
                : ""
            onSelectionChange(text)
        }
        slashHandler.updateMenu(in: textView)
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard slashHandler.isMenuVisible else { return false }
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            slashHandler.moveSelection(-1)
            return true
        case #selector(NSResponder.moveDown(_:)):
            slashHandler.moveSelection(1)
            return true
        case #selector(NSResponder.insertNewline(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
             #selector(NSResponder.insertTab(_:)):
            return slashHandler.commitSelection()
        case #selector(NSResponder.cancelOperation(_:)):
            slashHandler.closeMenu()
            return true
        default:
            return false
        }
    }

    // MARK: - Image drag & drop

    func textView(_ textView: NSTextView, performDragOperation draggingInfo: NSDraggingInfo) -> Bool {
        guard let items = draggingInfo.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else { return false }

        let images = items.filter { Self.imageExtensions.contains($0.pathExtension.lowercased()) }
        guard !images.isEmpty else { return false }

        let dropPoint = textView.convert(draggingInfo.draggingLocation, from: nil)
        let charIndex = textView.characterIndexForInsertion(at: dropPoint)
        var insertionText = ""
        for url in images {
            // 路径做百分号编码：空格/括号不处理会破坏 Markdown 链接语法
            let encodedPath = url.path.addingPercentEncoding(
                withAllowedCharacters: Self.markdownLinkPathAllowed
            ) ?? url.path
            // alt 文本里的方括号会破坏图片语法，直接剔除
            let alt = url.lastPathComponent
                .replacingOccurrences(of: "[", with: "")
                .replacingOccurrences(of: "]", with: "")
            insertionText += "![\(alt)](\(encodedPath))\n"
        }
        textView.insertText(insertionText, replacementRange: NSRange(location: charIndex, length: 0))
        return true
    }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "svg", "webp", "bmp", "tiff"]
    /// urlPathAllowed 本身不含空格；再剔除 () 防止提前闭合 Markdown 链接。
    private static let markdownLinkPathAllowed: CharacterSet =
        CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "()"))

    private static func previewUpdateDebounce(for content: String) -> TimeInterval {
        let bytes = content.utf8.count
        switch bytes {
        case 0..<16 * 1024:         return 0.02
        case 16 * 1024..<64 * 1024: return 0.03
        case 64 * 1024..<256 * 1024: return 0.05
        default:                     return 0.08
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
