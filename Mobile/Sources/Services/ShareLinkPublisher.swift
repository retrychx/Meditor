import Foundation
import Observation
import UIKit

/// iOS 在线分享发布器：把当前文档渲染成自包含 HTML 后 POST 到自建 Worker，
/// 成功把链接放上剪贴板。与 macOS 同一个 ShareLinkService / Keychain / API。
@MainActor
@Observable
final class ShareLinkPublisher {

    static let shared = ShareLinkPublisher()

    private let service: ShareLinkService

    init(service: ShareLinkService = ShareLinkService()) {
        self.service = service
    }

    // MARK: - 状态（UI 观察）

    var isPublishing = false
    var lastResultURL: String?
    var lastError: String?

    // MARK: - 配置

    private static let baseURLKey = "MEditor.shareBaseURL"
    private static let defaultBaseURL = "https://meditor-app.863129776.workers.dev"
    private static let keychain = Keychain(service: "com.meditor.share", account: "publish-token")

    var baseURL: String {
        get { UserDefaults.standard.string(forKey: Self.baseURLKey) ?? Self.defaultBaseURL }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(trimmed.isEmpty ? Self.defaultBaseURL : trimmed, forKey: Self.baseURLKey)
        }
    }

    private(set) var hasToken: Bool = false
    var isConfigured: Bool { hasToken }

    func saveToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Self.keychain.save(trimmed)
        hasToken = true
    }

    func clearToken() {
        Self.keychain.clear()
        hasToken = false
    }

    /// 设置页打开时调用一次（避免每次渲染都读 Keychain）。
    func refreshTokenStatus() {
        hasToken = Self.keychain.load() != nil
    }

    // MARK: - 发布

    /// 发布当前文档：Markdown 渲染成自包含 HTML 上传；成功复制链接到剪贴板。
    func publish(fileName: String, markdown: String) async {
        lastError = nil
        lastResultURL = nil
        guard let token = Self.keychain.load() else {
            lastError = ShareLinkError.notConfigured.errorDescription
            return
        }

        isPublishing = true
        defer { isPublishing = false }

        do {
            let title = (fileName as NSString).deletingPathExtension
            let html = try await PreviewHTMLRenderer.render(markdown: markdown, title: title)
            let url = try await service.publish(baseURL: baseURL, token: token, title: title, html: html)
            lastResultURL = url
            UIPasteboard.general.string = url
        } catch let e as ShareLinkError {
            lastError = e.errorDescription
        } catch {
            lastError = error.localizedDescription
        }
    }
}
