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
        // 必须在 self 释放前停掉流并排空 queue 上已入队的 callback，
        // 否则 callback 执行时会访问已释放的 self。
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

    // internal（非 private）以便单测直接驱动扫描
    nonisolated func prescanExistingFiles(in dir: URL) {
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
                offsets[url.path] = Self.committedOffset(atPath: url.path, fileSize: UInt64(size))
            }
        }
        stateLock.withLock { _fileOffsets = offsets }
    }

    /// 预扫描同样只提交到最后一个完整换行处：文件尾部的半行（Claude 正在写入中）
    /// 不算"已有内容"。若直接把偏移记为文件大小，行补全后 scan 会从半行中间开始读，
    /// 只剩半截 JSON 解析失败，事件被永久丢失。
    /// 只读文件尾部一段来定位最后的换行，避免全量读取大 session 文件。
    private nonisolated static func committedOffset(atPath path: String, fileSize: UInt64) -> UInt64 {
        guard fileSize > 0, let fh = FileHandle(forReadingAtPath: path) else { return fileSize }
        defer { fh.closeFile() }
        let tailLength = min(fileSize, 256 * 1024)
        fh.seek(toFileOffset: fileSize - tailLength)
        let tail = fh.readData(ofLength: Int(tailLength))
        // 换行符是 ASCII 单字节，尾部起点即使落在多字节字符中间也不影响查找
        if let lastNewline = tail.lastIndex(of: 0x0A) {
            return fileSize - tailLength + UInt64(lastNewline + 1)
        }
        // 尾部整段都没有换行：视为一条尚未写完的半行，从头留待下轮重读
        return fileSize - tailLength
    }

    // MARK: - JSONL scan

    // internal（非 private）以便单测直接驱动扫描
    nonisolated func scanNewLines(in dir: URL) -> [ClaudeFileEvent] {
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

            let lastOffset = stateLock.withLock { _fileOffsets[key] ?? 0 }
            guard currentSize > lastOffset else {
                stateLock.withLock { _fileOffsets[key] = currentSize }
                continue
            }

            // 读取新增的字节
            guard let fh = FileHandle(forReadingAtPath: key) else { continue }
            fh.seek(toFileOffset: lastOffset)
            let newData = fh.readData(ofLength: Int(currentSize - lastOffset))
            fh.closeFile()

            // 只提交到最后一个完整换行处的偏移：JSONL 尾部半行（Claude 正在写入中）
            // 留到下轮重读，否则半行解析失败后会被永久跳过（丢事件）。
            // 换行符是 ASCII 单字节，前缀必落在合法 UTF-8 边界上。
            guard let lastNewline = newData.lastIndex(of: 0x0A) else { continue }
            let consumed = lastNewline + 1
            stateLock.withLock { _fileOffsets[key] = lastOffset + UInt64(consumed) }

            // 逐行解析 JSONL（只取已确认的完整行）
            let newText = String(data: newData.prefix(consumed), encoding: .utf8) ?? ""
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
