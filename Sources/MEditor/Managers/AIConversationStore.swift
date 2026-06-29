import Foundation
import Observation

/// 一条等待用户在 agent step 流里确认执行的命令。
@MainActor
final class PendingCommand: Identifiable {
    let id = UUID()
    let command: String
    let cwd: String?
    private let respond: (Bool) -> Void
    private var answered = false

    init(command: String, cwd: String?, respond: @escaping (Bool) -> Void) {
        self.command = command
        self.cwd = cwd
        self.respond = respond
    }

    func approve() { guard !answered else { return }; answered = true; respond(true) }
    func reject()  { guard !answered else { return }; answered = true; respond(false) }
}

/// Persistent, multi-session conversation state for the AI assistant.
///
/// Owned by `AppState` and injected into the views (not a singleton), so it is
/// testable and consistent with the rest of the app's dependency wiring. Chats
/// survive the panel being recreated, and are persisted to disk (debounced,
/// off-main) so they survive app relaunches.
@MainActor
@Observable
final class AIConversation {

    private var sessions: [AISession] = []
    private(set) var activeID: UUID
    var input: String = ""
    var isResponding = false
    var showAllSuggestions = false

    /// Maximum messages per session. When exceeded, oldest messages are dropped
    /// (FIFO), but the first user message is always retained as seed context.
    static let maxMessagesPerSession = 100

    /// In-flight streaming task, so it can be cancelled (stop / new chat / switch).
    @ObservationIgnored var streamTask: Task<Void, Never>?
    /// Agent runner for tool-calling mode (助手面板接入 AgentRunner 时使用).
    @ObservationIgnored var agentRunner: AgentRunner?
    /// Debounced disk-persist work item.
    @ObservationIgnored private var persistWork: DispatchWorkItem?

    /// 待用户确认执行的命令（nil = 无）。AIAssistant 观察它显示确认条。
    var pendingCommand: PendingCommand? = nil
    /// 本次会话是否已授权执行命令（首次确认后置 true，之后不再逐条询问）。
    @ObservationIgnored var commandApprovedThisSession = false

    private static let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MEditor", isDirectory: true)
        return base.appendingPathComponent("ai-sessions.json")
    }()

    init() {
        // 先以空会话快速完成 init，避免主线程同步读磁盘。
        // 真实数据通过 loadFromDisk() 在 Task 中异步加载。
        let fresh = AISession()
        sessions  = [fresh]
        activeID  = fresh.id
        Task { await self.loadFromDisk() }
    }

    /// 从磁盘异步加载持久化会话。仅在 init 后首次调用。
    private func loadFromDisk() async {
        let url = Self.fileURL
        // 文件读取放到后台线程，避免阻塞 MainActor
        let result: [AISession]? = await Task.detached(priority: .utility) {
            guard let data  = try? Data(contentsOf: url),
                  let saved = try? JSONDecoder().decode([AISession].self, from: data),
                  !saved.isEmpty
            else { return nil }
            return saved
        }.value
        guard let saved = result else { return }
        // 回到 MainActor 更新状态
        sessions = saved
        activeID = saved[0].id
    }

    // MARK: Active session access

    private var activeIndex: Int { sessions.firstIndex { $0.id == activeID } ?? 0 }

    var messages: [AIChatMessage] {
        get { sessions.indices.contains(activeIndex) ? sessions[activeIndex].messages : [] }
        set {
            guard sessions.indices.contains(activeIndex) else { return }
            // Enforce per-session message cap: keep first user message + newest tail.
            let capped: [AIChatMessage]
            if newValue.count > Self.maxMessagesPerSession {
                let tail = Array(newValue.suffix(Self.maxMessagesPerSession - 1))
                if let seed = newValue.first(where: { $0.role == .user }),
                   tail.first?.id != seed.id {
                    capped = [seed] + tail
                } else {
                    capped = tail
                }
            } else {
                capped = newValue
            }
            sessions[activeIndex].messages = capped
            sessions[activeIndex].updatedAt = .now
            // Auto-title from first user message, stripping leading Markdown markers.
            if sessions[activeIndex].title.isEmpty,
               let firstUser = capped.first(where: { $0.role == .user }) {
                let cleaned = firstUser.text
                    .replacingOccurrences(of: #"^#{1,6}\s*"#, with: "",
                                         options: .regularExpression)
                sessions[activeIndex].title = String(cleaned.prefix(40))
            }
        }
    }

    // MARK: Context estimation

    /// Rough token estimate for the current conversation (chars ÷ 4).
    /// Used to surface a context-limit warning before the API rejects the request.
    var estimatedTokenCount: Int {
        messages.reduce(0) { $0 + $1.text.count / 4 }
    }

    /// True when estimated tokens exceed 80 % of a 128 K context window.
    var isApproachingContextLimit: Bool {
        estimatedTokenCount > 102_400   // 128 000 × 0.80
    }

    /// History ordered most-recently-updated first.
    var history: [AISession] {
        sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// O(1) in-place append to the last message — avoids copying the whole
    /// sessions array on every streamed token (was the O(n²) hot path).
    func appendToLastMessage(_ chunk: String) {
        let i = activeIndex
        guard sessions.indices.contains(i), !sessions[i].messages.isEmpty else { return }
        sessions[i].messages[sessions[i].messages.count - 1].text += chunk
        sessions[i].updatedAt = .now
    }

    // MARK: Lifecycle

    func cancelStreaming() {
        streamTask?.cancel()
        streamTask = nil
        agentRunner?.cancel()
        agentRunner = nil
        isResponding = false
        persist()
    }

    /// Start a fresh session. Reuses the current one if it's already empty.
    func newSession() {
        cancelStreaming()
        input = ""
        if sessions.indices.contains(activeIndex), sessions[activeIndex].messages.isEmpty {
            return
        }
        let fresh = AISession()
        sessions.insert(fresh, at: 0)
        activeID = fresh.id
        persist()
    }

    func activate(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        cancelStreaming()
        activeID = id
        input = ""
    }

    func delete(_ id: UUID) {
        if id == activeID { cancelStreaming() }
        sessions.removeAll { $0.id == id }
        if sessions.isEmpty {
            let fresh = AISession()
            sessions = [fresh]
            activeID = fresh.id
        } else if !sessions.contains(where: { $0.id == activeID }) {
            activeID = sessions[0].id
        }
        persist()
    }

    // MARK: Persistence

    func persist() {
        // Debounce: 只在真正要写盘时才拟快照 sessions，避免每次调用都复制整个数组。
        persistWork?.cancel()
        let url  = Self.fileURL
        let work = DispatchWorkItem { [weak self] in
            // 在工作项实际执行时打快照，这时已经在防抖窗口末尾，数据是最新的
            Task { @MainActor [weak self] in
                guard let self else { return }
                let snapshot = self.sessions
                let fileURL  = url
                DispatchQueue.global(qos: .utility).async {
                    guard let data = try? JSONEncoder().encode(snapshot) else { return }
                    try? FileManager.default.createDirectory(
                        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? data.write(to: fileURL, options: .atomic)
                }
            }
        }
        persistWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
