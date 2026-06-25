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

    // MARK: - Private (accessed only from queue — nonisolated(unsafe))

    private nonisolated(unsafe) var streamRef: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.meditor.claude-monitor", qos: .utility)

    /// 每个 JSONL 文件已读到的字节偏移（queue 上修改）
    private nonisolated(unsafe) var fileOffsets: [String: UInt64] = [:]

    /// 当前监听的目录（start 时设置，之后只读）
    private nonisolated(unsafe) var watchedDirectory: URL?

    /// 当前匹配的扩展名集合（start 时设置，之后只读）
    private nonisolated(unsafe) var allowedExtensions: Set<String> = ["md", "txt"]

    // MARK: - Start / Stop

    func start(directory: URL, extensions: [String]) {
        guard !isRunning else {
            // 如果配置变了，重启
            stop()
            start(directory: directory, extensions: extensions)
            return
        }

        watchedDirectory = directory
        allowedExtensions = Set(extensions.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) })
        fileOffsets = [:]

        // 预扫描已有文件，记录偏移（不触发旧内容的通知）
        prescanExistingFiles(in: directory)

        // 启动 FSEventStream
        let paths = [directory.path] as CFArray
        var ctx = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
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
        queue.sync {}
        fileOffsets = [:]
        watchedDirectory = nil
    }

    deinit {
        if let stream = streamRef {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    // MARK: - FSEvent callback handler (called on watcher queue)

    fileprivate nonisolated func handleFSEvent() {
        guard let dir = watchedDirectory else { return }
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

        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "jsonl" else { continue }
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                fileOffsets[url.path] = UInt64(size)
            }
        }
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

            let lastOffset = fileOffsets[key] ?? 0
            guard currentSize > lastOffset else {
                fileOffsets[key] = currentSize
                continue
            }

            // 读取新增的字节
            guard let fh = FileHandle(forReadingAtPath: key) else { continue }
            fh.seek(toFileOffset: lastOffset)
            let newData = fh.readData(ofLength: Int(currentSize - lastOffset))
            fh.closeFile()
            fileOffsets[key] = currentSize

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

            guard allowedExtensions.contains(ext) else { continue }

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
    // takeUnretainedValue 安全： monitor 的生命周期由 AppState 持有
    let monitor = Unmanaged<ClaudeSessionMonitor>.fromOpaque(info).takeUnretainedValue()
    // handleFSEvent 展开后是同步扫描，已经在 watcher queue 上，直接调用
    monitor.handleFSEvent()
}
