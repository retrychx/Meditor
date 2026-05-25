import XCTest
@testable import MEditor

// MARK: - Mock

final class MockFileService: FileServiceProtocol {
    var files: [URL: String] = [:]
    var children: [URL: [FileItem]] = [:]

    func loadImmediateChildren(of directory: URL) -> [FileItem] {
        children[directory] ?? []
    }

    func loadChildren(for item: FileItem) -> [FileItem] {
        let childs = children[item.url] ?? []
        item.children = childs
        return childs
    }

    func readFile(at url: URL) throws -> String {
        guard let content = files[url] else {
            throw NSError(domain: "mock", code: 1, userInfo: [NSLocalizedDescriptionKey: "File not found"])
        }
        return content
    }

    func writeFile(at url: URL, content: String) throws {
        files[url] = content
    }
}

// MARK: - Tests

final class AppStateTests: XCTestCase {

    var state: AppState!
    var mockService: MockFileService!

    override func setUp() {
        super.setUp()
        mockService = MockFileService()
        state = AppState(fileService: mockService)
    }

    override func tearDown() {
        state = nil
        mockService = nil
        super.tearDown()
    }

    // MARK: - Helpers

    func makeItem(_ name: String, isDir: Bool = false) -> FileItem {
        let url = URL(fileURLWithPath: "/tmp/\(name)")
        return FileItem(url: url, isDirectory: isDir)
    }

    func setupTab(_ name: String, content: String = "", language: EditorLanguage = .markdown) -> EditorTab {
        let url = URL(fileURLWithPath: "/tmp/\(name)")
        mockService.files[url] = content
        let item = FileItem(url: url, isDirectory: false)
        state.openFile(item)
        return state.selectedTab!
    }

    // MARK: - File Tree

    func test_openFolder_setsRootURLAndReloadsTree() {
        let root = URL(fileURLWithPath: "/tmp/project")
        mockService.children[root] = [
            makeItem("readme.md"),
            makeItem("src", isDir: true),
        ]

        state.openFolder(root)

        XCTAssertEqual(state.rootURL, root)
        XCTAssertEqual(state.fileTree.count, 2)
    }

    func test_reloadFileTree_clearsMapAndReloads() {
        let root = URL(fileURLWithPath: "/tmp/project")
        mockService.children[root] = [
            makeItem("a.md"),
            makeItem("b.md"),
        ]
        state.openFolder(root)
        state.fileItemMap[UUID()] = makeItem("c.md") // add stale entry

        state.reloadFileTree()

        XCTAssertEqual(state.fileTree.count, 2)
        XCTAssertEqual(state.fileItemMap.count, 2) // stale entry cleared
    }

    // MARK: - Tab Management

    func test_openFile_createsTab() {
        let url = URL(fileURLWithPath: "/tmp/hello.md")
        let item = FileItem(url: url, isDirectory: false)
        mockService.files[url] = "# Hello"

        state.openFile(item)

        XCTAssertEqual(state.openTabs.count, 1)
        XCTAssertEqual(state.selectedTab?.name, "hello.md")
        XCTAssertEqual(state.selectedTab?.content, "# Hello")
        XCTAssertEqual(state.selectedTab?.language, .markdown)
        XCTAssertEqual(state.selectedFileID, item.id)
    }

    func test_openFile_reusesExistingTab() {
        let tab = setupTab("hello.md", content: "# Hello")
        let item = FileItem(url: tab.url, isDirectory: false)

        state.openFile(item) // open same file again

        // Should reuse existing tab, not create a new one
        XCTAssertEqual(state.openTabs.count, 1)
        XCTAssertEqual(state.selectedTabID, tab.id)
    }

    func test_openFile_doesNotOpenDirectories() {
        let item = makeItem("subdir", isDir: true)

        state.openFile(item)

        XCTAssertEqual(state.openTabs.count, 0)
    }

    func test_openFile_setsEditorLanguageForHTML() {
        let url = URL(fileURLWithPath: "/tmp/page.html")
        mockService.files[url] = "<h1>Hi</h1>"
        let item = FileItem(url: url, isDirectory: false)

        state.openFile(item)

        XCTAssertEqual(state.selectedTab?.language, .html)
    }

    func test_closeTab_removesTab() {
        let tab1 = setupTab("a.md")
        let tab2 = setupTab("b.md")

        state.closeTab(tab1.id)

        XCTAssertEqual(state.openTabs.count, 1)
        XCTAssertEqual(state.openTabs[0].id, tab2.id)
    }

    func test_closeTab_unmodifiedWithConfirmation() {
        let tab = setupTab("a.md")
        // Don't modify — isModified stays false

        state.closeTab(tab.id)

        // Should close immediately without confirmation
        XCTAssertFalse(state.showingCloseConfirmation)
        XCTAssertNil(state.pendingCloseTab)
        XCTAssertTrue(state.openTabs.isEmpty)
    }

    func test_closeTab_modifiedShowsConfirmation() {
        let tab = setupTab("a.md", content: "original")
        state.updateTabContent(tab.id, content: "modified")

        state.closeTab(tab.id)

        XCTAssertTrue(state.showingCloseConfirmation)
        XCTAssertEqual(state.pendingCloseTab?.id, tab.id)
        XCTAssertEqual(state.openTabs.count, 1) // not removed yet
    }

    func test_confirmCloseTab_withSave() {
        let tab = setupTab("a.md", content: "original")
        state.updateTabContent(tab.id, content: "modified")

        state.closeTab(tab.id)
        state.confirmCloseTab(save: true)

        // Should have saved (written via mock)
        XCTAssertEqual(mockService.files[tab.url], "modified")
        XCTAssertTrue(state.openTabs.isEmpty)
        XCTAssertFalse(state.showingCloseConfirmation)
    }

