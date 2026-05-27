import CoreServices
import Foundation

// MARK: - C callback (must be a non-capturing function pointer)

private let fileWatcherCallback: FSEventStreamCallback = { _, info, _, _, _, _ in
    guard let info else { return }
    let watcher = Unmanaged<FileWatcherService>.fromOpaque(info).takeUnretainedValue()
    // Read the handler under the lock to avoid racing with stopWatching.
    let handler = watcher.lockedGetHandler()
    if let handler {
        DispatchQueue.main.async { handler() }
    }
}

final class FileWatcherService: FileWatcherServiceProtocol {
    private var streamRef: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.meditor.filewatcher")
    /// Protected by `lock` — accessed from both `queue` (callback) and main thread.
    private var _onChange: (() -> Void)?
    private let lock = NSLock()

    /// Thread-safe read of the onChange handler.
    fileprivate func lockedGetHandler() -> (() -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return _onChange
    }

    func startWatching(urls: [URL], onChange: @escaping () -> Void) {
        stopWatching()

        lock.lock()
        _onChange = onChange
        lock.unlock()

        let paths = urls.map { $0.path } as CFArray

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            fileWatcherCallback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagFileEvents)
        ) else { return }

        streamRef = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stopWatching() {
        guard let stream = streamRef else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        streamRef = nil

        // Drain any in-flight callbacks on the queue before clearing the handler.
        // After FSEventStreamInvalidate, no NEW callbacks will fire, but already-
        // dispatched blocks may still be in the queue. This sync barrier ensures
        // they complete before we nil out the handler.
        queue.sync {}

        lock.lock()
        _onChange = nil
        lock.unlock()
    }

    deinit {
        stopWatching()
    }
}
