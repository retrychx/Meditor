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
        // FSEvents 在 CI 慢机上延迟不可控，且 watcher 启动与首次写文件之间存在竞态：
        // 轮询等待回调（每 100ms 检查一次），超过 2s 未触发就重写文件再制造一次事件，
        // 最多等 15s，触发即提前结束。
        let box = CallbackBox()
        watcher.startWatching(urls: [tempDir]) {
            box.mark()
        }

        let file = tempDir.appendingPathComponent("trigger.txt")
        let deadline = Date().addingTimeInterval(15)
        var lastWrite = Date.distantPast
        while !box.fired && Date() < deadline {
            if Date().timeIntervalSince(lastWrite) >= 2 {
                try? "hello".write(to: file, atomically: true, encoding: .utf8)
                lastWrite = Date()
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }

        XCTAssertTrue(box.fired, "FileWatcher onChange 应在文件变化后 15s 内触发")
    }

    /// 回调触发标记的线程安全容器（FSEvents 回调在 watcher 的私有队列上触发）。
    private final class CallbackBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _fired = false
        func mark() { lock.lock(); _fired = true; lock.unlock() }
        var fired: Bool { lock.lock(); defer { lock.unlock() }; return _fired }
    }
}