    func test_confirmCloseTab_withoutSave() {
        let tab = setupTab("a.md", content: "original")
        state.updateTabContent(tab.id, content: "modified")

        state.closeTab(tab.id)
        state.confirmCloseTab(save: false)

        // Should NOT have saved
        XCTAssertEqual(mockService.files[tab.url], "original")
        XCTAssertTrue(state.openTabs.isEmpty)
    }

    func test_closeTab_selectsNextTab() {
        let tab1 = setupTab("a.md")
        let tab2 = setupTab("b.md")

        state.closeTab(tab1.id)

        XCTAssertEqual(state.selectedTabID, tab2.id)
    }

    func test_closeTab_selectsPreviousTabWhenLast() {
        let tab1 = setupTab("a.md")
        let tab2 = setupTab("b.md")

        state.closeTab(tab2.id) // close last tab

        XCTAssertEqual(state.selectedTabID, tab1.id)
    }

    func test_closeLastTab_clearsSelection() {
        let tab = setupTab("a.md")

        state.closeTab(tab.id)

        XCTAssertNil(state.selectedTabID)
        XCTAssertEqual(state.previewContent, "")
    }

    // MARK: - Tab Selection

    func test_selectTab_switchesPreview() {
        let tab1 = setupTab("a.md", content: "# A")
        setupTab("b.md", content: "# B")

        state.selectTab(tab1.id)

        XCTAssertEqual(state.selectedTabID, tab1.id)
        XCTAssertEqual(state.previewContent, "# A")
    }

    func test_selectedTab_computedProperty() {
        let tab = setupTab("a.md")
        XCTAssertEqual(state.selectedTab?.id, tab.id)

        state.selectedTab = nil
        XCTAssertNil(state.selectedTabID)
    }

    // MARK: - Tab Content

    func test_updateTabContent_updatesAndMarksModified() {
        let tab = setupTab("a.md", content: "original")

        state.updateTabContent(tab.id, content: "modified")

        XCTAssertEqual(state.openTabs[0].content, "modified")
        XCTAssertTrue(state.openTabs[0].isModified)
    }

    func test_updateTabContent_nonSelectedTabDoesNotTriggerPreview() {
        let tab1 = setupTab("a.md", content: "# A")
        let tab2 = setupTab("b.md", content: "# B")

        // Update the non-selected tab (tab1, since tab2 is selected)
        state.updateTabContent(tab1.id, content: "# A modified")

        // Preview should still show tab2's content
        XCTAssertEqual(state.previewContent, "# B")
    }

    // MARK: - Save

    func test_saveTab_writesAndClearsModified() {
        let tab = setupTab("a.md", content: "original")
        state.updateTabContent(tab.id, content: "updated")

        state.saveTab(state.openTabs[0])

        XCTAssertFalse(state.openTabs[0].isModified)
        XCTAssertEqual(mockService.files[tab.url], "updated")
    }

    func test_saveTab_unmodifiedDoesNothing() {
        let tab = setupTab("a.md", content: "hello")

        state.saveTab(state.openTabs[0])

        // Original file content unchanged (since we never modified)
        XCTAssertEqual(mockService.files[tab.url], "hello")
    }

    func test_saveCurrentTab_noSelectedTabDoesNothing() {
        // No crash when there's no selected tab
        state.saveCurrentTab()
        // Should not throw or crash
    }

    // MARK: - Tab Move

    func test_moveTab_reorders() {
        setupTab("a.md")
        setupTab("b.md")
        setupTab("c.md")

        // Move "c.md" from index 2 to index 0
        state.moveTab(from: 2, to: 0)

        XCTAssertEqual(state.openTabs[0].name, "c.md")
        XCTAssertEqual(state.openTabs[1].name, "a.md")
        XCTAssertEqual(state.openTabs[2].name, "b.md")
    }

    func test_moveTab_invalidIndexesDoesNothing() {
        setupTab("a.md")
        setupTab("b.md")

        state.moveTab(from: 5, to: 0)

        XCTAssertEqual(state.openTabs.count, 2)
        XCTAssertEqual(state.openTabs[0].name, "a.md")
    }

    // MARK: - Preview

    func test_openFile_syncsPreview() {
        let url = URL(fileURLWithPath: "/tmp/preview.md")
        mockService.files[url] = "# Preview"
        let item = FileItem(url: url, isDirectory: false)

        state.openFile(item)

        XCTAssertEqual(state.previewContent, "# Preview")
        XCTAssertEqual(state.previewLanguage, .markdown)
    }

    func test_currentFileSize_returnsFormattedSize() {
        setupTab("a.md", content: "hello")

        XCTAssertFalse(state.currentFileSize.isEmpty)
        XCTAssertTrue(state.currentFileSize.contains("5")) // "hello" is 5 bytes
    }

    func test_currentFileSize_noSelectedTab_returnsEmpty() {
        // Expect empty string when no tab is selected
        // This can happen if selectedTabID is nil but openTabs has entries
        XCTAssertEqual(state.currentFileSize, "")
    }

    // MARK: - Security Scoped Resources

    func test_beginEndAccessing_roundTrip() {
        let url = URL(fileURLWithPath: "/tmp/test.md")
        state.beginAccessing(url)
        state.endAccessing(url)
        // Should not crash — actual security scope needs real sandboxed file
    }

    // MARK: - Cursor

    func test_updateCursorPosition() {
        state.updateCursorPosition(line: 5, column: 12)
        XCTAssertEqual(state.cursorLine, 5)
        XCTAssertEqual(state.cursorColumn, 12)
    }

    // MARK: - Error

    func test_setError() {
        state.setError("Something went wrong")
        XCTAssertEqual(state.errorMessage, "Something went wrong")
    }
}
