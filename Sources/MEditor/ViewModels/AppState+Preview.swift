import Foundation

// MARK: - Preview forwarding

extension AppState {

    var previewContent: String             { previewManager.content }
    var previewContentRevision: Int        { previewManager.contentRevision }
    var previewLanguage: EditorLanguage    { previewManager.language }
    var previewMode: PreviewMode           { previewManager.mode }
    var previewHTMLFileURL: URL?           { previewManager.htmlFileURL }
    var previewReloadToken: Int            { previewManager.reloadToken }
    var previewExporter: PreviewExporter   { previewManager.exporter }
    var previewFindController: PreviewFindController { previewManager.findController }

    @discardableResult
    func clearPreview() -> Bool { previewManager.clear() }

    @discardableResult
    func showMarkdownPreview(content: String) -> Bool { previewManager.showMarkdown(content: content) }

    @discardableResult
    func showHTMLPreview(fileURL: URL) -> Bool { previewManager.showHTML(fileURL: fileURL) }

    func syncPreviewContent(from tab: EditorTab) { previewManager.sync(from: tab) }

    /// 指定文件落盘后，若正在 HTML 预览该文件则强制重新加载（方案 A）。
    func reloadHTMLPreviewIfShowing(_ url: URL) { previewManager.reloadHTML(url: url) }

    // MARK: - 改哪亮哪

    /// AI 落笔后：预览滚动到改动位置并脉冲高亮。
    /// sourceRange 为改动在 content（新文档）中的区间。
    func flashPreviewChange(sourceRange: Range<String.Index>, in content: String) {
        let startLine = Self.lineNumber(of: sourceRange.lowerBound, in: content)
        let endLine = Self.lineNumber(of: sourceRange.upperBound, in: content)
        requestPreviewScroll(to: startLine)
        // 预览随 contentRevision 异步重渲染（JS update 会重建 DOM），固定单次注入
        // 可能落在渲染前被清掉——注入两次覆盖渲染前后，重复注入幂等（动画重启）。
        for delay in [0.45, 1.25] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.previewExporter.webView?.evaluateJavaScript(
                    Self.changedPulseJS(start: startLine, end: endLine),
                    completionHandler: nil
                )
            }
        }
    }

    /// 字符位置 → 0-based 行号。
    /// 与渲染层对齐：render.js 的 data-source-line 是 0-based（collectHeadingLines
    /// push 的是 split('\n') 数组下标），编辑器 scrollToLine 也是 0-based。
    nonisolated static func lineNumber(of index: String.Index, in content: String) -> Int {
        content[..<index].filter { $0 == "\n" }.count
    }

    /// 脉冲高亮注入：给 data-source-line 落在 [start, end] 的块加琥珀色闪烁，
    /// 1.4s×2 后自动移除（幂等，重复注入安全）。
    /// 注意渲染层只有标题（h1-h6）带 data-source-line——非标题改动命中不到时，
    /// 回退到 start 之前最近的标题锚点（即改动所在小节的标题）。
    nonisolated static func changedPulseJS(start: Int, end: Int) -> String {
        """
        (function() {
            if (!document.getElementById('meditor-pulse-style')) {
                var st = document.createElement('style');
                st.id = 'meditor-pulse-style';
                st.textContent = '@keyframes meditorPulse{0%{background:rgba(255,190,40,.42)}100%{background:transparent}}.meditor-changed{animation:meditorPulse 1.4s ease-out 2;border-radius:6px}';
                document.head.appendChild(st);
            }
            var hits = [];
            var fallback = null, fallbackLine = -1;
            document.querySelectorAll('[data-source-line]').forEach(function(el) {
                var l = parseInt(el.getAttribute('data-source-line'), 10);
                if (l >= \(start) && l <= \(end)) {
                    hits.push(el);
                } else if (l >= 0 && l <= \(start) && l > fallbackLine) {
                    fallback = el; fallbackLine = l;
                }
            });
            if (hits.length === 0 && fallback) hits.push(fallback);
            hits.forEach(function(el) {
                el.classList.remove('meditor-changed');
                void el.offsetWidth;
                el.classList.add('meditor-changed');
            });
            setTimeout(function() {
                hits.forEach(function(el) { el.classList.remove('meditor-changed'); });
            }, 3200);
        })();
        """
    }
}
