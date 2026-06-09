import SwiftUI
import WebKit

/// Renders Markdown content inside a long-lived `WKWebView`.
///
/// Loads `template.html` once, then uses `MEditor.update(content)` JS calls
/// to replace the rendered body in place — avoiding full-page reloads and
/// preserving scroll position.
struct MarkdownWebPreview: View {
    let content: String
    var theme: PreviewTheme = .github
    /// Source line to scroll the preview to (editor→preview sync). -1 = none.
    var scrollToLine: Int = -1
    /// Monotonic token so the same target line can be requested more than once.
    var scrollRequestID: Int = 0
    /// Reports the data-source-line of the topmost visible anchor when the
    /// user scrolls inside the preview (preview→editor sync).
    var onVisibleLineChange: ((Int) -> Void)? = nil
    /// Reports extracted TOC items after each render.
    var onTOCUpdate: (([TOCItem]) -> Void)? = nil
    var exporter: PreviewExporter? = nil
    /// Source file URL — used to set <base href> so relative resources
    /// (images, links) in markdown resolve against the source directory.
    var sourceURL: URL? = nil
    /// Preview font size in px (from settings).
    var fontSize: Int = 15

    var body: some View {
        MarkdownWebView(
            content: content,
            theme: theme,
            scrollToLine: scrollToLine,
            scrollRequestID: scrollRequestID,
            onVisibleLineChange: onVisibleLineChange,
            onTOCUpdate: onTOCUpdate,
            exporter: exporter,
            sourceURL: sourceURL,
            fontSize: fontSize
        )
    }
}

/// A single heading entry extracted from the rendered preview.
struct TOCItem: Identifiable, Equatable {
    let id = UUID()
    let level: Int
    let title: String
    let line: Int
}

// MARK: - WKWebView wrapper

private struct MarkdownWebView: NSViewRepresentable {
    let content: String
    let theme: PreviewTheme
    let scrollToLine: Int
    let scrollRequestID: Int
    let onVisibleLineChange: ((Int) -> Void)?
    let onTOCUpdate: (([TOCItem]) -> Void)?
    let exporter: PreviewExporter?
    let sourceURL: URL?
    let fontSize: Int

    static let scrollHandlerName = "scrollHandler"
    static let copyHandlerName = "copyHandler"
    static let tocHandlerName = "tocHandler"

    func makeCoordinator() -> Coordinator {
        Coordinator(onVisibleLineChange: onVisibleLineChange, onTOCUpdate: onTOCUpdate, exporter: exporter)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: Self.scrollHandlerName)
        userContent.add(context.coordinator, name: Self.copyHandlerName)
        userContent.add(context.coordinator, name: Self.tocHandlerName)
        config.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.lastContent = content
        context.coordinator.lastTheme = theme
        exporter?.webView = webView

        loadTemplate(into: webView, initialContent: content, theme: theme, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onVisibleLineChange = onVisibleLineChange
        coordinator.onTOCUpdate = onTOCUpdate

        // Theme changed: swap stylesheet via JS; re-render handled by bridge.
        if theme != coordinator.lastTheme {
            coordinator.lastTheme = theme
            coordinator.evaluateWhenReady("window.MEditor && window.MEditor.setTheme('\(theme.rawValue)');")
        }

        // Source URL changed: update <base href> so relative resources resolve.
        if sourceURL != coordinator.lastSourceURL {
            coordinator.lastSourceURL = sourceURL
            let baseURL = sourceURL?.deletingLastPathComponent().absoluteString ?? ""
            let escaped = baseURL.replacingOccurrences(of: "'", with: "\\'")
            coordinator.evaluateWhenReady("window.MEditor && window.MEditor.setBaseURL('\(escaped)');")
        }

        // Font size changed: update CSS variable.
        if fontSize != coordinator.lastFontSize {
            coordinator.lastFontSize = fontSize
            coordinator.evaluateWhenReady("document.documentElement.style.setProperty('--preview-font-size','\(fontSize)px');")
        }

        // Content changed: incremental update via JS.
        if content != coordinator.lastContent {
            coordinator.lastContent = content
            coordinator.scheduleContentUpdate(content)
        }

        // Scroll sync editor → preview using source line.
        if scrollToLine >= 0, scrollRequestID != coordinator.lastAppliedRequestID {
            coordinator.lastAppliedTargetLine = scrollToLine
            coordinator.lastAppliedRequestID = scrollRequestID
            coordinator.isProgrammaticScroll = true
            coordinator.evaluateWhenReady(
                "window.MEditor && window.MEditor.scrollToLine(\(scrollToLine));"
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                coordinator.isProgrammaticScroll = false
            }
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        // Stop loading any in-flight requests, drop delegates, and detach
        // message handlers so the WKWebView can be deallocated.
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: scrollHandlerName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: copyHandlerName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: tocHandlerName)
        if coordinator.exporter?.webView === webView {
            coordinator.exporter?.webView = nil
        }
        coordinator.webView = nil
    }

