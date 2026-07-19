import SwiftUI
import WebKit

/// HTML 文件预览：WKWebView 加载 HTML 字符串。
/// updateUIView 会被任意无关状态刷新触发——coordinator 记录已加载内容，
/// 内容没变就不重载，避免整页重载丢失滚动位置。
struct HTMLPreviewView: UIViewRepresentable {
    let html: String

    final class Coordinator {
        var lastHTML: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        WKWebView()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }
}
