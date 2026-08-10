import Foundation

extension Notification.Name {
    /// 预览面板（WKWebView）持有焦点时收到 ESC 键。
    ///
    /// 背景：WKWebView 把键盘事件转发给独立的 WebContent 进程处理，AppKit 侧的
    /// `NSEvent.addLocalMonitorForEvents` 本地事件监视器和 `WKWebView` 子类的
    /// `keyDown` 覆写都拦不到（文件写入验证：两种方式都从未被触发）。只能在
    /// 页面自身注册 JS `keydown` 监听器，通过 `WKScriptMessageHandler`
    /// （message handler 名 `escapeHandler`）桥接回 Swift 层广播这个通知——
    /// 见 `MarkdownWebPreview.swift` / `WebPreviewView.swift` / `bridge.js`。
    static let previewWebViewDidPressEscape = Notification.Name("previewWebViewDidPressEscape")
}