    // MARK: - Template loading

    /// Render `template.html` with substituted values and load it into the webview.
    private func loadTemplate(into webView: WKWebView,
                              initialContent: String,
                              theme: PreviewTheme,
                              coordinator: Coordinator) {
        guard let resourcesRoot = PreviewResourceLocator.resourcesRoot(),
              let templateURL = PreviewResourceLocator.templateURL(),
              let template = try? String(contentsOf: templateURL, encoding: .utf8) else {
            // Fallback: blank page with an error message.
            webView.loadHTMLString(
                "<html><body><pre>MEditor: preview template not found.</pre></body></html>",
                baseURL: nil
            )
            return
        }

        let contentJSON = jsonEncode(string: initialContent) ?? "\"\""
        let html = template
            .replacingOccurrences(of: "{{INITIAL_THEME}}", with: theme.rawValue)
            .replacingOccurrences(of: "{{INITIAL_CONTENT_JSON}}", with: contentJSON)

        // Write to caches so loadFileURL can grant readAccessTo a stable directory.
        // We use a unique filename per session so WKWebView's file URL cache
        // doesn't serve stale content after a force-reload.
        let cacheDir = coordinator.previewDir
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        // Best-effort: prune if the cache has grown unreasonably large.
        Coordinator.pruneCacheIfNeeded(at: cacheDir)
        // Symlink (or copy) the resources into cache dir so relative paths work.
        ensurePreviewAssets(at: cacheDir, copyingFrom: resourcesRoot)

        let fileURL = cacheDir.appendingPathComponent("preview.html")
        try? html.write(to: fileURL, atomically: true, encoding: .utf8)

        coordinator.isReady = false
        webView.loadFileURL(fileURL, allowingReadAccessTo: cacheDir)
    }

    /// Mirror the bundle's Preview directory into `cacheDir` so the loaded
    /// `preview.html` can resolve `css/themes/*.css`, `scripts/*.js`,
    /// `marked.min.js` etc. with relative URLs.
    private func ensurePreviewAssets(at cacheDir: URL, copyingFrom source: URL) {
        let fm = FileManager.default
        let items = ["css", "scripts", "marked.min.js", "highlight.min.js", "mermaid.min.js"]
        for item in items {
            let src = source.appendingPathComponent(item)
            let dst = cacheDir.appendingPathComponent(item)
            guard fm.fileExists(atPath: src.path) else { continue }
            // If destination exists and the source is newer (or sizes differ for files), refresh.
            if fm.fileExists(atPath: dst.path) {
                if shouldRefresh(src: src, dst: dst) {
                    try? fm.removeItem(at: dst)
                    try? fm.copyItem(at: src, to: dst)
                }
            } else {
                try? fm.copyItem(at: src, to: dst)
            }
        }
    }

    private func shouldRefresh(src: URL, dst: URL) -> Bool {
        let fm = FileManager.default
        guard let srcAttrs = try? fm.attributesOfItem(atPath: src.path),
              let dstAttrs = try? fm.attributesOfItem(atPath: dst.path) else {
            return true
        }
        let srcDate = srcAttrs[.modificationDate] as? Date ?? .distantPast
        let dstDate = dstAttrs[.modificationDate] as? Date ?? .distantPast
        return srcDate > dstDate
    }

