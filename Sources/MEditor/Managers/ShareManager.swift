import Foundation
import Observation

/// Wraps LocalShareServer with a clean reactive interface.
///
/// AppState calls `sync(rootURL:openTabs:)` whenever tabs or rootURL change.
/// Views that show share UI read `isRunning`, `port`, etc. through AppState
/// forwarding properties (unchanged API).
@MainActor
@Observable
final class ShareManager {

    // MARK: - Private

    private let server = LocalShareServer()

    // MARK: - Forwarded state

    var isRunning: Bool { server.isRunning }
    var port: UInt16 { server.port }
    var localAddress: String { server.localAddress }
    var shareURL: String { server.shareURL }
    var accessToken: String { server.accessToken }
    var rootURL: URL? {
        get { server.rootURL }
        set { server.rootURL = newValue }
    }
    var allowedFiles: [URL] {
        get { server.allowedFiles }
        set { server.allowedFiles = newValue }
    }

    // MARK: - Actions

    func start(rootURL: URL?, openTabs: [EditorTab], preferredPort: UInt16 = 8899) {
        server.rootURL = rootURL
        server.allowedFiles = openTabs.map(\.url)
        server.start(preferredPort: preferredPort)
    }

    func stop() {
        server.stop()
    }

    /// Call after rootURL or openTabs changes to keep the server in sync.
    func sync(rootURL: URL?, openTabs: [EditorTab]) {
        guard server.isRunning else { return }
        if server.rootURL?.standardizedFileURL != rootURL?.standardizedFileURL {
            server.rootURL = rootURL
        }
        let currentFiles  = openTabs.map(\.url.standardizedFileURL)
        let existingFiles = server.allowedFiles.map(\.standardizedFileURL)
        if currentFiles != existingFiles {
            server.allowedFiles = openTabs.map(\.url)
        }
    }

    /// Returns a shareable URL string for a given file.
    func shareURLForFile(_ fileURL: URL) -> String? {
        server.shareURLForFile(fileURL)
    }
}
