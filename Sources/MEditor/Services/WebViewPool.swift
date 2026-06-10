import WebKit

/// Pre-warms a WKWebView with the preview template loaded so the first
/// file open gets instant rendering without the ~200ms cold-start penalty.
///
/// Usage: call `WebViewPool.shared.warmUp()` at app launch.
/// When MarkdownWebPreview needs a webview, call `dequeue()` instead of
/// creating a new one. If the pool is empty, falls back to fresh creation.
@MainActor
final class WebViewPool {
    static let shared = WebViewPool()

    private var warmedView: WKWebView?
    private var isReady = false

    private init() {}

    /// Call once at app launch (e.g. in onAppear). Pre-creates a WKWebView
    /// and loads the template so it's ready when the user opens a file.
    func warmUp() {
        guard warmedView == nil else { return }

        let config = WKWebViewConfiguration()
        config.userContentController = WKUserContentController()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        webView.setValue(false, forKey: "drawsBackground")

        // Load the template with empty content
        guard let resourcesRoot = PreviewResourceLocator.resourcesRoot(),
              let templateURL = PreviewResourceLocator.templateURL(),
              let template = try? String(contentsOf: templateURL, encoding: .utf8) else {
            return
        }

        let html = template
            .replacingOccurrences(of: "{{INITIAL_THEME}}", with: "github")
            .replacingOccurrences(of: "{{INITIAL_CONTENT_JSON}}", with: "\"\"")

        let cacheDir: URL = {
            let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            return cachesDir.appendingPathComponent("com.meditor.preview", isDirectory: true)
        }()

        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let fileURL = cacheDir.appendingPathComponent("preview-warm.html")
        try? html.write(to: fileURL, atomically: true, encoding: .utf8)

        webView.loadFileURL(fileURL, allowingReadAccessTo: cacheDir)
        warmedView = webView
    }

    /// Dequeue a pre-warmed webview. Returns nil if none available
    /// (caller should create fresh). The pool refills on next idle.
    func dequeue() -> WKWebView? {
        guard let view = warmedView else { return nil }
        warmedView = nil
        // Schedule a refill for the next file open
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.warmUp()
        }
        return view
    }
}
