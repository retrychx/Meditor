import WebKit

/// Pre-warms a WKWebView with the full preview template + assets loaded,
/// so the first file open gets instant rendering (~200ms saved).
///
/// The key insight: warmUp uses the SAME cache directory and resource
/// copying logic as the real preview, so the pooled webview can be
/// directly reused with all CSS/JS already parsed and ready.
@MainActor
final class WebViewPool {
    static let shared = WebViewPool()

    private(set) var warmedView: WKWebView?
    private(set) var isReady = false

    let cacheDir: URL = {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cachesDir.appendingPathComponent("com.meditor.preview", isDirectory: true)
    }()

    private init() {}

    /// Pre-create WKWebView + load template with all assets. Call at app launch.
    func warmUp() {
        guard warmedView == nil else { return }
        guard let resourcesRoot = PreviewResourceLocator.resourcesRoot(),
              let templateURL = PreviewResourceLocator.templateURL(),
              let template = try? String(contentsOf: templateURL, encoding: .utf8) else { return }

        // Ensure all assets are in cache dir (same as real preview)
        let fm = FileManager.default
        try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let items = ["css", "scripts", "marked.min.js", "highlight.min.js"]
        for item in items {
            let src = resourcesRoot.appendingPathComponent(item)
            let dst = cacheDir.appendingPathComponent(item)
            guard fm.fileExists(atPath: src.path), !fm.fileExists(atPath: dst.path) else { continue }
            try? fm.copyItem(at: src, to: dst)
        }

        // Write template with empty content
        let html = template
            .replacingOccurrences(of: "{{INITIAL_THEME}}", with: "github")
            .replacingOccurrences(of: "{{INITIAL_CONTENT_JSON}}", with: "\"\"")
        let fileURL = cacheDir.appendingPathComponent("preview.html")
        try? html.write(to: fileURL, atomically: true, encoding: .utf8)

        // Create and load
        let config = WKWebViewConfiguration()
        config.userContentController = WKUserContentController()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadFileURL(fileURL, allowingReadAccessTo: cacheDir)

        warmedView = webView
        isReady = false

        // Mark ready after navigation finishes (template + JS parsed)
        webView.navigationDelegate = ReadyDetector.shared
    }

    /// Dequeue a fully-ready webview. Returns nil if not ready or empty.
    func dequeue() -> WKWebView? {
        guard isReady, let view = warmedView else { return nil }
        warmedView = nil
        isReady = false
        view.navigationDelegate = nil
        // Refill pool for next use
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.warmUp()
        }
        return view
    }

    func markReady() {
        isReady = true
    }
}

/// Detects when the pooled webview finishes loading.
private class ReadyDetector: NSObject, WKNavigationDelegate {
    static let shared = ReadyDetector()
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            WebViewPool.shared.markReady()
        }
    }
}
