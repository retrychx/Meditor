import Foundation

/// Errors surfaced from GitHub Gist operations.
enum GitHubGistError: LocalizedError {
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
        case .notConfigured:     return L("github.error.notConfigured")
        case .invalidToken:      return L("github.error.invalidToken")
        case .insufficientScope: return L("github.error.insufficientScope")
        case .tooLarge:          return L("github.error.tooLarge")
        case .network:           return L("github.error.network")
        case .server(let code, let msg):
            return L("github.error.server", code, msg)
        case .badResponse:       return L("github.error.badResponse")
        case .keychain(let status):
            return L("github.error.keychain", Int(status))
        }
    }
}

/// Stateless wrapper over the GitHub Gists REST API plus Keychain token storage.
/// Tokens are never written to disk or logged.
///
/// Requires a GitHub PAT with the `gist` scope.
struct GitHubGistService {

    static let maxContentBytes = 1_000_000

    // MARK: - Keychain

    private static let keychainService = "com.meditor.github"
    private static let keychainAccount = "gist-token"

    static func saveToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else { throw GitHubGistError.badResponse }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw GitHubGistError.keychain(status) }
    }

    static func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - API

    private struct GistResponse: Decodable {
        let id: String
        let htmlURL: String
        enum CodingKeys: String, CodingKey { case id; case htmlURL = "html_url" }
    }

    /// Create a new Gist. Returns its id and shareable web URL.
    func createGist(
        token: String,
        description: String,
        fileName: String,
        content: String,
        isPublic: Bool
    ) async throws -> (id: String, url: String) {
        try Self.checkSize(content)
        let body: [String: Any] = [
            "description": description,
            "public": isPublic,
            "files": [fileName: ["content": content]]
        ]
        let data = try await send("POST", path: "/gists", token: token, body: body)
        let resp = try decode(data)
        return (resp.id, resp.htmlURL)
    }

    /// Update an existing Gist's file content. Returns the web URL.
    func updateGist(
        token: String,
        id: String,
        fileName: String,
        content: String
    ) async throws -> String {
        try Self.checkSize(content)
        let body: [String: Any] = [
            "files": [fileName: ["content": content]]
        ]
        let data = try await send("PATCH", path: "/gists/\(id)", token: token, body: body)
        return try decode(data).htmlURL
    }

    // MARK: - Helpers

    private static func checkSize(_ content: String) throws {
        if content.utf8.count > maxContentBytes { throw GitHubGistError.tooLarge }
    }

    private func decode(_ data: Data) throws -> GistResponse {
        guard let resp = try? JSONDecoder().decode(GistResponse.self, from: data) else {
            throw GitHubGistError.badResponse
        }
        return resp
    }

    private func send(
        _ method: String,
        path: String,
        token: String,
        body: [String: Any]
    ) async throws -> Data {
        guard let url = URL(string: "https://api.github.com\(path)") else {
            throw GitHubGistError.badResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GitHubGistError.network
        }
        guard let http = response as? HTTPURLResponse else { throw GitHubGistError.badResponse }
        switch http.statusCode {
        case 200...299: return data
        case 401:       throw GitHubGistError.invalidToken
        case 403:       throw GitHubGistError.insufficientScope
        case 413:       throw GitHubGistError.tooLarge
        default:
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
            throw GitHubGistError.server(http.statusCode, msg ?? "")
        }
    }
}
