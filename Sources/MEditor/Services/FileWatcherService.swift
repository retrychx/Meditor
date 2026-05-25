import CoreServices
import Foundation

// MARK: - C callback (must be a non-capturing function pointer)

private let fileWatcherCallback: FSEventStreamCallback = { _, info, _, _, _, _ in
    guard let info else { return }
    let watcher = Unmanaged<FileWatcherService>.fromOpaque(info).takeUnretainedValue()
    DispatchQueue.main.async {
        watcher.onChange?()
    }
}

final class FileWatcherService {
    private var streamRef: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.markedit.filewatcher")
    fileprivate var onChange: (() -> Void)?

    func startWatching(urls: [URL], onChange: @escaping () -> Void) {
        stopWatching()

        self.onChange = onChange

        let paths = urls.map { ($0 as NSURL).fileSystemRepresentation }

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
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagFileEvents)
        ) else { return }

        streamRef = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stopWatching() {
        guard let streamRef else { return }
        FSEventStreamStop(streamRef)
        FSEventStreamInvalidate(streamRef)
        FSEventStreamRelease(streamRef)
        self.streamRef = nil
        onChange = nil
    }

    deinit {
        stopWatching()
    }
}
