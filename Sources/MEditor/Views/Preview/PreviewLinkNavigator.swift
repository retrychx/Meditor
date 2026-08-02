import WebKit
import AppKit

/// 预览页（Markdown / HTML）内的链接点击策略。
///
/// 问题背景：WKWebView 默认允许页内导航，用户在预览里点击链接后，
/// 渲染模板/原文档会被目标页面替换，且没有"返回"入口，预览就此坏掉。
///
/// 策略：
///  - 页内锚点跳转（`#heading`）：放行，在预览内滚动。
///  - 其余链接（http/https/mailto/本地文件等）：交给系统默认应用打开，
///    取消 WebView 内导航，预览内容保持不变。
enum PreviewLinkNavigator {
    /// 供 `WKNavigationDelegate.webView(_:decidePolicyFor:decisionHandler:)` 调用。
    static func decidePolicy(
        for navigationAction: WKNavigationAction,
        webView: WKWebView,
        decisionHandler: (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if isSamePageAnchor(url, current: webView.url) {
            decisionHandler(.allow)
            return
        }
        openExternally(url)
        decisionHandler(.cancel)
    }

    /// 用系统默认应用打开链接（浏览器/Finder 关联应用等）。
    static func openExternally(_ url: URL) {
        // meditor-asset:// 是预览内部用于加载本地资源的自定义 scheme，
        // 系统无法识别，先还原为真实文件路径。
        if url.scheme == MeditorAssetSchemeHandler.scheme {
            let path = (url.path.removingPercentEncoding ?? url.path) as NSString
            NSWorkspace.shared.open(URL(fileURLWithPath: path.standardizingPath))
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// 仅 fragment 不同（同页锚点）的跳转。
    private static func isSamePageAnchor(_ url: URL, current: URL?) -> Bool {
        guard url.fragment != nil, let current else { return false }
        var target = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var base = URLComponents(url: current, resolvingAgainstBaseURL: false)
        target?.fragment = nil
        base?.fragment = nil
        return target?.string == base?.string
    }
}
