import Foundation

/// Persists and restores the user's session across app launches:
///   - root folder URL (as a security-scoped bookmark)
///   - open tab URLs and their order
///   - currently selected tab
///
/// Uses macOS security-scoped bookmarks rather than raw paths so the user
/// doesn't need to re-grant access via Open Panel after every launch — and
/// so the URL keeps working even if the file is renamed/moved.
final class SessionStore: SessionStoreProtocol {

    // MARK: - Persisted shape

    /// Lightweight DTO written to UserDefaults. Bookmark `Data` is base64-encoded
    /// so the whole session is a single Codable value.
    struct PersistedSession: Codable {
        var rootBookmark: Data?
        var tabs: [Data]              // bookmarks for every open tab, in order
        var selectedTabIndex: Int?    // index into `tabs`, nil if no selection
        var version: Int = 1
    }

    // MARK: - Storage

    private static let userDefaultsKey = "MEditor.session"
    private let userDefaults: UserDefaults
    private let queue = DispatchQueue(label: "com.meditor.session", qos: .utility)

    /// Debounced save coalesces bursty state changes.
    private var pendingSave: DispatchWorkItem?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - Save

    /// Schedule a save ~250ms in the future. Repeated calls within that window
    /// collapse to a single write. Use `saveNow` for app-quit flushes.
    func scheduleSave(rootURL: URL?, openTabURLs: [URL], selectedIndex: Int?) {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveNow(rootURL: rootURL, openTabURLs: openTabURLs, selectedIndex: selectedIndex)
        }
        pendingSave = work
        queue.asyncAfter(deadline: .now() + .milliseconds(250), execute: work)
    }

    /// Force an immediate synchronous save. Call before app quit so nothing is lost.
    /// Thread-safe: serializes through `queue` to avoid racing with debounced saves.
    func saveNow(rootURL: URL?, openTabURLs: [URL], selectedIndex: Int?) {
        queue.sync {
            pendingSave?.cancel()
            pendingSave = nil

            let session = PersistedSession(
                rootBookmark: rootURL.flatMap { Self.bookmarkData(for: $0) },
                tabs: openTabURLs.compactMap { Self.bookmarkData(for: $0) },
                selectedTabIndex: selectedIndex
            )

            guard let encoded = try? JSONEncoder().encode(session) else { return }
            self.userDefaults.set(encoded, forKey: Self.userDefaultsKey)
        }
    }

    // MARK: - Load

    /// Returns a previously-saved session, or nil if none / unreadable.
    func load() -> PersistedSession? {
        guard let data = userDefaults.data(forKey: Self.userDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(PersistedSession.self, from: data)
    }

    /// Resolve a bookmark back into a URL. Returns nil if the file no longer
    /// exists, the bookmark is corrupted, or sandbox access is denied.
    /// `isStale` indicates the bookmark should be re-created on next save.
    static func resolveBookmark(_ data: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return (url, isStale)
        } catch {
            return nil
        }
    }

    // MARK: - Clear

    /// Wipe the persisted session — for "reset" features or first-run testing.
    func clear() {
        pendingSave?.cancel()
        pendingSave = nil
        userDefaults.removeObject(forKey: Self.userDefaultsKey)
    }

    // MARK: - Internal

    private static func bookmarkData(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            // Bookmark creation can fail if the URL was never security-scoped
            // to begin with (e.g. constructed from a string path). Fall back
            // to a non-scoped bookmark so a non-sandboxed build still benefits.
            return try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
    }
}