    private func jsonEncode(string: String) -> String? {
        guard let data = try? JSONEncoder().encode(string) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Coordinator

extension MarkdownWebView {
    final class Coordinator: NSObject {
        weak var webView: WKWebView?
        var onVisibleLineChange: ((Int) -> Void)?
        var onTOCUpdate: (([TOCItem]) -> Void)?
        weak var exporter: PreviewExporter?

        var lastContent: String = ""
        var lastTheme: PreviewTheme = .github
        var lastSourceURL: URL?
        var lastFontSize: Int = 15
        var lastAppliedTargetLine: Int = -1
        var lastAppliedRequestID: Int = -1
        var lastReportedLine: Int = -1
        var isProgrammaticScroll = false
        var isReady = false

        let previewDir: URL = {
            let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            return cachesDir.appendingPathComponent("com.meditor.preview", isDirectory: true)
        }()

        /// Hard cap on preview cache size. Beyond this we wipe the directory
        /// and let it rebuild on next render. mermaid.min.js (~3.3 MB) and
        /// the preview HTML are the only persistent artefacts.
        private static let cacheSizeLimit: Int64 = 50 * 1024 * 1024  // 50 MB

        /// Inspect the preview cache directory and wipe it if it has grown
        /// beyond `cacheSizeLimit`. Cheap to call: only walks immediate
        /// children, no deep recursion.
        static func pruneCacheIfNeeded(at dir: URL) {
            let fm = FileManager.default
            guard let contents = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
                options: [.skipsSubdirectoryDescendants]
            ) else { return }
            var total: Int64 = 0
            for url in contents {
                if let size = (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?
                    .totalFileAllocatedSize {
                    total += Int64(size)
                }
            }
            if total > cacheSizeLimit {
                // Removing the whole directory is safe — it will be re-created
                // and resources re-copied on the next preview load.
                try? fm.removeItem(at: dir)
            }
        }

        // Pending JS to run once the page finishes loading.
        private var pendingScripts: [String] = []

        init(onVisibleLineChange: ((Int) -> Void)? = nil, onTOCUpdate: (([TOCItem]) -> Void)? = nil, exporter: PreviewExporter? = nil) {
            self.onVisibleLineChange = onVisibleLineChange
            self.onTOCUpdate = onTOCUpdate
            self.exporter = exporter
        }

        deinit {
            // The user content controller's script handlers retain coordinator;
            // dismantleNSView already removes them, so deinit is mostly a safety net.
        }

        /// Run a JS string immediately if the page is ready, otherwise queue it.
        func evaluateWhenReady(_ js: String) {
            if isReady, let webView {
                webView.evaluateJavaScript(js) { _, error in
                    if let error { Self.logJSError(js: js, error: error) }
                }
            } else {
                pendingScripts.append(js)
            }
        }

        func flushPendingScripts() {
            guard let webView else { return }
            let scripts = pendingScripts
            pendingScripts.removeAll()
            for js in scripts {
                webView.evaluateJavaScript(js) { _, error in
                    if let error { Self.logJSError(js: js, error: error) }
                }
            }
        }

        /// Push new content to the preview immediately. Subsequent calls with
        /// the same content are skipped via the lastContent check at the call site.
        func scheduleContentUpdate(_ content: String) {
            let escaped = Self.jsonEncode(string: content) ?? "\"\""
            evaluateWhenReady("window.MEditor && window.MEditor.update(\(escaped));")
        }

        private static func jsonEncode(string: String) -> String? {
            guard let data = try? JSONEncoder().encode(string) else { return nil }
            return String(data: data, encoding: .utf8)
        }

        private static func logJSError(js: String, error: Error) {
            #if DEBUG
            let preview = js.count > 80 ? String(js.prefix(80)) + "…" : js
            print("MEditor JS error: \(error.localizedDescription) — \(preview)")
            #endif
        }
    }
}

// MARK: - WKNavigationDelegate

extension MarkdownWebView.Coordinator: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isReady = true
        // Apply configured font size on initial load.
        let fs = lastFontSize
        if fs != 15 {
            webView.evaluateJavaScript("document.documentElement.style.setProperty('--preview-font-size','\(fs)px');", completionHandler: nil)
        }
        flushPendingScripts()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // Non-fatal: leave isReady as false so we don't try to evaluateJS.
        #if DEBUG
        print("MEditor preview navigation failed: \(error.localizedDescription)")
        #endif
    }
}

// MARK: - WKScriptMessageHandler

extension MarkdownWebView.Coordinator: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        switch message.name {
        case MarkdownWebView.scrollHandlerName:
            handleScrollMessage(message)
        case MarkdownWebView.copyHandlerName:
            handleCopyMessage(message)
        case MarkdownWebView.tocHandlerName:
            handleTOCMessage(message)
        default:
            break
        }
    }

    private func handleScrollMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        if isProgrammaticScroll { return }
        if let line = body["line"] as? Int, line >= 0, line != lastReportedLine {
            lastReportedLine = line
            onVisibleLineChange?(line)
        }
    }

    private func handleCopyMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let text = body["text"] as? String else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func handleTOCMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let items = body["items"] as? [[String: Any]] else { return }
        let tocItems = items.compactMap { dict -> TOCItem? in
            guard let level = dict["level"] as? Int,
                  let title = dict["title"] as? String,
                  let line = dict["line"] as? Int else { return nil }
            return TOCItem(level: level, title: title, line: line)
        }
        onTOCUpdate?(tocItems)
    }
}
