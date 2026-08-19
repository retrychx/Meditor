import AppKit
import WebKit
import Observation

/// Coordinates exporting the current preview to HTML or PDF.
///
/// The preview panel registers its `WKWebView` instance here at mount time
/// so the toolbar (which lives outside the preview hierarchy) can trigger
/// exports without holding a direct reference to the webview.
@Observable
final class PreviewExporter: PreviewExporterProtocol {
    /// Set by `MarkdownWebPreview` when the webview is created. Cleared on dismantle.
    @ObservationIgnored
    weak var webView: WKWebView?

    /// True when there is a registered webview that can be exported.
    var isExportAvailable: Bool { webView != nil }

    enum ExportFormat {
        case html
        case pdf
        case image
        case markdown
    }

    enum ExportError: LocalizedError {
        case noWebView
        case javaScriptFailed(String)
        case pdfGenerationFailed(String)
        case snapshotFailed(String)

        var errorDescription: String? {
            switch self {
            case .noWebView: return L("export.err.noWebView")
            case .javaScriptFailed(let m): return L("export.err.js", m)
            case .pdfGenerationFailed(let m): return L("export.err.pdf", m)
            case .snapshotFailed(let m): return L("export.err.image", m)
            }
        }
    }

    /// Show a save panel and export the current preview to the chosen format.
    /// - Parameters:
    ///   - format: `.html` or `.pdf`.
    ///   - suggestedName: filename without extension shown in the save panel.
    ///   - completion: called on the main queue with `Result<URL, ExportError>`.
    func export(format: ExportFormat,
                suggestedName: String,
                completion: @escaping (Result<URL, ExportError>) -> Void) {
        export(format: format, suggestedName: suggestedName, pdfOptions: nil, completion: completion)
    }

