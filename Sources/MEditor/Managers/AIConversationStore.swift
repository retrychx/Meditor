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
    /// 各会话最近一次 Agent 运行的状态快照（Runner 完成后保留历史步骤展示用）。
    /// per-session 存储：切到历史会话只显示该会话自己的步骤面板；在途 run 收尾
    /// 按会话 id 写回（setLastRunState(_:sessionID:)），不污染当前活跃会话。
    /// 仅内存快照，不落盘（AgentRunState 非 Codable，AISession 持久化结构不变）。
    private var lastRunStates: [UUID: AgentRunState] = [:]
    /// 当前活跃会话的运行快照（读写代理到 lastRunStates[activeID]，UI 消费方无需改动）。
    var lastRunState: AgentRunState? {
        get { lastRunStates[activeID] }
        set { lastRunStates[activeID] = newValue }
    }
    /// Debounced disk-persist work item.
    @ObservationIgnored private var persistWork: DispatchWorkItem?

    /// 待用户确认执行的命令（nil = 无）。AIAssistant 观察它显示确认条。
    var pendingCommand: PendingCommand? = nil

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
        // 回到 MainActor 更新状态。
        // 加载期间用户可能已发出首条消息：内存已有用户内容时保留内存状态，
        // 磁盘会话并入列表（按 id 去重）；否则才整体采用磁盘数据。
        let hasUserContent = sessions.contains { !$0.messages.isEmpty || !$0.agentHistory.isEmpty }
        guard !hasUserContent else {
            let existingIDs = Set(sessions.map(\.id))
            sessions.append(contentsOf: saved.filter { !existingIDs.contains($0.id) })
            return
        }
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

    /// AgentMessage 完整历史（含工具调用上下文），读写当前会话
    var agentHistory: [AgentMessage] {
        get { sessions.indices.contains(activeIndex) ? sessions[activeIndex].agentHistory : [] }
        set {
            guard sessions.indices.contains(activeIndex) else { return }
            sessions[activeIndex].agentHistory = newValue
        }
    }

    // MARK: 指定会话的写入
    //
    // 在途 run 的回调（onChunk / onComplete）必须按发起时的会话 id 写回：
    // run 进行中用户可能已切换 / 新建会话，若走 messages / agentHistory 代理
    // （读写活跃会话）会把旧 run 的结果写进新会话。会话已被删除时静默丢弃。

    /// 更新指定会话中某条消息的文本（流式 chunk / 完成回填）。
    func updateMessageText(_ text: String, messageID: UUID, sessionID: UUID) {
        guard let si = sessions.firstIndex(where: { $0.id == sessionID }),
              let mi = sessions[si].messages.firstIndex(where: { $0.id == messageID }) else { return }
        sessions[si].messages[mi].text = text
        sessions[si].updatedAt = .now
    }

    /// 删除指定会话中的消息（无文本回复时清理空占位）。
    func removeMessage(_ messageID: UUID, sessionID: UUID) {
        guard let si = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[si].messages.removeAll { $0.id == messageID }
    }

    /// 写入指定会话的 agentHistory（含工具调用上下文）。
    func setAgentHistory(_ history: [AgentMessage], sessionID: UUID) {
        guard let si = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[si].agentHistory = history
    }

    /// 写入指定会话的运行快照（步骤面板历史）。
    func setLastRunState(_ runState: AgentRunState?, sessionID: UUID) {
        guard sessions.contains(where: { $0.id == sessionID }) else { return }
        lastRunStates[sessionID] = runState
    }

    // MARK: Context estimation

    /// Rough token estimate for the current conversation.
    /// 除 UI 消息文本外，还纳入 agentHistory（工具调用/结果的原始内容，单条可达 64KB）——
    /// 这才是真正发给模型的 agentMessages 的主要体积来源，否则触发时机会严重滞后于真实占用。
    /// Used to surface a context-limit warning before the API rejects the request.
    var estimatedTokenCount: Int {
        messages.reduce(0) { $0 + Self.estimateTokens($1.text) }
            + agentHistory.reduce(0) { $0 + Self.estimateTokens($1.content) }
    }

    /// 混合语言 token 估算：CJK/全角按 ~1.5 字符/token，拉丁/数字/符号按 ~4。
    /// （原为全部 ÷4——中文实测约 1–1.5 字符/token，中文会话的滑动截断几乎永不触发。）
    nonisolated static func estimateTokens(_ text: String) -> Int {
        var cjk = 0, other = 0
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x4E00...0x9FFF).contains(v)      // CJK 统一表意文字
                || (0x3400...0x4DBF).contains(v)  // 扩展 A
                || (0x3000...0x303F).contains(v)  // CJK 标点
                || (0xFF00...0xFFEF).contains(v)  // 全角字符
                || (0x20000...0x2A6DF).contains(v) { // 扩展 B
                cjk += 1
            } else {
                other += 1
            }
        }
        return cjk * 2 / 3 + other / 4
    }

    /// True when estimated tokens exceed 80 % of a 128 K context window.
    var isApproachingContextLimit: Bool {
        estimatedTokenCount > 102_400   // 128 000 × 0.80
    }

    /// 当对话历史超过 context limit 时，自动滑动窗口截断早期消息。
    /// 策略：保留第一条用户消息（初始上下文）+ 最近 N 轮对话（一对 = user + assistant 各一条）。
    /// agentHistory 同步从最老一端滑动裁剪（保持 tool_calls / tool result 配对完整），
    /// 避免长任务后工具上下文全丢导致模型重复已做过的操作。
    @discardableResult
    func truncateIfOverLimit(keepRecentPairs: Int = 10) -> Bool {
        guard isApproachingContextLimit else { return false }
        guard sessions.indices.contains(activeIndex) else { return false }

        var msgs = sessions[activeIndex].messages
        let totalPairs = keepRecentPairs * 2   // user + assistant 各一条

        if msgs.count > totalPairs + 1 {
            let first = msgs.first   // 保留最早的用户消息（初始上下文）
            let recent = Array(msgs.suffix(totalPairs))
            msgs = (first.map { [$0] } ?? []) + recent
            // 去重（首条和 recent 可能重叠）
            var seen = Set<UUID>()
            msgs = msgs.filter { seen.insert($0.id).inserted }
            sessions[activeIndex].messages = msgs
        }

        // 滑动裁剪 agentHistory（而不是整体清空）：从最老一端丢弃，但裁剪边界不能
        // 落在 assistant(toolCalls) 与其 tool results 之间，也不能让历史以半个工具轮次开头。
        let history = sessions[activeIndex].agentHistory
        if history.count > totalPairs {
            // system prompt（若有）固定在头部，不参与裁剪
            let head: [AgentMessage] = history.first?.role == .system ? [history[0]] : []
            var tail = Array(history.dropFirst(head.count))
            if tail.count > totalPairs {
                var start = tail.count - totalPairs
                // tool 结果必须跟在对应 assistant(toolCalls) 之后：起点落在 tool 消息上
                // 则继续后移，把它连同前面的 assistant(toolCalls) 一起整轮丢弃
                while start < tail.count, tail[start].role == .tool { start += 1 }
                tail = Array(tail[start...])
            }
            sessions[activeIndex].agentHistory = head + tail
        }
        persist()
        return true
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
        // dismiss 挂起的命令确认：reject() 会以 false 恢复工具内的 continuation，
        // 让卡在确认框的 Agent loop 能响应取消退出，确认条同时从 UI 消失。
        pendingCommand?.reject()
        pendingCommand = nil
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
        lastRunStates[id] = nil
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
                    do {
                        let data = try JSONEncoder().encode(snapshot)
                        try FileManager.default.createDirectory(
                            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try data.write(to: fileURL, options: .atomic)
                    } catch {
                        AppLog.session.error("AIConversation: persist failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }
        persistWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
