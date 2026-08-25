import Foundation

/// 在线分享链接（自建 Cloudflare Worker + KV）的错误类型。
enum ShareLinkError: LocalizedError {
    case notConfigured
    case invalidToken
    case tooLarge
    case quotaExceeded(Int)
    case network
    case server(Int, String)
    case badResponse
    case noWebView
    case renderFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:        return L("sharelink.error.notConfigured")
        case .invalidToken:         return L("sharelink.error.invalidToken")
        case .tooLarge:             return L("sharelink.error.tooLarge")
        case .quotaExceeded(let limit):
            return L("sharelink.error.quotaExceeded", limit)
        case .network:              return L("sharelink.error.network")
        case .server(let code, let msg):
            return L("sharelink.error.server", code, msg)
        case .badResponse:          return L("sharelink.error.badResponse")
        case .noWebView:            return L("sharelink.error.noWebView")
        case .renderFailed(let m):  return L("sharelink.error.renderFailed", m)
        }
    }
}

/// Stateless wrapper over the self-hosted share API (Cloudflare Worker + KV).
/// Token lives in the Keychain (never on disk/logs); base URL lives in AppSettings
/// （发布前把默认 workers.dev 换成自定义域名即可，只改一处）。
struct ShareLinkService {

    static let maxHTMLBytes = 4 * 1024 * 1024

    // MARK: - Keychain

    private static let keychain = Keychain(service: "com.meditor.share", account: "publish-token")

    static func saveToken(_ token: String) { keychain.save(token) }
    static func loadToken() -> String? { keychain.load() }
    static func deleteToken() { keychain.clear() }

    // MARK: - API

    /// 网络传输层，测试时可注入 mock。
    var transport: (URLRequest) async throws -> (Data, URLResponse) = {
        try await URLSession.shared.data(for: $0)
    }

    private struct ShareResponse: Decodable {
        let url: String
    }

    /// 发布渲染后的自包含 HTML，返回在线链接。
    func publish(baseURL: String, token: String, title: String, html: String) async throws -> String {
        guard html.utf8.count <= Self.maxHTMLBytes else { throw ShareLinkError.tooLarge }
        let endpoint = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: endpoint + "/api/share") else { throw ShareLinkError.badResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["title": title, "html": html])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch {
            throw ShareLinkError.network
        }
        guard let http = response as? HTTPURLResponse else { throw ShareLinkError.badResponse }
        switch http.statusCode {
        case 200...299:
            guard let resp = try? JSONDecoder().decode(ShareResponse.self, from: data) else {
                throw ShareLinkError.badResponse
            }
            return resp.url
        case 401: throw ShareLinkError.invalidToken
        case 413: throw ShareLinkError.tooLarge
        case 429:
            // 免费档月度配额超限：服务端返回 {error, limit, resetsAt}
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw ShareLinkError.quotaExceeded(body?["limit"] as? Int ?? 20)
        default:
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw ShareLinkError.server(http.statusCode, msg ?? "")
        }
    }
}
