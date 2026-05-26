import AppKit
import WebKit
import Observation

/// Coordinates exporting the current preview to HTML or PDF.
///
/// The preview panel registers its `WKWebView` instance here at mount time
/// so the toolbar (which lives outside the preview hierarchy) can trigger
/// exports without holding a direct reference to the webview.
@Observable
final class PreviewExporter {
    /// Set by `MarkdownWebPreview` when the webview is created. Cleared on dismantle.
    @ObservationIgnored
    weak var webView: WKWebView?

    /// True when there is a registered webview that can be exported.
    var isExportAvailable: Bool { webView != nil }

    enum ExportFormat {
        case html
        case pdf
    }

    enum ExportError: LocalizedError {
        case noWebView
        case javaScriptFailed(String)
        case pdfGenerationFailed(String)

        var errorDescription: String? {
            switch self {
            case .noWebView: return "Preview is not available."
            case .javaScriptFailed(let m): return "Export failed (JS): \(m)"
            case .pdfGenerationFailed(let m): return "PDF export failed: \(m)"
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
        savePanel.title = format == .html ? "Export as HTML" : "Export as PDF"
        savePanel.nameFieldStringValue = suggestedName + (format == .html ? ".html" : ".pdf")
        savePanel.allowedContentTypes = format == .html
            ? [.html]
            : [.pdf]

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            switch format {
            case .html:
                Self.exportHTML(webView: webView, to: url, completion: completion)
            case .pdf:
                Self.exportPDF(webView: webView, to: url, completion: completion)
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
        let config = WKPDFConfiguration()
        webView.createPDF(configuration: config) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    do {
                        try data.write(to: url)
                        completion(.success(url))
                    } catch {
                        completion(.failure(.pdfGenerationFailed(error.localizedDescription)))
                    }
                case .failure(let error):
                    completion(.failure(.pdfGenerationFailed(error.localizedDescription)))
                }
            }
        }
    }
}
