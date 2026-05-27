import Foundation

/// Manages session persistence: save/restore/flush.
/// Extracted from AppState to isolate persistence concerns.
@MainActor
final class SessionManager {
    private let sessionStore: SessionStore
    private var isRestoringSession = false

    init(sessionStore: SessionStore = SessionStore()) {
        self.sessionStore = sessionStore
    }

    var isRestoring: Bool { isRestoringSession }

    func beginRestore() { isRestoringSession = true }
    func endRestore() { isRestoringSession = false }

    func scheduleSave(rootURL: URL?, openTabs: [EditorTab], selectedTabID: UUID?) {
        guard !isRestoringSession else { return }
        let urls = openTabs.map { $0.url }
        let selectedIdx = selectedIndex(tabs: openTabs, selectedTabID: selectedTabID)
        sessionStore.scheduleSave(rootURL: rootURL, openTabURLs: urls, selectedIndex: selectedIdx)
    }

    func flushSession(rootURL: URL?, openTabs: [EditorTab], selectedTabID: UUID?) {
        let urls = openTabs.map { $0.url }
        let selectedIdx = selectedIndex(tabs: openTabs, selectedTabID: selectedTabID)
        sessionStore.saveNow(rootURL: rootURL, openTabURLs: urls, selectedIndex: selectedIdx)
    }

    func loadSession() -> SessionStore.PersistedSession? {
        sessionStore.load()
    }

    static func resolveBookmark(_ data: Data) -> (url: URL, isStale: Bool)? {
        SessionStore.resolveBookmark(data)
    }

    private func selectedIndex(tabs: [EditorTab], selectedTabID: UUID?) -> Int? {
        guard let id = selectedTabID else { return nil }
        return tabs.firstIndex(where: { $0.id == id })
    }
}
