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
    let fileURL: URL?
    let reloadToken: Int
    var exporter: PreviewExporter? = nil
    var rootURL: URL? = nil
    var findController: PreviewFindController? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(findController: findController)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "copyHandler")
        config.userContentController = userContent
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = context.coordinator

        context.coordinator.webView = webView
        context.coordinator.rootURL = rootURL
        findController?.register(webView: webView, for: .html)
        context.coordinator.applyLoad(fileURL: fileURL, reloadToken: reloadToken)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Register with exporter when HTML preview is active.
        if fileURL != nil {
            exporter?.webView = webView
        }
        context.coordinator.rootURL = rootURL
        context.coordinator.findController = findController
        findController?.register(webView: webView, for: .html)
        context.coordinator.applyLoad(fileURL: fileURL, reloadToken: reloadToken)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "copyHandler")
        coordinator.findController?.register(webView: nil, for: .html)
        coordinator.webView = nil
    }
}

extension WebPreviewView {
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var rootURL: URL?
        var findController: PreviewFindController?
        private var lastFileURL: URL?
        private var lastReloadToken: Int = -1

        init(findController: PreviewFindController? = nil) {
            self.findController = findController
        }

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

            // Grant read access to the project root (or file's parent) so that
            // relative resources (images, css, js) referenced in the HTML
            // resolve correctly — even when paths traverse up to sibling dirs.
            let readAccess = rootURL ?? fileURL.deletingLastPathComponent()
            webView.loadFileURL(fileURL, allowingReadAccessTo: readAccess)
        }
    }
}

extension WebPreviewView.Coordinator {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "copyHandler",
              let body = message.body as? [String: Any],
              let text = body["text"] as? String else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

extension WebPreviewView.Coordinator {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Inject copy buttons into <pre><code> blocks, mirroring render.js behaviour.
        let js = """
        (function() {
            if (document.querySelector('.meditor-copy-btn')) return;
            var style = document.createElement('style');
            style.textContent = '.meditor-codeblock{position:relative}.meditor-copy-btn{position:absolute;top:8px;right:8px;padding:3px 9px;font-size:11px;font-family:-apple-system,sans-serif;font-weight:500;background:rgba(255,255,255,.15);color:inherit;border:1px solid rgba(128,128,128,.3);border-radius:4px;cursor:pointer;opacity:0;transition:opacity .15s}.meditor-codeblock:hover .meditor-copy-btn{opacity:.9}.meditor-copy-btn:hover{opacity:1!important}.meditor-copy-btn--copied{opacity:1!important;color:#0969da}';
            document.head.appendChild(style);
            document.querySelectorAll('pre code, pre').forEach(function(el) {
                var pre = el.tagName === 'PRE' ? el : el.parentElement;
                if (!pre || pre.tagName !== 'PRE') return;
                if (pre.querySelector('.meditor-copy-btn')) return;
                pre.style.position = 'relative';
                pre.classList.add('meditor-codeblock');
                var btn = document.createElement('button');
                btn.className = 'meditor-copy-btn';
                btn.textContent = 'Copy';
                btn.addEventListener('click', function(e) {
                    e.stopPropagation();
                    var text = (pre.querySelector('code') || pre).innerText || '';
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.copyHandler) {
                        window.webkit.messageHandlers.copyHandler.postMessage({text: text});
                    } else if (navigator.clipboard) {
                        navigator.clipboard.writeText(text);
                    }
                    btn.textContent = 'Copied';
                    btn.classList.add('meditor-copy-btn--copied');
                    setTimeout(function() { btn.textContent = 'Copy'; btn.classList.remove('meditor-copy-btn--copied'); }, 1200);
                });
                pre.appendChild(btn);
            });
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}
