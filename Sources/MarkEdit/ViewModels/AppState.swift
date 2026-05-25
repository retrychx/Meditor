import Foundation
import Observation

enum EditorLanguage: String {
    case markdown
    case html
}

@Observable
final class AppState {
    var fileTree: [FileItem] = []
    var selectedFileID: UUID?
    var rootURL: URL?
    var openTabs: [EditorTab] = []
    var selectedTabID: UUID?
    var previewContent: String = ""
    var previewLanguage: EditorLanguage = .markdown

    private let fileService = FileService()

    var selectedTab: EditorTab? {
        get { openTabs.first { $0.id == selectedTabID } }
        set {
            guard let newValue else {
                selectedTabID = nil
                return
            }
            selectedTabID = newValue.id
        }
    }

    // MARK: - File tree

    func openFolder(_ url: URL) {
        rootURL = url
        fileTree = fileService.loadContents(of: url)
    }

    func selectFile(_ item: FileItem) {
        if item.isDirectory {
            selectedFileID = item.id
        } else {
            openFile(item)
        }
    }

    // MARK: - Tabs

    func openFile(_ item: FileItem) {
        guard !item.isDirectory else { return }

        selectedFileID = item.id

        // Check if already open
        if let existing = openTabs.first(where: { $0.url == item.url }) {
            selectedTabID = existing.id
            syncPreviewContent(from: existing)
            return
        }

        do {
            let content = try fileService.readFile(at: item.url)
            let lang: EditorLanguage = item.extension == "md" || item.extension == "markdown" ? .markdown : .html
            let tab = EditorTab(url: item.url, content: content, language: lang)
            openTabs.append(tab)
            selectedTabID = tab.id
            syncPreviewContent(from: tab)
        } catch {
            print("Failed to open file: \(error)")
        }
    }

    func closeTab(_ tabID: UUID) {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabID }) else { return }

        let tab = openTabs[idx]
        if tab.isModified {
            // For now, just close. Could add save prompt.
            saveTab(tab)
        }

        openTabs.remove(at: idx)

        if selectedTabID == tabID {
            if idx < openTabs.count {
                selectedTabID = openTabs[idx].id
            } else if !openTabs.isEmpty {
                selectedTabID = openTabs.last?.id
            } else {
                selectedTabID = nil
                previewContent = ""
            }
        }

        if let newTab = selectedTab {
            syncPreviewContent(from: newTab)
        }
    }

    func updateTabContent(_ tabID: UUID, content: String) {
        guard let idx = openTabs.firstIndex(where: { $0.id == tabID }) else { return }
        openTabs[idx].content = content
        openTabs[idx].isModified = true

        if tabID == selectedTabID {
            previewContent = content
            previewLanguage = openTabs[idx].language
        }
    }

    func saveTab(_ tab: EditorTab) {
        guard tab.isModified else { return }
        do {
            try fileService.writeFile(at: tab.url, content: tab.content)
            if let idx = openTabs.firstIndex(where: { $0.id == tab.id }) {
                openTabs[idx].isModified = false
            }
        } catch {
            print("Failed to save file: \(error)")
        }
    }

    func saveCurrentTab() {
        guard let tab = selectedTab else { return }
        saveTab(tab)
    }

    // MARK: - Private

    private func syncPreviewContent(from tab: EditorTab) {
        previewContent = tab.content
        previewLanguage = tab.language
    }
}
