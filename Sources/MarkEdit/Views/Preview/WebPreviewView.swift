import SwiftUI
import WebKit

/// Renders HTML content in a WKWebView.
struct WebPreviewView: NSViewRepresentable {
    let htmlContent: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.autoresizingMask = [.width, .height]

        if !htmlContent.isEmpty {
            webView.loadHTMLString(htmlContent, baseURL: nil)
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if !htmlContent.isEmpty {
            webView.loadHTMLString(htmlContent, baseURL: nil)
        }
    }
}
