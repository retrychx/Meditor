import XCTest
@testable import MEditor

final class PreviewThemeStoreTests: XCTestCase {

    var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "PreviewThemeStoreTests")!
        defaults.removePersistentDomain(forName: "PreviewThemeStoreTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "PreviewThemeStoreTests")
        defaults = nil
        super.tearDown()
    }

    func test_defaultTheme_isGithub() {
        let store = PreviewThemeStore(userDefaults: defaults)
        XCTAssertEqual(store.current, .github)
    }

    func test_setTheme_persists() {
        let store = PreviewThemeStore(userDefaults: defaults)
        store.current = .dracula

        // Create a new store with same defaults — should restore
        let store2 = PreviewThemeStore(userDefaults: defaults)
        XCTAssertEqual(store2.current, .dracula)
    }

    func test_invalidPersistedValue_fallsBackToGithub() {
        defaults.set("nonexistent_theme", forKey: "MEditor.previewTheme")

        let store = PreviewThemeStore(userDefaults: defaults)
        XCTAssertEqual(store.current, .github)
    }
}
