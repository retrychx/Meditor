import Foundation
import Observation
import AppKit

/// Coordinates publishing the current document to a GitHub Gist.
///
/// - Token lives in the macOS Keychain (never on disk/logs).
/// - `isPublic` (secret/public) lives in AppSettings.
/// - A `path → gist id` map (UserDefaults) lets re-shares update in place.
@MainActor
@Observable
final class GitHubGistManager {

    private let service = GitHubGistService()
    private let settings = AppSettings.shared
    private let gistMapKey = "MEditor.githubGistMap"

    // MARK: - Publish state (observed by UI)

    var isPublishing = false
    var lastResultURL: String?
    var lastError: String?

    // MARK: - Config

    var isPublic: Bool {
        get { settings.githubGistPublic }
        set { settings.githubGistPublic = newValue }
    }

    /// Cached flag — avoids Keychain reads on every SwiftUI render.
    /// Updated when the user saves or clears a token.
    private(set) var hasToken: Bool = false
    var isConfigured: Bool { hasToken }

    func saveToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? GitHubGistService.saveToken(trimmed)
        hasToken = true
    }

    func clearToken() {
        GitHubGistService.deleteToken()
        hasToken = false
    }

    /// Call once when the Settings sheet opens (not at app launch).
    func refreshTokenStatus() {
        hasToken = GitHubGistService.loadToken() != nil
    }

    // MARK: - Publish

    func publish(tab: EditorTab) async {
        lastError = nil
        lastResultURL = nil
        guard let token = GitHubGistService.loadToken() else {
            lastError = GitHubGistError.notConfigured.errorDescription
            return
        }

        let fileName = tab.url.lastPathComponent
        let description = tab.url.deletingPathExtension().lastPathComponent + " — shared via MEditor"
        let content = tab.content
        let pathKey = tab.url.standardizedFileURL.path

        isPublishing = true
        defer { isPublishing = false }

        do {
            let url: String
            if let existingID = gistID(for: pathKey) {
                // Update in place; fall back to create if remote gist is gone.
                do {
                    url = try await service.updateGist(
                        token: token, id: existingID,
                        fileName: fileName, content: content)
                } catch {
                    let created = try await service.createGist(
                        token: token, description: description,
                        fileName: fileName, content: content, isPublic: isPublic)
                    setGistID(created.id, for: pathKey)
                    url = created.url
                }
            } else {
                let created = try await service.createGist(
                    token: token, description: description,
                    fileName: fileName, content: content, isPublic: isPublic)
                setGistID(created.id, for: pathKey)
                url = created.url
            }
            lastResultURL = url
            // Auto-copy to clipboard so the user can paste immediately.
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(url, forType: .string)
        } catch let e as GitHubGistError {
            lastError = e.errorDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Gist id map

    private func gistMap() -> [String: String] {
        (UserDefaults.standard.dictionary(forKey: gistMapKey) as? [String: String]) ?? [:]
    }

    private func gistID(for path: String) -> String? { gistMap()[path] }

    private func setGistID(_ id: String, for path: String) {
        var map = gistMap()
        map[path] = id
        UserDefaults.standard.set(map, forKey: gistMapKey)
    }

    /// Forget all local gist associations (does not delete remote gists).
    func clearGistMap() {
        UserDefaults.standard.removeObject(forKey: gistMapKey)
    }
}
