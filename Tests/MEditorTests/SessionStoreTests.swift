import XCTest
@testable import MEditor

final class SessionStoreTests: XCTestCase {

    var store: SessionStore!
    var defaults: UserDefaults!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SessionStoreTests")!
        defaults.removePersistentDomain(forName: "SessionStoreTests")
        store = SessionStore(userDefaults: defaults)
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionStoreTests_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        store.clear()
        defaults.removePersistentDomain(forName: "SessionStoreTests")
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        defaults = nil
        store = nil
        super.tearDown()
    }

    @discardableResult
    private func createFile(_ name: String, contents: String = "") -> URL {
        let url = tempDir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data(contents.utf8))
        return url
    }

    /// 轮询等待 debounced 保存落盘。scheduleSave 的 250ms debounce 跑在 utility 队列上，
    /// CI 慢机上固定等 0.5s 不可靠；改为轮询直到满足条件（触发即提前返回），最多 5s。
    private func waitForPersistedSession(
        timeout: TimeInterval = 5.0,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ predicate: (SessionStore.PersistedSession) -> Bool
    ) -> SessionStore.PersistedSession? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let session = store.load(), predicate(session) { return session }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        XCTFail("等待 debounced 保存超时（\(timeout)s）", file: file, line: line)
        return store.load()
    }

    // MARK: - Save & Load Round-Trip

    func test_saveNow_and_load_roundTrip() {
        let root = tempDir!
        let tabs = [
            createFile("a.md"),
            createFile("b.md"),
        ]

        store.saveNow(rootURL: root, openTabURLs: tabs, selectedIndex: 1)

        let session = store.load()
        XCTAssertNotNil(session)
        XCTAssertNotNil(session?.rootBookmark)
        XCTAssertEqual(session?.tabs.count, 2)
        XCTAssertEqual(session?.selectedTabIndex, 1)
    }

    func test_load_returnsNil_whenNoSession() {
        let session = store.load()
        XCTAssertNil(session)
    }

    func test_clear_removesSession() {
        let root = tempDir!
        store.saveNow(rootURL: root, openTabURLs: [], selectedIndex: nil)
        XCTAssertNotNil(store.load())

        store.clear()
        XCTAssertNil(store.load())
    }

    func test_saveNow_withNilRoot() {
        store.saveNow(rootURL: nil, openTabURLs: [], selectedIndex: nil)

        let session = store.load()
        XCTAssertNotNil(session)
        XCTAssertNil(session?.rootBookmark)
        XCTAssertEqual(session?.tabs.count, 0)
        XCTAssertNil(session?.selectedTabIndex)
    }

    func test_saveNow_withSelectedIndex_nil() {
        let tabs = [createFile("a.md")]
        store.saveNow(rootURL: nil, openTabURLs: tabs, selectedIndex: nil)

        let session = store.load()
        XCTAssertNil(session?.selectedTabIndex)
    }

    func test_scheduleSave_eventuallyPersists() {
        let root = tempDir!
        let tabs = [createFile("c.md")]

        store.scheduleSave(rootURL: root, openTabURLs: tabs, selectedIndex: 0)

        // scheduleSave debounces 250ms — 轮询等待落盘，而非固定 sleep
        let session = waitForPersistedSession { $0.tabs.count == 1 }
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.tabs.count, 1)
    }

    // MARK: - Bookmark Resolution

    func test_resolveBookmark_returnsNil_forInvalidData() {
        let result = SessionStore.resolveBookmark(Data([0, 1, 2, 3]))
        XCTAssertNil(result)
    }

    func test_resolveBookmark_returnsNil_forEmptyData() {
        let result = SessionStore.resolveBookmark(Data())
        XCTAssertNil(result)
    }

    // MARK: - Multiple Saves Coalesce

    func test_scheduleSave_coalescesBurstySaves() {
        let root = tempDir!

        // Rapid-fire saves — only the last should persist
        store.scheduleSave(rootURL: root, openTabURLs: [createFile("1.md")], selectedIndex: 0)
        store.scheduleSave(rootURL: root, openTabURLs: [createFile("2.md")], selectedIndex: 0)
        store.scheduleSave(rootURL: root, openTabURLs: [createFile("3.md")], selectedIndex: 0)

        // 三次调用合并为最后一次保存；轮询等待落盘，而非固定 sleep
        let session = waitForPersistedSession { $0.tabs.count == 1 }
        // Should have 1 tab (the last save)
        XCTAssertEqual(session?.tabs.count, 1)
    }

    // MARK: - scheduleSave round-trip

    func test_scheduleAndLoad_roundTrip() {
        let root = tempDir!
        let tab = createFile("roundtrip.md")

        store.scheduleSave(rootURL: root, openTabURLs: [tab], selectedIndex: 0)

        let session = waitForPersistedSession { $0.tabs.count == 1 }
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.tabs.count, 1)
        XCTAssertEqual(session?.selectedTabIndex, 0)
    }

    // MARK: - Bookmark cache

    func test_bookmarkCacheHit_resultConsistentAcrossSaves() {
        let root = tempDir!
        let tab = createFile("cached.md")

        store.saveNow(rootURL: root, openTabURLs: [tab], selectedIndex: 0)
        let first = store.load()

        store.saveNow(rootURL: root, openTabURLs: [tab], selectedIndex: 0)
        let second = store.load()

        // Both loads should resolve to the same tab count — bookmark consistency.
        XCTAssertEqual(first?.tabs.count, second?.tabs.count)
        XCTAssertEqual(first?.selectedTabIndex, second?.selectedTabIndex)
    }
}
