import SwiftUI
import WebKit

/// Renders HTML content in a WKWebView.
struct WebPreviewView: NSViewRepresentable {
    let htmlContent: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.autoresizingMask = [.width, .height]

        context.coordinator.lastLoadedContent = htmlContent
        webView.loadHTMLString(htmlContent, baseURL: nil)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard htmlContent != context.coordinator.lastLoadedContent else { return }
        context.coordinator.lastLoadedContent = htmlContent
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }
}

// MARK: - Coordinator

extension WebPreviewView {
    class Coordinator {
        var lastLoadedContent: String = ""
    }
}
