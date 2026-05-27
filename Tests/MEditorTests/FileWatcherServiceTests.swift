import XCTest
@testable import MEditor

final class FileWatcherServiceTests: XCTestCase {

    var watcher: FileWatcherService!
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        watcher = FileWatcherService()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileWatcherTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        watcher.stopWatching()
        watcher = nil
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    func test_startWatching_doesNotCrash() {
        // Basic lifecycle test — start and stop without crash
        watcher.startWatching(urls: [tempDir]) {}
        watcher.stopWatching()
    }

    func test_stopWatching_isIdempotent() {
        watcher.stopWatching() // no-op when not watching
        watcher.startWatching(urls: [tempDir]) {}
        watcher.stopWatching()
        watcher.stopWatching() // second stop is no-op
    }

    func test_startWatching_replacesExistingWatch() {
        var count1 = 0
        var count2 = 0

        watcher.startWatching(urls: [tempDir]) { count1 += 1 }
        watcher.startWatching(urls: [tempDir]) { count2 += 1 }

        // First callback should be replaced — only count2 should fire
        // We can't easily trigger FSEvents in a unit test, but at least
        // verify no crash on replacement
        watcher.stopWatching()
        XCTAssertEqual(count1, 0)
    }

    func test_deinit_stopsWatching() {
        var localWatcher: FileWatcherService? = FileWatcherService()
        localWatcher?.startWatching(urls: [tempDir]) {}
        localWatcher = nil
        // Should not crash — deinit calls stopWatching
    }

    func test_onChange_firesOnFileChange() {
        let expectation = expectation(description: "onChange fires")
        expectation.isInverted = false

        watcher.startWatching(urls: [tempDir]) {
            expectation.fulfill()
        }

        // Create a file to trigger FSEvents
        let file = tempDir.appendingPathComponent("trigger.txt")
        try? "hello".write(to: file, atomically: true, encoding: .utf8)

        wait(for: [expectation], timeout: 5.0)
    }
}
