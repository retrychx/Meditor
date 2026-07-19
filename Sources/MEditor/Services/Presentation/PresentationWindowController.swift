import AppKit
import WebKit

/// 定位打包资源中的 `Resources/Presentation` 目录（template.html、slides.js、slides.css）。
/// 候选路径与 `PreviewResourceLocator` 保持一致，兼容 SwiftPM 资源 bundle 与 .app。
enum PresentationResourceLocator {
    static func resourcesRoot() -> URL? {
        let fm = FileManager.default
        let mainURL = Bundle.main.bundleURL
        let candidates: [URL] = [
            mainURL.appendingPathComponent("MEditor_MEditor.bundle/Resources/Presentation"),
            mainURL.appendingPathComponent("Contents/Resources/Presentation"),
            mainURL.appendingPathComponent("Presentation"),
        ]
        for url in candidates where fm.fileExists(atPath: url.appendingPathComponent("template.html").path) {
            return url
        }
        return nil
    }
}

/// 演讲模式窗口：独立 NSWindow 承载全屏 WKWebView 幻灯片。
///
/// 生命周期：
/// - `present(...)` 创建窗口并进入全屏；
/// - 退出路径有两条——JS 捕获 ESC 经 `presentationExit` message handler 回调，
///   或用户点关闭按钮触发 `windowWillClose`；两者都汇入 `teardown()` 做幂等清理；
/// - 清理时成对移除 message handler 并断开 delegate，保证 WebView 随窗口释放。
@MainActor
final class PresentationWindowController: NSObject {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var coordinator: Coordinator?

    /// 窗口完全关闭后回调（用于同步 isPresenting 状态）。
    var onDidClose: (() -> Void)?

    static let exitHandlerName = "presentationExit"

    /// 打开放映窗口并进入全屏。资源缺失或已在放映中时返回 false。
    @discardableResult
    func present(slides: [String], sourceURL: URL?, theme: PreviewTheme) -> Bool {
        guard window == nil else { return false }
        guard let resourcesRoot = PresentationResourceLocator.resourcesRoot() else { return false }

        let coordinator = Coordinator(controller: self)
        self.coordinator = coordinator

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(MeditorAssetSchemeHandler(), forURLScheme: MeditorAssetSchemeHandler.scheme)
        let userContent = WKUserContentController()
        userContent.add(coordinator, name: Self.exitHandlerName)
        config.userContentController = userContent

        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let webView = WKWebView(frame: screenFrame, configuration: config)
        webView.navigationDelegate = coordinator
        self.webView = webView

        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "MEditor Presentation"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // 窗口背景先跟随主题，避免 WebView 加载完成前闪白/闪黑
        window.backgroundColor = theme.editorBackgroundNSColor
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = webView
        self.window = window

        // template.html 是静态文件，直接从 bundle 加载；
        // read access 给到 Resources 目录，使 ../Preview/ 下的共享资源可解析。
        let resourcesDir = resourcesRoot.deletingLastPathComponent()
        webView.loadFileURL(
            resourcesRoot.appendingPathComponent("template.html"),
            allowingReadAccessTo: resourcesDir
        )

        coordinator.pendingBoot = Self.bootScript(slides: slides, sourceURL: sourceURL, theme: theme)

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(webView)
        NSApp.activate()
        window.toggleFullScreen(nil)
        return true
    }

    /// JS ESC 回调或内部主动退出走这里；关闭按钮直接触发 windowWillClose。
    /// 两条路径都汇入 windowWillClose → teardown()，保证清理只发生一次。
    func closePresentation() {
        window?.close()
    }

    /// 放映中实时切换主题：与 boot 时一致只改 <html> 的 class，窗口背景同步跟随。
    func applyTheme(_ theme: PreviewTheme) {
        window?.backgroundColor = theme.editorBackgroundNSColor
        webView?.evaluateJavaScript(
            "document.documentElement.className = 'theme-\(theme.rawValue)';",
            completionHandler: nil
        )
    }

    /// 生成 JS boot 调用；slides 经 JSON 编码保证转义安全。
    private static func bootScript(slides: [String], sourceURL: URL?, theme: PreviewTheme) -> String {
        let baseHref = sourceURL.map {
            MeditorAssetSchemeHandler.baseURLString(forDirectory: $0.deletingLastPathComponent())
        } ?? ""
        let payload: [String: Any] = [
            "slides": slides,
            "theme": theme.rawValue,
            "baseHref": baseHref,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return "window.MEditorSlides && window.MEditorSlides.boot(\(json));"
    }

    /// 幂等清理：成对移除 message handler、断开 delegate、释放 WebView 与窗口引用。
    private func teardown() {
        guard window != nil || webView != nil else { return }
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.exitHandlerName)
        webView?.removeFromSuperview()
        webView = nil
        coordinator = nil
        window?.delegate = nil
        window?.contentView = nil
        window = nil
        onDidClose?()
    }

    // MARK: - Coordinator

    /// WebKit 回调代理。被 userContentController 强引用，因此反引用 controller 用 weak。
    private final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var controller: PresentationWindowController?
        /// 页面加载完成后要执行的 boot 脚本（didFinish 里消费）。
        var pendingBoot: String = ""

        init(controller: PresentationWindowController) {
            self.controller = controller
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !pendingBoot.isEmpty else { return }
            let js = pendingBoot
            pendingBoot = ""
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == PresentationWindowController.exitHandlerName else { return }
            Task { @MainActor [weak self] in
                self?.controller?.closePresentation()
            }
        }
    }
}

// MARK: - NSWindowDelegate

extension PresentationWindowController: NSWindowDelegate {
    /// 用户点关闭按钮（或 Cmd+W 落到窗口上）时清理。
    func windowWillClose(_ notification: Notification) {
        teardown()
    }
}
