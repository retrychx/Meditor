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
    }

    enum ExportError: LocalizedError {
        case noWebView
        case javaScriptFailed(String)
        case pdfGenerationFailed(String)
        case snapshotFailed(String)

        var errorDescription: String? {
            switch self {
            case .noWebView: return "Preview is not available."
            case .javaScriptFailed(let m): return "Export failed (JS): \(m)"
            case .pdfGenerationFailed(let m): return "PDF export failed: \(m)"
            case .snapshotFailed(let m): return "Image export failed: \(m)"
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
        }

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            switch format {
            case .html:
                Self.exportHTML(webView: webView, to: url, completion: completion)
            case .pdf:
                Self.exportPDF(webView: webView, to: url, completion: completion)
            case .image:
                Self.exportImage(webView: webView, to: url, completion: completion)
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

    // MARK: - PDF export

    private static func exportPDF(webView: WKWebView,
                                  to url: URL,
                                  completion: @escaping (Result<URL, ExportError>) -> Void) {
        captureViaReload(webView: webView) { pdfData in
            guard let pdfData else {
                completion(.failure(.pdfGenerationFailed("createPDF returned no data")))
                return
            }
            do {
                try pdfData.write(to: url)
                completion(.success(url))
            } catch {
                completion(.failure(.pdfGenerationFailed(error.localizedDescription)))
            }
        }
    }

    /// Reloads the webview content via loadHTMLString (bypasses file:// createPDF limitation),
    /// calls createPDF, then restores the original file URL.
    private static func captureViaReload(webView: WKWebView, completion: @escaping (Data?) -> Void) {
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

            let baseURL = isMEditorCache ? nil : originalURL?.deletingLastPathComponent()
            // Extra delay for HTML files with JS rendering (charts need time to paint).
            let delay: TimeInterval = isMEditorCache ? 0 : 1.5

            let delegate = OneShotNavDelegate(delay: delay) {
                let config = WKPDFConfiguration()
                webView.createPDF(configuration: config) { pdfResult in
                    DispatchQueue.main.async {
                        if let originalURL, let cacheDir {
                            webView.loadFileURL(originalURL, allowingReadAccessTo: cacheDir)
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