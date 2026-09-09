import WebKit

/// 粘贴用 HTML → Markdown 转换器：把剪贴板里的 HTML（网页 / 飞书 / 公众号
/// 文章等富文本来源）加载进一个离屏 WKWebView，跑与导出共用的 mdH2M 转换器
///（HTMLToMarkdownJS），拿回 Markdown 文本。
///
/// 设计上需要注意的几点：
/// - 离屏、复用单个实例：WKWebView 冷启动要拉起 WebContent 进程，保留一个
///   常驻实例避免每次粘贴都付出启动开销。
/// - 禁止页面内 JS（allowsContentJavaScript = false）：剪贴板 HTML 来自外部
///   不可信来源，不允许其中脚本执行；`evaluateJavaScript` 是 App 注入的，
///   不受该开关影响。
/// - 串行队列：一次只转一份，转换按粘贴先后顺序完成。
/// - 单个任务带超时：页面加载挂起时不能让后续粘贴全部堵死。
@MainActor
final class PasteHTMLConverter: NSObject {

    static let shared = PasteHTMLConverter()

    /// 单个转换任务的最长耗时；超时按失败处理（调用方回退纯文本粘贴）。
    private static let jobTimeout: TimeInterval = 3

    private struct Job {
        let id = UUID()
        let html: String
        let completion: (String?) -> Void
    }

    private var webView: WKWebView?
    private var queue: [Job] = []
    private var activeJob: Job?

    /// 把 HTML 转成 Markdown。completion 一定在主线程回调；
    /// 结果为 nil 表示加载/转换失败（调用方应回退纯文本粘贴）。
    func convert(html: String, completion: @escaping (String?) -> Void) {
        queue.append(Job(html: html, completion: completion))
        pump()
    }

    // MARK: - 串行队列

    private func pump() {
        guard activeJob == nil, let job = queue.first else { return }
        queue.removeFirst()
        activeJob = job

        let webView = preparedWebView()
        webView.loadHTMLString(job.html, baseURL: nil)

        // 超时兜底：loadHTMLString 挂起时按失败收尾，放行后续任务
        let jobID = job.id
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.jobTimeout * 1_000_000_000))
            guard let self, self.activeJob?.id == jobID else { return }
            self.finishActiveJob(with: nil)
        }
    }

    private func finishActiveJob(with markdown: String?) {
        guard let job = activeJob else { return }
        activeJob = nil
        job.completion(markdown)
        pump()
    }

    // MARK: - WebView

    private func preparedWebView() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600),
                                configuration: config)
        webView.navigationDelegate = self
        self.webView = webView
        return webView
    }

    private func runConversion() {
        guard let jobID = activeJob?.id, let webView else { return }
        webView.evaluateJavaScript(HTMLToMarkdownJS.convertBodyScript) { [weak self] result, _ in
            // 字符串处理不涉及隔离；结果（String?）是 Sendable，可以安全带进 Task
            let markdown = (result as? String).map(HTMLToMarkdownJS.cleanConvertedMarkdown)
            Task { @MainActor in
                guard let self, self.activeJob?.id == jobID else { return }
                self.finishActiveJob(with: markdown?.isEmpty == false ? markdown : nil)
            }
        }
    }
}

extension PasteHTMLConverter: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView,
                             didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.runConversion() }
    }

    nonisolated func webView(_ webView: WKWebView,
                             didFail navigation: WKNavigation!,
                             withError error: Error) {
        Task { @MainActor in self.finishActiveJob(with: nil) }
    }

    nonisolated func webView(_ webView: WKWebView,
                             didFailProvisionalNavigation navigation: WKNavigation!,
                             withError error: Error) {
        Task { @MainActor in self.finishActiveJob(with: nil) }
    }
}
