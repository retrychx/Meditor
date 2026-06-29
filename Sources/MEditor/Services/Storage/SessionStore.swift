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
    private enum BookmarkLookup {
        case hit(Data)
        case generated(Data)
        case failed
    }

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

    /// Cache bookmarkData by standardized URL to avoid repeated IPC calls.
    /// Each `bookmarkData(options:...)` invocation triggers a synchronous XPC
    /// round-trip to the scoped-bookmark agent — caching eliminates this for
    /// URLs that haven't changed between saves.
    private var bookmarkCache: [URL: Data] = [:]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - Save

    /// Schedule a save ~250ms in the future. Repeated calls within that window
    /// collapse to a single write. Use `saveNow` for app-quit flushes.
    func scheduleSave(rootURL: URL?, openTabURLs: [URL], selectedIndex: Int?) {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?._saveNow(rootURL: rootURL, openTabURLs: openTabURLs, selectedIndex: selectedIndex)
        }
        pendingSave = work
        queue.asyncAfter(deadline: .now() + .milliseconds(250), execute: work)
    }

    func saveNow(rootURL: URL?, openTabURLs: [URL], selectedIndex: Int?) {
        queue.sync {
            self._saveNow(rootURL: rootURL, openTabURLs: openTabURLs, selectedIndex: selectedIndex)
        }
    }

    private func _saveNow(rootURL: URL?, openTabURLs: [URL], selectedIndex: Int?) {
        pendingSave?.cancel()
        pendingSave = nil

        let session = PersistedSession(
            rootBookmark: rootURL.flatMap { bookmarkData(for: $0) },
            tabs: openTabURLs.compactMap { bookmarkData(for: $0) },
            selectedTabIndex: selectedIndex
        )

        // Prune cache entries for URLs no longer in the session.
        let activeURLs = Set(openTabURLs.map(\.standardizedFileURL) + [rootURL?.standardizedFileURL].compactMap { $0 })
        bookmarkCache = bookmarkCache.filter { activeURLs.contains($0.key) }

        guard let encoded = try? JSONEncoder().encode(session) else { return }
        self.userDefaults.set(encoded, forKey: Self.userDefaultsKey)
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

    /// Return cached bookmark data or create + cache it. Avoids redundant IPC.
    private func bookmarkData(for url: URL) -> Data? {
        let key = url.standardizedFileURL
        switch cachedBookmarkData(for: key) {
        case .hit(let data), .generated(let data):
            return data
        case .failed:
            return nil
        }
    }

    private func cachedBookmarkData(for url: URL) -> BookmarkLookup {
        if let cached = bookmarkCache[url] {
            PerformanceTracer.event("SessionBookmarkCacheHit", log: PerformanceTracer.session)
            return .hit(cached)
        }

        PerformanceTracer.event("SessionBookmarkCacheMiss", log: PerformanceTracer.session)
        let sid = PerformanceTracer.begin("SessionBookmarkCreate", log: PerformanceTracer.session)
        defer { PerformanceTracer.end("SessionBookmarkCreate", log: PerformanceTracer.session, id: sid) }

        guard let data = Self.bookmarkData(for: url) else {
            PerformanceTracer.event("SessionBookmarkCreateFailed", log: PerformanceTracer.session)
            return .failed
        }
        bookmarkCache[url] = data
        return .generated(data)
    }

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
            PerformanceTracer.event("SessionBookmarkFallbackNonScoped", log: PerformanceTracer.session)
            return try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
    }
}
