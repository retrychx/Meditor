import XCTest
@testable import MEditor

@MainActor
final class TabManagerTests: XCTestCase {

    var tabManager: TabManager!
    var mockService: MockFileService!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        mockService = MockFileService()
        tabManager = TabManager(fileService: mockService)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TabManagerTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        tabManager = nil
        mockService = nil
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeFile(_ name: String, size: Int64 = 100) -> FileItem {
        let url = tempDir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data(count: Int(size)))
        mockService.mockAttributes[url] = [.size: size]
        return FileItem(url: url, isDirectory: false)
    }

    // MARK: - openFile

    func testOpenFileLargeFileTriggersWarning() {
        let item = makeFile("big.md", size: TabManager.largeFileThreshold + 1)
        tabManager.openFile(item)
        XCTAssertTrue(tabManager.showingLargeFileWarning)
        XCTAssertEqual(tabManager.pendingLargeFile?.url, item.url)
        XCTAssertTrue(tabManager.openTabs.isEmpty)
    }

    func testOpenFileSmallFileOpensTab() {
        let item = makeFile("small.md", size: 100)
        tabManager.openFile(item)
        XCTAssertFalse(tabManager.showingLargeFileWarning)
        XCTAssertEqual(tabManager.openTabs.count, 1)
    }

    // MARK: - openFileUnchecked

    func testOpenFileUncheckedExistingTabDoesNotDuplicate() {
        let item = makeFile("a.md")
        tabManager.openFileUnchecked(item)
        XCTAssertEqual(tabManager.openTabs.count, 1)
        let firstTabID = tabManager.openTabs[0].id

        tabManager.openFileUnchecked(item)
        XCTAssertEqual(tabManager.openTabs.count, 1)
        XCTAssertEqual(tabManager.selectedTabID, firstTabID)
    }

    func testOpenFileUncheckedSymlinkVariantURLDoesNotDuplicate() {
        let item = makeFile("a2.md")
        tabManager.openFileUnchecked(item)
        XCTAssertEqual(tabManager.openTabs.count, 1)
        let firstTabID = tabManager.openTabs[0].id

        // tempDir 在 /var/folders 下（/var → /private/var）：
        // 同一文件的符号链接变体 URL 不应开出第二个 tab
        let resolvedURL = item.url.resolvingSymlinksInPath()
        guard resolvedURL != item.url else { return }
        let variant = FileItem(url: resolvedURL, isDirectory: false)
        mockService.mockAttributes[resolvedURL] = [.size: 100]

        tabManager.openFileUnchecked(variant)
        XCTAssertEqual(tabManager.openTabs.count, 1)
        XCTAssertEqual(tabManager.selectedTabID, firstTabID)
    }

    // MARK: - closeTab

    func testCloseTabModifiedShowsConfirmation() {
        let item = makeFile("b.md")
        tabManager.openFileUnchecked(item)
        tabManager.openTabs[0].isModified = true
        let tabID = tabManager.openTabs[0].id

        tabManager.closeTab(tabID)

        XCTAssertTrue(tabManager.showingCloseConfirmation)
        XCTAssertNotNil(tabManager.pendingCloseTab)
        XCTAssertEqual(tabManager.openTabs.count, 1)
    }

    func testCloseTabUnmodifiedClosesDirectly() {
        let item = makeFile("c.md")
        tabManager.openFileUnchecked(item)
        let tabID = tabManager.openTabs[0].id

        tabManager.closeTab(tabID)

        XCTAssertFalse(tabManager.showingCloseConfirmation)
        XCTAssertTrue(tabManager.openTabs.isEmpty)
    }

    // MARK: - performCloseTab

    func testPerformCloseLastTabSetsSelectedTabIDNil() {
        let item = makeFile("d.md")
        tabManager.openFileUnchecked(item)
        let tabID = tabManager.openTabs[0].id

        tabManager.performCloseTab(tabID)

        XCTAssertNil(tabManager.selectedTabID)
        XCTAssertTrue(tabManager.openTabs.isEmpty)
    }

    func testPerformCloseSelectsNeighbour() {
        let a = makeFile("a.md")
        let b = makeFile("b.md")
        tabManager.openFileUnchecked(a)
        tabManager.openFileUnchecked(b)
        let bID = tabManager.openTabs[0].id

        tabManager.performCloseTab(bID)

        XCTAssertNotNil(tabManager.selectedTabID)
        XCTAssertEqual(tabManager.openTabs.count, 1)
    }

    // MARK: - selectNextTab / selectPreviousTab

    func testSelectNextTabWrapsAround() {
        let a = makeFile("a.md"); let b = makeFile("b.md"); let c = makeFile("c.md")
        tabManager.openFileUnchecked(a)
        tabManager.openFileUnchecked(b)
        tabManager.openFileUnchecked(c)
        // Tabs are inserted at index 0, so order is [c, b, a].
        let lastID = tabManager.openTabs.last!.id
        tabManager.selectedTabID = lastID

        tabManager.selectNextTab()

        XCTAssertEqual(tabManager.selectedTabID, tabManager.openTabs.first?.id,
                       "next from last should wrap to first")
    }

    func testSelectPreviousTabWrapsAround() {
        let a = makeFile("a.md"); let b = makeFile("b.md")
        tabManager.openFileUnchecked(a)
        tabManager.openFileUnchecked(b)
        let firstID = tabManager.openTabs.first!.id
        tabManager.selectedTabID = firstID

        tabManager.selectPreviousTab()

        XCTAssertEqual(tabManager.selectedTabID, tabManager.openTabs.last?.id,
                       "previous from first should wrap to last")
    }

    // MARK: - moveTab

    func testMoveTabInBounds() {
        let a = makeFile("a.md"); let b = makeFile("b.md"); let c = makeFile("c.md")
        tabManager.openFileUnchecked(a)
        tabManager.openFileUnchecked(b)
        tabManager.openFileUnchecked(c)
        let originalFirst = tabManager.openTabs[0].url

        tabManager.moveTab(from: 0, to: 2)

        XCTAssertEqual(tabManager.openTabs[2].url, originalFirst)
    }

    func testMoveTabOutOfBoundsDoesNotCrash() {
        let a = makeFile("a.md")
        tabManager.openFileUnchecked(a)

        XCTAssertNoThrow(tabManager.moveTab(from: 0, to: 99))
        XCTAssertNoThrow(tabManager.moveTab(from: -1, to: 0))
        XCTAssertEqual(tabManager.openTabs.count, 1)
    }

    // MARK: - reopenLastClosedTab

    func testReopenLastClosedTabRestoresTab() {
        let item = makeFile("reopen.md")
        tabManager.openFileUnchecked(item)
        let tabID = tabManager.openTabs[0].id
        tabManager.performCloseTab(tabID)
        XCTAssertTrue(tabManager.openTabs.isEmpty)

        tabManager.reopenLastClosedTab()

        XCTAssertEqual(tabManager.openTabs.count, 1)
        XCTAssertEqual(tabManager.openTabs[0].url, item.url)
    }

    // MARK: - updateTabContent

    func testUpdateTabContentMarksModified() {
        let item = makeFile("mod.md")
        tabManager.openFileUnchecked(item)
        let tabID = tabManager.openTabs[0].id
        tabManager.openTabs[0].isModified = false

        tabManager.updateTabContent(tabID, content: "new content")

        XCTAssertEqual(tabManager.openTabs[0].isModified, true)
        XCTAssertEqual(tabManager.openTabs[0].content, "new content")
    }

    // MARK: - reopenLastClosedTab (multiple closes)

    func testReopenClosedTabAfterMultipleCloses() {
        let a = makeFile("a.md")
        let b = makeFile("b.md")
        let c = makeFile("c.md")
        tabManager.openFileUnchecked(a)
        tabManager.openFileUnchecked(b)
        tabManager.openFileUnchecked(c)
        let aID = tabManager.openTabs.first { $0.url == a.url }!.id
        let bID = tabManager.openTabs.first { $0.url == b.url }!.id
        tabManager.performCloseTab(aID)
        tabManager.performCloseTab(bID)

        tabManager.reopenLastClosedTab()

        XCTAssertTrue(
            tabManager.openTabs.contains { $0.url == b.url },
            "Most recently closed tab (b) should be restored first"
        )
    }

    // MARK: - saveTab

    func testSaveTabClearsModifiedFlag() {
        let item = makeFile("save.md")
        tabManager.openFileUnchecked(item)
        let tab = tabManager.openTabs[0]
        tab.isModified = true

        tabManager.saveTab(tab)

        XCTAssertFalse(tab.isModified, "saveTab should clear isModified after a successful write")
    }
}
