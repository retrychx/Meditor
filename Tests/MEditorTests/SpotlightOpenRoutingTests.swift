import CoreSpotlight
import XCTest
@testable import MEditor

/// Spotlight 结果点击 → NSUserActivity → 打开文件的路由测试（MEditorAppDelegate）。
@MainActor
final class SpotlightOpenRoutingTests: XCTestCase {

    var state: AppState!
    var delegate: MEditorAppDelegate!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        state = AppState(fileService: MockFileService(), fileWatcher: MockFileWatcher())
        delegate = MEditorAppDelegate()
        delegate.appState = state
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spotlight-route-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        state = nil
        delegate = nil
        tempDir = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func spotlightActivity(identifier: String) -> NSUserActivity {
        let activity = NSUserActivity(activityType: MEditorAppDelegate.spotlightActivityType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: identifier]
        return activity
    }

    @discardableResult
    private func continueActivity(_ activity: NSUserActivity) -> Bool {
        delegate.application(NSApplication.shared, continue: activity) { _ in }
    }

    private func makeFile(_ name: String, under dir: URL? = nil) throws -> URL {
        let url = (dir ?? tempDir).appendingPathComponent(name)
        try "# Doc".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Tests

    func testSpotlightActivityOpensFileInsideWorkspace() throws {
        let file = try makeFile("doc.md")
        state.openFolder(tempDir)
        XCTAssertTrue(continueActivity(spotlightActivity(identifier: file.path)))
        XCTAssertEqual(state.openTabs.map(\.url.standardizedFileURL), [file.standardizedFileURL])
    }

    func testSpotlightActivityWithoutWorkspaceOpensParentFolder() throws {
        let file = try makeFile("doc.md")
        XCTAssertNil(state.rootURL)
        XCTAssertTrue(continueActivity(spotlightActivity(identifier: file.path)))
        XCTAssertEqual(state.rootURL?.standardizedFileURL, tempDir.standardizedFileURL)
        XCTAssertEqual(state.openTabs.map(\.url.standardizedFileURL), [file.standardizedFileURL])
    }

    func testSpotlightActivityOutsideWorkspaceOpensAsLooseFile() throws {
        state.openFolder(tempDir)
        let otherDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spotlight-route-other-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: otherDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: otherDir) }
        let outside = try makeFile("outside.md", under: otherDir)

        XCTAssertTrue(continueActivity(spotlightActivity(identifier: outside.path)))
        // 不切换工作区，散文件路径打开
        XCTAssertEqual(state.rootURL?.standardizedFileURL, tempDir.standardizedFileURL)
        XCTAssertTrue(state.openTabs.contains { $0.url.standardizedFileURL == outside.standardizedFileURL })
    }

    func testNonSpotlightActivityIgnored() {
        let activity = NSUserActivity(activityType: "com.example.unrelated")
        XCTAssertFalse(continueActivity(activity))
    }

    func testMissingFileIgnored() {
        let ghost = tempDir.appendingPathComponent("ghost-\(UUID().uuidString).md")
        XCTAssertFalse(continueActivity(spotlightActivity(identifier: ghost.path)))
        XCTAssertTrue(state.openTabs.isEmpty)
    }

    func testActivityWithoutIdentifierIgnored() {
        let activity = NSUserActivity(activityType: MEditorAppDelegate.spotlightActivityType)
        XCTAssertFalse(continueActivity(activity))
    }

    func testPendingOpensConsumedAfterAppStateInjection() throws {
        // 冷启动竞态：activity 先于 AppState 注入到达时应排队，注入后补开
        let freshDelegate = MEditorAppDelegate()
        let file = try makeFile("pending.md")
        XCTAssertTrue(freshDelegate.application(
            NSApplication.shared, continue: spotlightActivity(identifier: file.path)) { _ in })
        XCTAssertTrue(state.openTabs.isEmpty)

        freshDelegate.appState = state
        freshDelegate.consumePendingOpens()
        XCTAssertEqual(state.openTabs.map(\.url.standardizedFileURL), [file.standardizedFileURL])
    }
}
