import Foundation

/// Manages tab lifecycle: open, close, reorder, select.
/// Extracted from AppState to reduce single-class complexity.
@MainActor
final class TabManager {
    private let fileService: FileServiceProtocol
    private let onTabsChanged: () -> Void

    var openTabs: [EditorTab] = [] {
        didSet { onTabsChanged() }
    }
    var selectedTabID: UUID? {
        didSet { onTabsChanged() }
    }

    /// Stack of URLs from recently closed tabs, used by reopen.
    private var recentlyClosedURLs: [URL] = []
    private static let recentlyClosedLimit = 16

    // MARK: - Tab close confirmation
    var pendingCloseTab: EditorTab?
    var showingCloseConfirmation = false

    var selectedTab: EditorTab? {
        get { openTabs.first { $0.id == selectedTabID } }
        set { selectedTabID = newValue?.id }
    }

    init(fileService: FileServiceProtocol, onTabsChanged: @escaping () -> Void) {
        self.fileService = fileService
        self.onTabsChanged = onTabsChanged
    }

    // MARK: - Open

    /// Returns (tab, isNew) — isNew=false means an existing tab was reused.
    @discardableResult
    func openTab(url: URL, language: EditorLanguage) -> (tab: EditorTab, isNew: Bool) {
        if let existing = openTabs.first(where: { $0.url == url }) {
            selectedTabID = existing.id
            return (existing, false)
        }
        let tab = EditorTab(url: url, content: "", language: language)
        openTabs.insert(tab, at: 0)
        selectedTabID = tab.id
        return (tab, true)
    }

    // MARK: - Close

    func closeTab(_ tabID: UUID) -> Bool {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabID }) else { return false }
        let tab = openTabs[idx]
        if tab.isModified {
            pendingCloseTab = tab
            showingCloseConfirmation = true
            return false
        }
        performClose(tabID)
        return true
    }

    func confirmClose(save: Bool) {
        guard let tab = pendingCloseTab else { return }
        if save {
            do {
                try fileService.writeFile(at: tab.url, content: tab.content)
                if let idx = openTabs.firstIndex(where: { $0.id == tab.id }) {
                    openTabs[idx].isModified = false
                }
            } catch {}
        }
        performClose(tab.id)
        pendingCloseTab = nil
        showingCloseConfirmation = false
    }

    /// Returns the URL of the closed tab for security-scope release.
    @discardableResult
    func performClose(_ tabID: UUID) -> URL? {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabID }) else { return nil }
        let closingURL = openTabs[idx].url
        openTabs.remove(at: idx)

        recentlyClosedURLs.append(closingURL)
        if recentlyClosedURLs.count > Self.recentlyClosedLimit {
            recentlyClosedURLs.removeFirst()
        }

        if selectedTabID == tabID {
            if idx < openTabs.count {
                selectedTabID = openTabs[idx].id
            } else if !openTabs.isEmpty {
                selectedTabID = openTabs.last?.id
            } else {
                selectedTabID = nil
            }
        }
        return closingURL
    }

    // MARK: - Content

    func updateContent(_ tabID: UUID, content: String) {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabID }) else { return }
        openTabs[idx].content = content
        openTabs[idx].isModified = true
    }

    func applyLoadedContent(tabID: UUID, content: String) {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabID }) else { return }
        openTabs[idx].content = content
    }

    // MARK: - Navigation

    func selectTab(_ id: UUID) {
        selectedTabID = id
    }

    func selectNextTab() {
        guard openTabs.count > 1, let id = selectedTabID,
              let idx = openTabs.firstIndex(where: { $0.id == id }) else { return }
        selectTab(openTabs[(idx + 1) % openTabs.count].id)
    }

    func selectPreviousTab() {
        guard openTabs.count > 1, let id = selectedTabID,
              let idx = openTabs.firstIndex(where: { $0.id == id }) else { return }
        selectTab(openTabs[(idx - 1 + openTabs.count) % openTabs.count].id)
    }

    func moveTab(from sourceIndex: Int, to destIndex: Int) {
        guard sourceIndex >= 0, sourceIndex < openTabs.count,
              destIndex >= 0, destIndex < openTabs.count else { return }
        let tab = openTabs.remove(at: sourceIndex)
        openTabs.insert(tab, at: destIndex)
    }

    // MARK: - Reopen

    /// Returns the URL to reopen, or nil if nothing to reopen.
    func popRecentlyClosed() -> URL? {
        while let url = recentlyClosedURLs.popLast() {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if openTabs.contains(where: { $0.url == url }) { continue }
            return url
        }
        return nil
    }

    // MARK: - Save

    func saveTab(_ tab: EditorTab) throws {
        guard tab.isModified else { return }
        try fileService.writeFile(at: tab.url, content: tab.content)
        if let idx = openTabs.firstIndex(where: { $0.id == tab.id }) {
            openTabs[idx].isModified = false
        }
    }
}
