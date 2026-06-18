import Foundation
import Observation
import AppKit

/// Coordinates publishing the current document to a GitLab Snippet.
///
/// - Host & default visibility live in `AppSettings` (UserDefaults).
/// - The personal access token lives in the macOS Keychain (never on disk/logs).
/// - A `path → snippet id` map (UserDefaults) lets re-shares update in place.
@MainActor
@Observable
final class GitLabShareManager {

    private let service = GitLabService()
    private let settings = AppSettings.shared
    private let snippetMapKey = "MEditor.gitlabSnippetMap"

    // MARK: - Publish state (observed by UI)

    var isPublishing = false
    var lastResultURL: String?
    var lastError: String?

    // MARK: - Config

    var host: String {
        get { settings.gitlabHost }
        set { settings.gitlabHost = newValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    var visibility: String {
        get { settings.gitlabVisibility }
        set { settings.gitlabVisibility = newValue }
    }

    var hasToken: Bool {
        guard !host.isEmpty else { return false }
        return GitLabService.loadToken(host: host) != nil
    }

    var isConfigured: Bool { !host.isEmpty && hasToken }

    func saveToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, !trimmed.isEmpty else { return }
        try? GitLabService.saveToken(trimmed, host: host)
    }

    func clearToken() {
        guard !host.isEmpty else { return }
        GitLabService.deleteToken(host: host)
    }

    // MARK: - Publish

    func publish(tab: EditorTab) async {
        lastError = nil
        lastResultURL = nil
        guard !host.isEmpty, let token = GitLabService.loadToken(host: host) else {
            lastError = GitLabError.notConfigured.errorDescription
            return
        }

        let fileName = tab.url.lastPathComponent
        let title = tab.url.deletingPathExtension().lastPathComponent
        let content = tab.content
        let pathKey = tab.url.standardizedFileURL.path

        isPublishing = true
        defer { isPublishing = false }

        do {
            let url: String
            if let existingID = snippetID(for: pathKey) {
                // Update in place; if the remote snippet is gone, fall back to create.
                do {
                    url = try await service.updateSnippet(
                        host: host, token: token, id: existingID,
                        fileName: fileName, content: content)
                } catch {
                    let created = try await service.createSnippet(
                        host: host, token: token, title: title,
                        fileName: fileName, content: content, visibility: visibility)
                    setSnippetID(created.id, for: pathKey)
                    url = created.url
                }
            } else {
                let created = try await service.createSnippet(
                    host: host, token: token, title: title,
                    fileName: fileName, content: content, visibility: visibility)
                setSnippetID(created.id, for: pathKey)
                url = created.url
            }
            lastResultURL = url
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(url, forType: .string)
        } catch let e as GitLabError {
            lastError = e.errorDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Snippet id map

    private func snippetMap() -> [String: Int] {
        (UserDefaults.standard.dictionary(forKey: snippetMapKey) as? [String: Int]) ?? [:]
    }

    private func snippetID(for path: String) -> Int? { snippetMap()[path] }

    private func setSnippetID(_ id: Int, for path: String) {
        var map = snippetMap()
        map[path] = id
        UserDefaults.standard.set(map, forKey: snippetMapKey)
    }

    /// Forget all local snippet associations (does not delete remote snippets).
    func clearSnippetMap() {
        UserDefaults.standard.removeObject(forKey: snippetMapKey)
    }
}
