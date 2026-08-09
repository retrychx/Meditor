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
        // 预览随 contentRevision 异步重渲染，等渲染完成再注入高亮
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.previewExporter.webView?.evaluateJavaScript(
                Self.changedPulseJS(start: startLine, end: endLine),
                completionHandler: nil
            )
        }
    }

    /// 字符位置 → 1-based 行号（与渲染层的 data-source-line 对齐）。
    nonisolated static func lineNumber(of index: String.Index, in content: String) -> Int {
        content[..<index].filter { $0 == "\n" }.count + 1
    }

    /// 脉冲高亮注入：给 data-source-line 落在 [start, end] 的块加琥珀色闪烁，
    /// 1.4s×2 后自动移除（幂等，重复注入安全）。
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
            document.querySelectorAll('[data-source-line]').forEach(function(el) {
                var l = parseInt(el.getAttribute('data-source-line'), 10);
                if (l >= \(start) && l <= \(end)) {
                    el.classList.remove('meditor-changed');
                    void el.offsetWidth;
                    el.classList.add('meditor-changed');
                    hits.push(el);
                }
            });
            setTimeout(function() {
                hits.forEach(function(el) { el.classList.remove('meditor-changed'); });
            }, 3200);
        })();
        """
    }
}
