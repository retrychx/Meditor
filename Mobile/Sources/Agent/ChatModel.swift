import Foundation
import Observation

/// AI 对话面板的状态：消息列表 + AgentRunner 流式接入。
/// 骨架级：单会话、不落盘，多轮上下文通过 AgentRunner.finalMessages 保留。
@MainActor
@Observable
final class ChatModel {

    struct ChatMessage: Identifiable {
        enum Role { case user, assistant }
        let id = UUID()
        let role: Role
        var text: String
        /// 本次回复的工具步骤快照（运行中为空；运行中的实时步骤由 runner.steps 展示）。
        var steps: [AgentRunnerStep] = []
    }

    var messages: [ChatMessage] = []
    var input: String = ""
    var isResponding = false

    /// 运行中的 Runner（只读暴露给视图，驱动工具步骤面板）。
    private(set) var runner: AgentRunner?
    private var history: [AgentMessage] = []
    private let store: DocumentStore
    private let context: MobileAgentContext
    private let settings: MobileAISettings
    private let skillStore: MobileSkillStore
    /// Backend 工厂，透传给每次新建的 AgentRunner；测试时可注入 mock。
    private let backendFactory: @Sendable (AIConfig) -> any AgentBackend

    init(
        store: DocumentStore,
        settings: MobileAISettings,
        // 默认 nil → init 内取 .shared（默认参数表达式在非隔离上下文求值，
        // 直接写 = .shared 会在 Swift 6 模式报错）。
        skillStore: MobileSkillStore? = nil,
        backendFactory: @escaping @Sendable (AIConfig) -> any AgentBackend = AgentBackendFactory.make
    ) {
        self.store          = store
        self.context        = MobileAgentContext(store: store)
        self.settings       = settings
        self.skillStore     = skillStore ?? .shared
        self.backendFactory = backendFactory
    }

    private static let systemPrompt = """
        你是 MEditor 移动端的 AI 助手。用户当前打开了一个 Markdown/HTML 文档，\
        你可以使用工具读取和修改当前文档（read_document / patch_document / write_document），\
        也可以操作 App 沙盒工作区内的文件（list_files / read_file / write_file / search_workspace 等）。\
        回答使用与用户相同的语言，简洁直接。
        """

    /// 系统 prompt = 基础说明 + 已启用技能注入（每次发送时现取，开关即时生效）。
    private func systemPromptWithSkills() -> String {
        let section = skillStore.promptSection
        return section.isEmpty ? Self.systemPrompt : Self.systemPrompt + "\n\n" + section
    }

    /// 发送当前输入框内容。
    func send() {
        send(text: input.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// 发送指定内容（技能快捷指令 chip 用）。
    func sendQuick(_ text: String) {
        send(text: text)
    }

    private func send(text: String) {
        guard !text.isEmpty, !isResponding else { return }
        input = ""
        store.beginAIRun()

        // 对话过长时先做滑动窗口截断（对齐 macOS AIAssistant 的发送前行为）。
        if truncateIfOverLimit() {
            messages.append(ChatMessage(role: .assistant, text: "⚠️ 对话历史过长，已自动保留最近 10 轮对话。"))
        }

        messages.append(ChatMessage(role: .user, text: text))
        messages.append(ChatMessage(role: .assistant, text: ""))
        isResponding = true

        // history（= 上轮 runner.finalMessages）首条已含 system 消息。
        // 对齐 macOS AIAssistant 的策略：替换首条而非再前置一条——
        // 保证 system prompt 有且仅有一条，且始终是当前最新（技能开关即时生效）。
        var msgs = history
        let systemMessage = AgentMessage(role: .system, content: systemPromptWithSkills())
        if msgs.first?.role == .system {
            msgs[0] = systemMessage
        } else {
            msgs.insert(systemMessage, at: 0)
        }
        msgs.append(AgentMessage(role: .user, content: text))

        let r = AgentRunner(backendFactory: backendFactory)
        runner = r
        r.onChunk = { [weak self] fullText in
            self?.updateLastAssistant(fullText)
        }
        // 双 weak 捕获：避免 闭包 → runner → 闭包 的 retain cycle
        // （对齐 macOS AIAssistant.swift 的 onComplete 写法）。
        r.onComplete = { [weak self, weak r] in
            guard let self, let r else { return }
            self.finish(r)
        }
        r.run(
            messages: msgs,
            tools: BuiltinAgentTools.all,
            config: settings.makeConfig(),
            context: context
        )
    }

    func cancel() {
        runner?.cancel()
        runner = nil
        isResponding = false
    }

    /// 把 AI 回复插入当前文档末尾（消息操作）；无打开文档时返回 false。
    @discardableResult
    func insertIntoDocument(_ text: String) -> Bool {
        guard store.hasDocument else { return false }
        context.insertIntoDocument(text)
        return true
    }

    /// 撤销上一轮 AI 对文档的改动。
    func undoAIChanges() {
        store.undoAIChanges()
    }

    private func updateLastAssistant(_ text: String) {
        guard !messages.isEmpty else { return }
        messages[messages.count - 1].text = text
    }

    // MARK: - 上下文长度管理

    /// 上下文占用上限（token 估算 = 字符数 ÷ 4）：128K 窗口的 80%，与 macOS 一致。
    private static let contextTokenLimit = 102_400
    /// 截断后保留的最近对话轮数（一轮 = user + assistant 各一条），与 macOS 一致。
    private static let keepRecentPairs = 10

    /// 粗略 token 估算：UI 消息 + agent 历史（工具结果原始内容，单条可达 64KB）。
    private var estimatedTokenCount: Int {
        messages.reduce(0) { $0 + $1.text.count / 4 }
            + history.reduce(0) { $0 + $1.content.count / 4 }
    }

    /// 历史超过上下文上限时做滑动窗口截断，避免长会话被 API 400 拒绝。
    /// 策略与 macOS 对齐（同步来源：Sources/MEditor/Managers/AIConversationStore.swift
    /// 的 truncateIfOverLimit）：保留首条用户消息（初始上下文）+ system prompt
    /// + 最近 N 轮完整消息对；agent 历史从最老一端裁剪，裁剪边界不落在
    /// assistant(toolCalls) 与其 tool results 之间。
    @discardableResult
    private func truncateIfOverLimit() -> Bool {
        guard estimatedTokenCount > Self.contextTokenLimit else { return false }
        let totalPairs = Self.keepRecentPairs * 2

        if messages.count > totalPairs + 1 {
            let tail = Array(messages.suffix(totalPairs))
            // 保留最早的用户消息（初始上下文）；首条与 recent 不可能重叠
            // （count > totalPairs + 1 时 suffix 不含首条）
            if let seed = messages.first(where: { $0.role == .user }) {
                messages = [seed] + tail
            } else {
                messages = tail
            }
        }

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
            history = head + tail
        }
        return true
    }

    private func finish(_ r: AgentRunner) {
        history = r.finalMessages
        // 工具步骤快照进消息（滤掉 thinking 占位），run 结束后仍可回放。
        if !messages.isEmpty {
            messages[messages.count - 1].steps = r.steps.filter { step in
                if case .thinking = step { return false }
                return true
            }
        }
        if let error = r.error, messages.last?.text.isEmpty == true {
            updateLastAssistant("[!] \(error)")
        } else if let error = r.error {
            updateLastAssistant((messages.last?.text ?? "") + "\n\n[!] \(error)")
        }
        runner = nil
        isResponding = false
    }
}
