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

    // MARK: - Image paste / drop context

    /// 当前文档 URL（图片落盘位置与相对路径的基准），由 NativeEditorView 同步。
    var documentURL: URL?
    /// 工作区根目录（判断拖入文件是否已在工作区内），由 NativeEditorView 同步。
    var workspaceRoot: URL?
    /// 图片落盘失败时上报错误（toast）。
    var onImageError: ((String) -> Void)?
    let imageAssetService = ImageAssetService()

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
                // 带参数命令（/ask、/polish 等）的空格是参数分隔符（「/ask 问题」），
                // 放行插入不提交命令；Enter 提交路径不变
                if text == " ", slashHandler.isArgumentContext(in: textView, at: range.location) {
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
        if slashHandler.isMenuVisible {
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
        // Esc：有选区时收起选区（光标落到选区末尾），选区浮动操作条随之关闭；
        // 焦点保持在编辑器，无需额外关条 UI。IME 组合态（hasMarkedText）放行，
        // 让 Esc 归输入法取消候选，不收选区。
        if commandSelector == #selector(NSResponder.cancelOperation(_:)),
           !textView.hasMarkedText(),
           textView.selectedRange().length > 0 {
            textView.setSelectedRange(NSRange(location: NSMaxRange(textView.selectedRange()), length: 0))
            return true
        }
        return false
    }

    // MARK: - Image paste

    /// ⌘V 入口（MEditorTextView.paste 调用）：粘贴板含图片时落盘并在光标处插入
    /// Markdown 引用。返回 false = 未处理（无图片 / 无文档上下文 / 落盘失败），
    /// 调用方回退系统默认粘贴。insertText 走 textView 常规编辑路径，自动注册 undo。
    @discardableResult
    func pasteImageFromPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        guard let textView, let documentURL else { return false }

        // 1) file URL 优先（Finder ⌘C / Photos 等组合 flavor 源）：走
        //    referenceForDroppedFile 的工作区判定——工作区内直接引用原文件，
        //    避免把已有文件落盘重编码一份
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let images = urls.filter { ImageAssetService.imageExtensions.contains($0.pathExtension.lowercased()) }
        if !images.isEmpty,
           insertDroppedImages(images, in: textView, at: textView.selectedRange().location) {
            return true
        }

        // 2) 粘贴板直接携带的图片数据兜底（截图等无文件来源的场景）
        if let (data, ext) = Self.imageData(from: pasteboard) {
            do {
                let result = try imageAssetService.savePastedImage(
                    data: data, fileExtension: ext, documentURL: documentURL
                )
                insertMarkdownReference(result.markdown, in: textView,
                                        at: textView.selectedRange().location)
                return true
            } catch {
                onImageError?(error.localizedDescription)
                return false
            }
        }

        return false
    }

    /// 从粘贴板提取图片数据：优先 PNG，其次 TIFF（统一转 PNG 落盘）。
    static func imageData(from pasteboard: NSPasteboard) -> (Data, String)? {
        if let data = pasteboard.data(forType: .png) { return (data, "png") }
        if let tiff = pasteboard.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return (png, "png")
        }
        return nil
    }

    // MARK: - Image drag & drop

    func textView(_ textView: NSTextView, performDragOperation draggingInfo: NSDraggingInfo) -> Bool {
        guard let items = draggingInfo.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else { return false }

        let images = items.filter { ImageAssetService.imageExtensions.contains($0.pathExtension.lowercased()) }
        guard !images.isEmpty else { return false }

        let dropPoint = textView.convert(draggingInfo.draggingLocation, from: nil)
        let charIndex = textView.characterIndexForInsertion(at: dropPoint)
        return insertDroppedImages(images, in: textView, at: charIndex)
    }

    /// 拖入/粘贴文件引用的共用路径：工作区内直接引用（不复制），否则复制进 assets/。
    /// 部分失败时插入成功项并 toast 失败数；全部失败返回 false（回退默认行为）。
    private func insertDroppedImages(_ images: [URL], in textView: NSTextView, at charIndex: Int) -> Bool {
        guard let documentURL else { return false }
        var insertionText = ""
        var failed = 0
        for url in images {
            do {
                let result = try imageAssetService.referenceForDroppedFile(
                    url, documentURL: documentURL, workspaceRoot: workspaceRoot
                )
                insertionText += result.markdown + "\n"
            } catch {
                failed += 1
            }
        }
        if failed > 0 { onImageError?(L("image.dropFailed", failed)) }
        guard !insertionText.isEmpty else { return false }
        insertMarkdownReference(insertionText, in: textView, at: charIndex)
        return true
    }

    /// insertText 走 NSTextView 常规编辑路径：触发 delegate、注册 undo。
    private func insertMarkdownReference(_ markdown: String, in textView: NSTextView, at charIndex: Int) {
        textView.insertText(markdown, replacementRange: NSRange(location: charIndex, length: 0))
    }

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