    /// 带 PDF 选项的导出入口（功能9：纸张/边距/页眉页脚/封面）。
    /// pdfOptions 仅在 format == .pdf 时生效。
    func export(format: ExportFormat,
                suggestedName: String,
                pdfOptions: PDFExportOptions?,
                completion: @escaping (Result<URL, ExportError>) -> Void) {
        guard let webView = webView else {
            completion(.failure(.noWebView))
            return
        }

        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        switch format {
        case .html:
            savePanel.title = "Export as HTML"
            savePanel.nameFieldStringValue = suggestedName + ".html"
            savePanel.allowedContentTypes = [.html]
        case .pdf:
            savePanel.title = "Export as PDF"
            savePanel.nameFieldStringValue = suggestedName + ".pdf"
            savePanel.allowedContentTypes = [.pdf]
        case .image:
            savePanel.title = "Export as Image"
            savePanel.nameFieldStringValue = suggestedName + ".png"
            savePanel.allowedContentTypes = [.png]
        case .markdown:
            savePanel.title = "Export as Markdown"
            savePanel.nameFieldStringValue = suggestedName + ".md"
            savePanel.allowedContentTypes = [.plainText]
        }

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            switch format {
            case .html:
                Self.exportHTML(webView: webView, to: url, completion: completion)
            case .pdf:
                Self.exportPDF(webView: webView, to: url, title: suggestedName,
                               options: pdfOptions, completion: completion)
            case .image:
                Self.exportImage(webView: webView, to: url, completion: completion)
            case .markdown:
                Self.exportMarkdown(webView: webView, to: url, completion: completion)
            }
        }
    }

    // MARK: - HTML export

    private static func exportHTML(webView: WKWebView,
                                   to url: URL,
                                   completion: @escaping (Result<URL, ExportError>) -> Void) {
        let title = url.deletingPathExtension().lastPathComponent
        let escapedTitle = title.replacingOccurrences(of: "\\", with: "\\\\")
                                .replacingOccurrences(of: "'", with: "\\'")
        let js = "window.MEditor && window.MEditor.getRenderedHTML('\(escapedTitle)')"
        webView.evaluateJavaScript(js) { result, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(.javaScriptFailed(error.localizedDescription)))
                    return
                }
                guard let html = result as? String, !html.isEmpty else {
                    completion(.failure(.javaScriptFailed("empty result")))
                    return
                }
                do {
                    try html.write(to: url, atomically: true, encoding: .utf8)
                    completion(.success(url))
                } catch {
                    completion(.failure(.javaScriptFailed(error.localizedDescription)))
                }
            }
        }
    }

    // MARK: - Markdown export (HTML → Markdown via turndown-style JS)

    private static func exportMarkdown(webView: WKWebView,
                                       to url: URL,
                                       completion: @escaping (Result<URL, ExportError>) -> Void) {
        // Extract the HTML body content, then do a basic HTML→Markdown conversion in JS.
        // Elements with inline style attributes are preserved as raw HTML in the output.
        let js = """
        (function() {
            function h2m(el, indent) {
                indent = indent || '';
                var md = '';
                el.childNodes.forEach(function(node) {
                    if (node.nodeType === 3) {
                        // 折叠空白为单空格（模拟浏览器渲染）；纯空白节点（标签间的换行/缩进）
                        // 直接丢弃，否则会作为前导空格污染行首，导致 ## 标题被当成代码块
                        var t = node.textContent.replace(/\\s+/g, ' ');
                        if (t.trim() !== '') md += t;
                        return;
                    }
                    if (node.nodeType !== 1) return;
                    var tag = node.tagName.toLowerCase();
                    // 跳过脚本/样式/模板，避免 JS/CSS 源码混入 markdown
                    if (tag === 'script' || tag === 'style' || tag === 'noscript' || tag === 'template') return;
                    // 带 inline style 的元素保留为 raw HTML，但 <pre> 例外（走下方代码块转换更干净）；
                    // 前后补空行，确保与相邻 markdown 块正确分隔，否则后续 ### 标题会紧贴而不渲染
                    if (node.getAttribute('style') && tag !== 'pre') {
                        md += '\\n\\n' + node.outerHTML + '\\n\\n';
                        return;
                    }
                    if (tag === 'h1') md += '# ' + h2m(node, indent).trim() + '\\n\\n';
                    else if (tag === 'h2') md += '## ' + h2m(node, indent).trim() + '\\n\\n';
                    else if (tag === 'h3') md += '### ' + h2m(node, indent).trim() + '\\n\\n';
                    else if (tag === 'h4') md += '#### ' + h2m(node, indent).trim() + '\\n\\n';
                    else if (tag === 'h5') md += '##### ' + h2m(node, indent).trim() + '\\n\\n';
                    else if (tag === 'h6') md += '###### ' + h2m(node, indent).trim() + '\\n\\n';
                    else if (tag === 'p') md += h2m(node, indent).trim() + '\\n\\n';
                    else if (tag === 'br') md += '\\n';
                    // 用 HTML 标签而非 **/*：中文标点边界下 markdown 的 **粗体** 常无法闭合渲染，
                    // inline HTML 在 markdown 中通用且渲染可靠
                    else if (tag === 'strong' || tag === 'b') md += '<strong>' + h2m(node, indent) + '</strong>';
                    else if (tag === 'em' || tag === 'i') md += '<em>' + h2m(node, indent) + '</em>';
                    else if (tag === 'code' && node.parentElement && node.parentElement.tagName === 'PRE') md += h2m(node, indent);
                    else if (tag === 'code') md += '`' + h2m(node, indent) + '`';
                    else if (tag === 'pre') {
                        var code = node.querySelector('code');
                        var lang = '';
                        if (code) { var cls = code.className.match(/language-(\\w+)/); if (cls) lang = cls[1]; }
                        md += '```' + lang + '\\n' + (code || node).textContent + '\\n```\\n\\n';
                    }
                    else if (tag === 'a') md += '[' + h2m(node, indent) + '](' + (node.getAttribute('href') || '') + ')';
                    else if (tag === 'img') md += '![' + (node.getAttribute('alt') || '') + '](' + (node.getAttribute('src') || '') + ')';
                    else if (tag === 'ul') {
                        var lis = node.querySelectorAll(':scope > li');
                        lis.forEach(function(li) {
                            var liText = '';
                            var subList = '';
                            li.childNodes.forEach(function(c) {
                                if (c.nodeType === 1 && (c.tagName === 'UL' || c.tagName === 'OL')) {
                                    subList += h2m(c, indent + '  ');
                                } else if (c.nodeType === 1) {
                                    liText += h2m(c, indent);
                                } else if (c.nodeType === 3) {
                                    liText += c.textContent;
                                }
                            });
                            md += indent + '- ' + liText.trim() + '\\n';
                            if (subList) md += subList;
                        });
                        if (!indent) md += '\\n';
                    }
                    else if (tag === 'ol') {
                        var i = 1;
                        var olis = node.querySelectorAll(':scope > li');
                        olis.forEach(function(li) {
                            var liText = '';
                            var subList = '';
                            li.childNodes.forEach(function(c) {
                                if (c.nodeType === 1 && (c.tagName === 'UL' || c.tagName === 'OL')) {
                                    subList += h2m(c, indent + '  ');
                                } else if (c.nodeType === 1) {
                                    liText += h2m(c, indent);
                                } else if (c.nodeType === 3) {
                                    liText += c.textContent;
                                }
                            });
                            md += indent + i + '. ' + liText.trim() + '\\n';
                            if (subList) md += subList;
                            i++;
                        });
                        if (!indent) md += '\\n';
                    }
                    else if (tag === 'blockquote') {
                        var inner = h2m(node, indent).trim();
                        inner.split('\\n').forEach(function(line) {
                            md += '> ' + line + '\\n';
                        });
                        md += '\\n';
                    }
                    else if (tag === 'hr') md += '---\\n\\n';
                    else if (tag === 'table') {
                        var rows = node.querySelectorAll('tr');
                        rows.forEach(function(row, ri) {
                            var cells = row.querySelectorAll('th, td');
                            var line = '|';
                            cells.forEach(function(c) { line += ' ' + h2m(c, indent).trim() + ' |'; });
                            md += line + '\\n';
                            if (ri === 0) {
                                md += '|';
                                cells.forEach(function() { md += ' --- |'; });
                                md += '\\n';
                            }
                        });
                        md += '\\n';
                    }
                    else md += h2m(node, indent);
                });
                return md;
            }
            // 优先从主内容区导出，跳过侧边栏/目录导航等非正文容器；无则退回整个 body
            var root = document.querySelector('main, .main, article, [role="main"]') || document.body;
            return h2m(root, '');
        })();
        """
        webView.evaluateJavaScript(js) { result, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(.javaScriptFailed(error.localizedDescription)))
                    return
                }
                guard let markdown = result as? String, !markdown.isEmpty else {
                    completion(.failure(.javaScriptFailed("empty result")))
                    return
                }
                // 清理：去行尾空格、折叠 3+ 连续空行为一个空行、去首尾空白
                let cleaned = markdown
                    .replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
                    .replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
                do {
                    try cleaned.write(to: url, atomically: true, encoding: .utf8)
                    completion(.success(url))
                } catch {
                    completion(.failure(.javaScriptFailed(error.localizedDescription)))
                }
            }
        }
    }

    // MARK: - PDF export

    private static func exportPDF(webView: WKWebView,
                                  to url: URL,
                                  title: String,
                                  options: PDFExportOptions?,
                                  completion: @escaping (Result<URL, ExportError>) -> Void) {
        // 默认选项不需要后处理：不注入 @page 样式（保留 WebKit 自带分页/边距），
        // 也跳过 decorate——重绘会丢链接 annotation（见 postProcessPDFData）。
        let needsDecoration = options.map { !$0.isDefault } ?? false
        captureViaReload(webView: webView, extraCSS: needsDecoration ? options?.printCSS() : nil) { pdfData in
            guard let pdfData else {
                completion(.failure(.pdfGenerationFailed("createPDF returned no data")))
                return
            }
            // 装饰（重排/封面/页眉页脚）与写盘放后台队列：百页文档主线程同步装饰会
            // 卡 UI，且重绘过程瞬时内存翻倍。completion 统一回主线程。
            DispatchQueue.global(qos: .userInitiated).async {
                let finalData = Self.postProcessPDFData(pdfData, options: options, title: title)
                do {
                    try finalData.write(to: url)
                    DispatchQueue.main.async { completion(.success(url)) }
                } catch {
                    DispatchQueue.main.async {
                        completion(.failure(.pdfGenerationFailed(error.localizedDescription)))
                    }
                }
            }
        }
    }

    /// PDF 后处理决策（拆成纯函数便于单测）：
    /// 默认选项直接返回原数据——PDFDocumentDecorator 走 drawPDFPage 重绘，
    /// 不保留链接 annotation，默认排版没必要付出「导出 PDF 链接全灭」的代价；
    /// 非默认选项才装饰，装饰失败回退原始数据。
    static func postProcessPDFData(_ data: Data, options: PDFExportOptions?, title: String) -> Data {
        guard let options, !options.isDefault else { return data }
        return PDFDocumentDecorator.decorate(data: data, options: options, title: title) ?? data
    }

    /// Reloads the webview content via loadHTMLString (bypasses file:// createPDF limitation),
    /// calls createPDF, then restores the original file URL.
    /// - Parameter extraCSS: 追加注入 </head> 前的样式（PDF 导出用它声明 @page 纸张尺寸）。
    private static func captureViaReload(webView: WKWebView,
                                         extraCSS: String? = nil,
                                         completion: @escaping (Data?) -> Void) {
        webView.evaluateJavaScript("document.documentElement.outerHTML") { result, _ in
            guard let html = result as? String else { completion(nil); return }
            let originalURL = webView.url
            let cacheDir = originalURL?.deletingLastPathComponent()

            // Determine if this is a user HTML file (not MEditor's markdown preview cache).
            // For HTML files: keep scripts so JS-rendered content (charts etc.) works.
            // For markdown preview: strip scripts to prevent MEditor.boot() wiping #content.
            let isMEditorCache = originalURL?.path.contains("com.meditor.preview") == true
            var processed = inlineCSS(html: html, baseDir: cacheDir)
            if isMEditorCache {
                processed = stripScripts(processed)
            }
            if let extraCSS {
                processed = injectCSS(processed, css: extraCSS)
            }

            let baseURL = isMEditorCache ? nil : originalURL?.deletingLastPathComponent()
            // Extra delay for HTML files with JS rendering (charts need time to paint).
            let delay: TimeInterval = isMEditorCache ? 0 : 1.5

            let delegate = OneShotNavDelegate(delay: delay) {
                let config = WKPDFConfiguration()
                webView.createPDF(configuration: config) { pdfResult in
                    DispatchQueue.main.async {
                        // 仅当原始 URL 确为 file:// 时才用 loadFileURL 恢复预览；
                        // 否则（about:blank / loadHTMLString 来源等）loadFileURL 会抛
                        // NSInvalidArgumentException 导致整个 app abort，这里用 reload 兜底。
                        if let originalURL, originalURL.isFileURL, let cacheDir {
                            webView.loadFileURL(originalURL, allowingReadAccessTo: cacheDir)
                        } else {
                            webView.reload()
                        }
                        completion(try? pdfResult.get())
                    }
                }
            }
            objc_setAssociatedObject(webView, &OneShotNavDelegate.key, delegate, .OBJC_ASSOCIATION_RETAIN)
            webView.navigationDelegate = delegate
            webView.loadHTMLString(processed, baseURL: baseURL)
        }
    }

    private static func inlineCSS(html: String, baseDir: URL?) -> String {
        guard let baseDir else { return html }
        var result = html
        let pattern = try? NSRegularExpression(pattern: #"<link\b[^>]*\bhref="([^"]+\.css)"[^>]*/?>"#)
        for match in (pattern?.matches(in: result, range: NSRange(result.startIndex..., in: result)) ?? []).reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let hrefRange = Range(match.range(at: 1), in: result) else { continue }
            let fileURL = baseDir.appendingPathComponent(String(result[hrefRange]))
            if let css = try? String(contentsOf: fileURL, encoding: .utf8) {
                result.replaceSubrange(fullRange, with: "<style>\(css)</style>")
            }
        }
        return result
    }

    /// 在 </head> 前注入一段样式；没有 </head> 时兜底拼到文档头。
    /// 纯字符串处理，拆出来便于单测。
    static func injectCSS(_ html: String, css: String) -> String {
        let style = "<style>\(css)</style>"
        if let range = html.range(of: "</head>", options: .caseInsensitive) {
            var result = html
            result.insert(contentsOf: style, at: range.lowerBound)
            return result
        }
        return style + html
    }

    private static func stripScripts(_ html: String) -> String {
        // Remove all <script ...>...</script> blocks — content is already rendered in DOM.
        let pattern = try? NSRegularExpression(
            pattern: #"<script\b[^>]*>[\s\S]*?</script>"#,
            options: .caseInsensitive
        )
        guard let pattern else { return html }
        return pattern.stringByReplacingMatches(
            in: html,
            range: NSRange(html.startIndex..., in: html),
            withTemplate: ""
        )
    }

    // MARK: - Image export (high-resolution)

    private static func exportImage(webView: WKWebView,
                                    to url: URL,
                                    completion: @escaping (Result<URL, ExportError>) -> Void) {
        webView.evaluateJavaScript(
            "[document.documentElement.scrollWidth, document.documentElement.scrollHeight]"
        ) { result, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(.snapshotFailed(error.localizedDescription)))
                    return
                }
                let dims = result as? [CGFloat] ?? []
                let contentW = max(dims.count > 0 ? dims[0] : webView.bounds.width, 100)
                let contentH = max(dims.count > 1 ? dims[1] : webView.bounds.height, 100)

                captureViaReload(webView: webView) { pdfData in
                    guard let pdfData else {
                        completion(.failure(.snapshotFailed("createPDF returned no data")))
                        return
                    }
                    guard let image = rasterizePDF(pdfData,
                                                   size: CGSize(width: contentW, height: contentH),
                                                   scale: 2.0),
                          let tiff = image.tiffRepresentation,
                          let bitmap = NSBitmapImageRep(data: tiff),
                          let png = bitmap.representation(using: .png, properties: [:]) else {
                        completion(.failure(.snapshotFailed("Failed to rasterize PDF")))
                        return
                    }
                    do {
                        try png.write(to: url)
                        completion(.success(url))
                    } catch {
                        completion(.failure(.snapshotFailed(error.localizedDescription)))
                    }
                }
            }
        }
    }
}

// MARK: - One-shot navigation delegate for export reload

private final class OneShotNavDelegate: NSObject, WKNavigationDelegate {
    static var key: UInt8 = 0
    private let delay: TimeInterval
    private let onFinish: () -> Void

    init(delay: TimeInterval = 0, onFinish: @escaping () -> Void) {
        self.delay = delay
        self.onFinish = onFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.navigationDelegate = nil
        objc_setAssociatedObject(webView, &OneShotNavDelegate.key, nil, .OBJC_ASSOCIATION_RETAIN)
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.onFinish() }
        } else {
            onFinish()
        }
    }
}

private func rasterizePDF(_ data: Data, size: CGSize, scale: CGFloat) -> NSImage? {
        guard let provider = CGDataProvider(data: data as CFData),
              let pdf = CGPDFDocument(provider),
              let page = pdf.page(at: 1) else { return nil }

        let pixelW = Int(size.width * scale)
        let pixelH = Int(size.height * scale)
        guard let ctx = CGContext(
            data: nil,
            width: pixelW, height: pixelH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: pixelW, height: pixelH))
        ctx.scaleBy(x: scale, y: scale)
        ctx.drawPDFPage(page)

        guard let cgImage = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: size)
}