import Foundation
import Observation
import WebKit

/// 把当前文档的预览渲染结果发布成在线分享链接（自建 Worker + KV）。
///
/// - Token 存 Keychain（对齐 GitHubGistManager 的模式）。
/// - Base URL 存 AppSettings.shareBaseURL，默认 workers.dev，发布前换自定义域名只改一处。
/// - HTML 取自预览 webview：先 renderAllDiagrams() 渲染全部 Mermaid 占位，
///   再 getRenderedHTML() 拿自包含 HTML（内联 CSS + 主题 class）。
@MainActor
@Observable
final class ShareLinkPublisher {

    private let settings: AppSettings
    private let webViewProvider: () -> WKWebView?
    private let service: ShareLinkService

    /// - Parameter webViewProvider: 取当前预览 webview（PreviewExporter 持有弱引用）。
    init(
        settings: AppSettings = .shared,
        webViewProvider: @escaping () -> WKWebView? = { nil },
        service: ShareLinkService = ShareLinkService()
    ) {
        self.settings = settings
        self.webViewProvider = webViewProvider
        self.service = service
    }

    // MARK: - Publish state (observed by UI)

    var isPublishing = false
    var lastResultURL: String?
    var lastError: String?

    // MARK: - Config

    /// Cached flag — avoids Keychain reads on every SwiftUI render.
    private(set) var hasToken: Bool = false
    var isConfigured: Bool { hasToken }

    var baseURL: String {
        get { settings.shareBaseURL }
        set { settings.shareBaseURL = newValue }
    }

    func saveToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        ShareLinkService.saveToken(trimmed)
        hasToken = true
    }

    func clearToken() {
        ShareLinkService.deleteToken()
        hasToken = false
    }

    /// Call once when the Settings sheet opens (not at app launch).
    func refreshTokenStatus() {
        hasToken = ShareLinkService.loadToken() != nil
    }

    // MARK: - Publish

    func publish(tab: EditorTab) async {
        lastError = nil
        lastResultURL = nil
        guard let token = ShareLinkService.loadToken() else {
            lastError = ShareLinkError.notConfigured.errorDescription
            return
        }
        guard let webView = webViewProvider() else {
            lastError = ShareLinkError.noWebView.errorDescription
            return
        }

        isPublishing = true
        defer { isPublishing = false }

        do {
            let title = tab.url.deletingPathExtension().lastPathComponent
            let rendered = try await Self.renderedHTML(webView: webView, title: title)
            // 本地图片（meditor-asset / file:// / 相对路径）内联成 data URI，否则线上全挂
            let html = ShareImageInliner.inlineImages(
                in: rendered, baseDirectory: tab.url.deletingLastPathComponent())
            let url = try await service.publish(
                baseURL: settings.shareBaseURL, token: token, title: title, html: html)
            lastResultURL = url
            // Auto-copy to clipboard so the user can paste immediately.
            Pasteboard.copy(url)
        } catch let e as ShareLinkError {
            lastError = e.errorDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 先把未懒渲染的 Mermaid 图全部渲染，再取自包含 HTML。
    private static func renderedHTML(webView: WKWebView, title: String) async throws -> String {
        // callAsyncJavaScript + await：等 renderAllDiagrams 的 Promise 完成
        _ = try? await webView.callAsyncJavaScript(
            "return await window.MEditor.renderAllDiagrams();",
            arguments: [:], in: nil, contentWorld: .page
        )
        let escapedTitle = title.replacingOccurrences(of: "\\", with: "\\\\")
                                .replacingOccurrences(of: "'", with: "\\'")
        let js = "window.MEditor && window.MEditor.getRenderedHTML('\(escapedTitle)')"
        let result = try await webView.evaluateJavaScript(js)
        guard let html = result as? String, !html.isEmpty else {
            throw ShareLinkError.renderFailed("empty result")
        }
        return html
    }
}
