import SwiftUI
import WebKit

/// Renders an HTML file in a long-lived `WKWebView` via `loadFileURL`.
///
/// Why URL instead of a content string:
///  - `loadFileURL` lets the WebContent process mmap the file directly,
///    bypassing IPC transfer of large strings.
///  - Loading proceeds in parallel with the Swift-side file read; for HTML
///    files we don't need Swift to wait on disk before the preview updates.
///  - Relative resources in the HTML (`<img src="./pic.png">`,
///    `<link href="./style.css">`) resolve correctly against the file's
///    parent directory.
///  - Reload is triggered by an external token, not by content diffing,
///    avoiding any string equality checks on large documents.
struct WebPreviewView: NSViewRepresentable {
    /// File URL to load. nil means show a blank page.
    let fileURL: URL?
    /// Bumped by the host (e.g. on save / external modification) to force a reload
    /// even when `fileURL` hasn't changed.
    let reloadToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = context.coordinator

        context.coordinator.webView = webView
        context.coordinator.applyLoad(fileURL: fileURL, reloadToken: reloadToken)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.applyLoad(fileURL: fileURL, reloadToken: reloadToken)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        coordinator.webView = nil
    }
}

extension WebPreviewView {
    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var lastFileURL: URL?
        private var lastReloadToken: Int = -1

        /// Load the file only when something actually changed.
        /// SwiftUI calls `updateNSView` for many unrelated reasons, so dedup here.
        func applyLoad(fileURL: URL?, reloadToken: Int) {
            let urlChanged = fileURL?.absoluteURL != lastFileURL?.absoluteURL
            let tokenChanged = reloadToken != lastReloadToken

            guard urlChanged || tokenChanged else { return }
            lastFileURL = fileURL
            lastReloadToken = reloadToken

            guard let webView = webView else { return }
            guard let fileURL = fileURL else {
                // No file: show a blank page (a single empty doc, cached forever).
                webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
                return
            }

            // Grant read access to the file's parent directory so that
            // relative resources (images, css, js) referenced in the HTML
            // resolve correctly.
            let readAccess = fileURL.deletingLastPathComponent()
            webView.loadFileURL(fileURL, allowingReadAccessTo: readAccess)
        }
    }
}
