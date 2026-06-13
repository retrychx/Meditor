import Foundation

// MARK: - Tab forwarding

extension AppState {

    // State
    var openTabs: [EditorTab] {
        get { tabManager.openTabs }
        set { tabManager.openTabs = newValue }
    }
    var selectedTabID: UUID? {
        get { tabManager.selectedTabID }
        set { tabManager.selectedTabID = newValue }
    }
    var selectedTab: EditorTab? {
        get { tabManager.selectedTab }
        set { tabManager.selectedTabID = newValue?.id }
    }
    var pendingCloseTab: EditorTab? {
        get { tabManager.pendingCloseTab }
        set { tabManager.pendingCloseTab = newValue }
    }
    var showingCloseConfirmation: Bool {
        get { tabManager.showingCloseConfirmation }
        set { tabManager.showingCloseConfirmation = newValue }
    }
    var pendingLargeFile: FileItem? {
        get { tabManager.pendingLargeFile }
        set { tabManager.pendingLargeFile = newValue }
    }
    var showingLargeFileWarning: Bool {
        get { tabManager.showingLargeFileWarning }
        set { tabManager.showingLargeFileWarning = newValue }
    }
    var recentlyClosedURLs: [URL] {
        get { tabManager.recentlyClosedURLs }
        set { tabManager.recentlyClosedURLs = newValue }
    }

    // Actions
    func openFile(_ item: FileItem)                              { tabManager.openFile(item) }
    func openFileUnchecked(_ item: FileItem)                     { tabManager.openFileUnchecked(item) }
    func applyLoadedContent(tabID: UUID, content: String)        { tabManager.applyLoadedContent(tabID: tabID, content: content) }
    func failLoadingTab(tabID: UUID, url: URL, error: Error)     { tabManager.failLoadingTab(tabID: tabID, url: url, error: error) }
    func closeTab(_ tabID: UUID)                                 { tabManager.closeTab(tabID) }
    func confirmCloseTab(save: Bool)                             { tabManager.confirmCloseTab(save: save) }
    func performCloseTab(_ tabID: UUID)                          { tabManager.performCloseTab(tabID) }
    func updateTabContent(_ tabID: UUID, content: String)        { tabManager.updateTabContent(tabID, content: content) }
    func saveTab(_ tab: EditorTab)                               { tabManager.saveTab(tab) }
    func saveCurrentTab()                                        { tabManager.saveCurrentTab() }
    func selectTab(_ id: UUID)                                   { tabManager.selectTab(id) }
    func reopenLastClosedTab()                                   { tabManager.reopenLastClosedTab() }
    func selectNextTab()                                         { tabManager.selectNextTab() }
    func selectPreviousTab()                                     { tabManager.selectPreviousTab() }
    func moveTab(from src: Int, to dst: Int)                     { tabManager.moveTab(from: src, to: dst) }
}
