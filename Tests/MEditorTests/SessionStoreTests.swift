import XCTest
@testable import MEditor

final class SessionStoreTests: XCTestCase {

    var store: SessionStore!
    var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SessionStoreTests")!
        defaults.removePersistentDomain(forName: "SessionStoreTests")
        store = SessionStore(userDefaults: defaults)
    }

    override func tearDown() {
        store.clear()
        defaults.removePersistentDomain(forName: "SessionStoreTests")
        defaults = nil
        store = nil
        super.tearDown()
    }

    // MARK: - Save & Load Round-Trip

    func test_saveNow_and_load_roundTrip() {
        let root = URL(fileURLWithPath: "/tmp/project")
        let tabs = [
            URL(fileURLWithPath: "/tmp/project/a.md"),
            URL(fileURLWithPath: "/tmp/project/b.md"),
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
        let root = URL(fileURLWithPath: "/tmp/project")
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
        let tabs = [URL(fileURLWithPath: "/tmp/a.md")]
        store.saveNow(rootURL: nil, openTabURLs: tabs, selectedIndex: nil)

        let session = store.load()
        XCTAssertNil(session?.selectedTabIndex)
    }

    func test_scheduleSave_eventuallyPersists() {
        let root = URL(fileURLWithPath: "/tmp/project")
        let tabs = [URL(fileURLWithPath: "/tmp/project/c.md")]

        store.scheduleSave(rootURL: root, openTabURLs: tabs, selectedIndex: 0)

        // scheduleSave debounces at 250ms
        let expectation = expectation(description: "debounced save")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        let session = store.load()
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
        let root = URL(fileURLWithPath: "/tmp/project")

        // Rapid-fire saves — only the last should persist
        store.scheduleSave(rootURL: root, openTabURLs: [URL(fileURLWithPath: "/tmp/1.md")], selectedIndex: 0)
        store.scheduleSave(rootURL: root, openTabURLs: [URL(fileURLWithPath: "/tmp/2.md")], selectedIndex: 0)
        store.scheduleSave(rootURL: root, openTabURLs: [URL(fileURLWithPath: "/tmp/3.md")], selectedIndex: 0)

        let expectation = expectation(description: "coalesced save")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        let session = store.load()
        // Should have 1 tab (the last save)
        XCTAssertEqual(session?.tabs.count, 1)
    }
}
