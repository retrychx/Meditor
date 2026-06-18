import Foundation

/// Errors surfaced from GitLab Snippet operations, mapped to user-friendly text.
enum GitLabError: LocalizedError {
    case notConfigured
    case invalidToken
    case insufficientScope
    case tooLarge
    case network
    case server(Int, String)
    case badResponse
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .notConfigured:     return L("gitlab.error.notConfigured")
        case .invalidToken:      return L("gitlab.error.invalidToken")
        case .insufficientScope: return L("gitlab.error.insufficientScope")
        case .tooLarge:          return L("gitlab.error.tooLarge")
        case .network:           return L("gitlab.error.network")
        case .server(let code, let msg):
            return L("gitlab.error.server", code, msg)
        case .badResponse:       return L("gitlab.error.badResponse")
        case .keychain(let status):
            return L("gitlab.error.keychain", Int(status))
        }
    }
}

/// Stateless wrapper over the GitLab Snippets REST API plus Keychain token
/// storage. Tokens are never written to disk or logged.
///
/// Requires GitLab ≥ 13.5 for the multi-file `files` payload (confirmed
/// gitlab.sheincorp.cn = 16.11.4).
struct GitLabService {

    /// Max content size we allow uploading as a single snippet.
    static let maxContentBytes = 1_000_000

    // MARK: - Keychain (token per host)

    private static let keychainService = "com.meditor.gitlab"

    static func saveToken(_ token: String, host: String) throws {
        guard let data = token.data(using: .utf8) else { throw GitLabError.badResponse }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: host
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw GitLabError.keychain(status) }
    }

    static func loadToken(host: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: host,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteToken(host: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: host
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - API

    private struct SnippetResponse: Decodable {
        let id: Int
        let webURL: String
        enum CodingKeys: String, CodingKey { case id; case webURL = "web_url" }
    }

    /// Create a new snippet. Returns its id and shareable web URL.
    func createSnippet(
        host: String,
        token: String,
        title: String,
        fileName: String,
        content: String,
        visibility: String
    ) async throws -> (id: Int, url: String) {
        try Self.checkSize(content)
        let body: [String: Any] = [
            "title": title,
            "description": "Shared via MEditor",
            "visibility": visibility,
            "files": [["file_path": fileName, "content": content]]
        ]
        let data = try await send("POST", path: "/api/v4/snippets", host: host, token: token, body: body)
        let resp = try decode(data)
        return (resp.id, resp.webURL)
    }

    /// Update an existing snippet's file content. Returns the web URL.
    func updateSnippet(
        host: String,
        token: String,
        id: Int,
        fileName: String,
        content: String
    ) async throws -> String {
        try Self.checkSize(content)
        let body: [String: Any] = [
            "files": [["action": "update", "file_path": fileName, "content": content]]
        ]
        let data = try await send("PUT", path: "/api/v4/snippets/\(id)", host: host, token: token, body: body)
        return try decode(data).webURL
    }

    // MARK: - Helpers

    private static func checkSize(_ content: String) throws {
        if content.utf8.count > maxContentBytes { throw GitLabError.tooLarge }
    }

    private func decode(_ data: Data) throws -> SnippetResponse {
        guard let resp = try? JSONDecoder().decode(SnippetResponse.self, from: data) else {
            throw GitLabError.badResponse
        }
        return resp
    }

    private func send(
        _ method: String,
        path: String,
        host: String,
        token: String,
        body: [String: Any]
    ) async throws -> Data {
        guard let url = URL(string: "https://\(host)\(path)") else { throw GitLabError.badResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GitLabError.network
        }
        guard let http = response as? HTTPURLResponse else { throw GitLabError.badResponse }
        switch http.statusCode {
        case 200...299: return data
        case 401:       throw GitLabError.invalidToken
        case 403:       throw GitLabError.insufficientScope
        case 413:       throw GitLabError.tooLarge
        default:
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw GitLabError.server(http.statusCode, msg ?? "")
        }
    }
}
