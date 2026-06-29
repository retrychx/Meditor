import CoreServices
import Foundation

// MARK: - Claude 文件事件

struct ClaudeFileEvent {
    /// Claude 通过 Write tool 创建的文件路径
    let fileURL: URL
    /// 来自哪个 session（JSONL 文件路径）
    let sessionURL: URL
}

// MARK: - ClaudeSessionMonitor

/// 监听 ~/.claude/projects/ 下的 JSONL 会话文件，
/// 当 Claude Code 执行 Write tool 创建匹配扩展名的文件时，回调通知。
@MainActor
final class ClaudeSessionMonitor {

    // MARK: - Public

    /// 发现新文件时触发（主线程）
    var onFileCreated: ((ClaudeFileEvent) -> Void)?

    /// 是否正在监听
    private(set) var isRunning = false

    // MARK: - Private

    /// FSEvent stream，只在主线程写，通过 lock 保护跨线程读。
    private nonisolated(unsafe) var streamRef: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.meditor.claude-monitor", qos: .utility)
    /// 保护所有跨线程可变状态（fileOffsets / watchedDirectory / allowedExtensions）。
    private let stateLock = NSLock()

    /// 每个 JSONL 文件已读到的字节偏移（queue + stateLock 保护）。
    private nonisolated(unsafe) var _fileOffsets: [String: UInt64] = [:]
    /// 当前监听的目录（start/stop 写；callback 读，均通过 stateLock）。
    private nonisolated(unsafe) var _watchedDirectory: URL?
    /// 当前匹配的扩展名集合（start 写一次后只读）。
    private nonisolated(unsafe) var _allowedExtensions: Set<String> = ["md", "txt"]

    // MARK: - Start / Stop

    func start(directory: URL, extensions: [String]) {
        guard !isRunning else {
            // 如果配置变了，重启
            stop()
            start(directory: directory, extensions: extensions)
            return
        }

        stateLock.withLock {
            _watchedDirectory = directory
            _allowedExtensions = Set(extensions.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) })
            _fileOffsets = [:]
        }

        // 预扫描已有文件，记录偏移（不触发旧内容的通知）
        prescanExistingFiles(in: directory)

        // 启动 FSEventStream
        let paths = [directory.path] as CFArray
        // passRetained + retain/release 回调：FSEventStream 持有 self 的强引用，
        // 保证 callback 执行期间 self 不会被释放（修复 passUnretained 悬空指针）。
        var ctx = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(self).toOpaque(),
            retain: { ptr -> UnsafeRawPointer? in
                guard let ptr else { return nil }
                Unmanaged<ClaudeSessionMonitor>.fromOpaque(ptr).retain()
                return ptr
            },
            release: { ptr in
                guard let ptr else { return }
                Unmanaged<ClaudeSessionMonitor>.fromOpaque(ptr).release()
            },
            copyDescription: nil
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            claudeMonitorCallback,
            &ctx,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.8, // latency: 800ms 合批
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagFileEvents)
        ) else { return }

        streamRef = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        isRunning = true
    }

    func stop() {
        guard let stream = streamRef else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        streamRef = nil
        isRunning = false
        // 排龙 in-flight 回调：FSEventStreamInvalidate 后不再触发新回调，
        // 但已入队的可能还在运行，同步屏障确保完成再清空状态。
        queue.sync {}   // 等待尚在执行中的 callback 完成
        stateLock.withLock {
            _fileOffsets = [:]
            _watchedDirectory = nil
        }
    }

    deinit {
        // 必须在 queue 有共对止之前清理流，否则 callback 返回时会访问已释放的 self。
        if let stream = streamRef {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)   // 触发 release 回调，平衡 passRetained 的 +1
            queue.sync {}                  // 确保已入队的 callback 都完成
        }
    }

    // MARK: - FSEvent callback handler (called on watcher queue)

    fileprivate nonisolated func handleFSEvent() {
        guard let dir = stateLock.withLock({ _watchedDirectory }) else { return }
        // 直接在 queue 上扫描（已在 queue.async 中）
        let events = scanNewLines(in: dir)
        if !events.isEmpty {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                for event in events {
                    self.onFileCreated?(event)
                }
            }
        }
    }

    // MARK: - Prescan

    private nonisolated func prescanExistingFiles(in dir: URL) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var offsets: [String: UInt64] = [:]
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "jsonl" else { continue }
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                offsets[url.path] = UInt64(size)
            }
        }
        stateLock.withLock { _fileOffsets = offsets }
    }

    // MARK: - JSONL scan

    private nonisolated func scanNewLines(in dir: URL) -> [ClaudeFileEvent] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var events: [ClaudeFileEvent] = []

        for case let jsonlURL as URL in enumerator {
            guard jsonlURL.pathExtension.lowercased() == "jsonl" else { continue }

            let key = jsonlURL.path
            let currentSize: UInt64
            if let s = try? jsonlURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                currentSize = UInt64(s)
            } else { continue }

            let lastOffset = _fileOffsets[key] ?? 0
            guard currentSize > lastOffset else {
                _fileOffsets[key] = currentSize
                continue
            }

            // 读取新增的字节
            guard let fh = FileHandle(forReadingAtPath: key) else { continue }
            fh.seek(toFileOffset: lastOffset)
            let newData = fh.readData(ofLength: Int(currentSize - lastOffset))
            fh.closeFile()
            _fileOffsets[key] = currentSize

            // 逐行解析 JSONL
            let newText = String(data: newData, encoding: .utf8) ?? ""
            for line in newText.split(separator: "\n", omittingEmptySubsequences: true) {
                if let fileEvent = parseJSONL(String(line), sessionURL: jsonlURL) {
                    events.append(fileEvent)
                }
            }
        }

        return events
    }

    // MARK: - JSONL line parser

    private nonisolated func parseJSONL(_ line: String, sessionURL: URL) -> ClaudeFileEvent? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // 结构：{ "message": { "role": "assistant", "content": [...] } }
        guard let message = json["message"] as? [String: Any],
              let role = message["role"] as? String, role == "assistant",
              let content = message["content"] as? [[String: Any]]
        else { return nil }

        for block in content {
            guard let type = block["type"] as? String, type == "tool_use",
                  let name = block["name"] as? String,
                  let input = block["input"] as? [String: Any]
            else { continue }

            // 只关注 Write（创建文件）
            guard name == "Write" else { continue }

            guard let filePath = input["file_path"] as? String else { continue }
            let fileURL = URL(fileURLWithPath: filePath)
            let ext = fileURL.pathExtension.lowercased()

            let exts = stateLock.withLock { _allowedExtensions }
            guard exts.contains(ext) else { continue }

            // 文件必须确实存在（排除假路径）
            guard FileManager.default.fileExists(atPath: filePath) else { continue }

            return ClaudeFileEvent(fileURL: fileURL, sessionURL: sessionURL)
        }

        return nil
    }
}

// MARK: - FSEvent C callback

private let claudeMonitorCallback: FSEventStreamCallback = { _, info, _, _, _, _ in
    guard let info else { return }
    // passRetained 将对象的强引用转让给 FSEventStream，流存活就能安全访问 self。
    let monitor = Unmanaged<ClaudeSessionMonitor>.fromOpaque(info).takeUnretainedValue()
    // handleFSEvent 展开后是同步扫描，已经在 watcher queue 上，直接调用
    monitor.handleFSEvent()
}
