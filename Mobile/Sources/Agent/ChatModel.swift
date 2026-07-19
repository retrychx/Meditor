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
        /// 本次回复的工具步骤快照（运行中为空，由 liveSteps 展示）。
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

    init(store: DocumentStore, settings: MobileAISettings) {
        self.store    = store
        self.context  = MobileAgentContext(store: store)
        self.settings = settings
    }

    private static let systemPrompt = """
        你是 MEditor 移动端的 AI 助手。用户当前打开了一个 Markdown/HTML 文档，\
        你可以使用工具读取和修改当前文档（read_document / patch_document / write_document），\
        也可以操作 App 沙盒工作区内的文件（list_files / read_file / write_file / search_workspace 等）。\
        回答使用与用户相同的语言，简洁直接。
        """

    /// 系统 prompt = 基础说明 + 已启用技能注入（每次发送时现取，开关即时生效）。
    private func systemPromptWithSkills() -> String {
        let section = MobileSkillStore.shared.promptSection
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

        messages.append(ChatMessage(role: .user, text: text))
        messages.append(ChatMessage(role: .assistant, text: ""))
        isResponding = true

        var msgs = [AgentMessage(role: .system, content: systemPromptWithSkills())]
        msgs.append(contentsOf: history)
        msgs.append(AgentMessage(role: .user, content: text))

        let r = AgentRunner()
        runner = r
        r.onChunk = { [weak self] fullText in
            self?.updateLastAssistant(fullText)
        }
        r.onComplete = { [weak self] in
            self?.finish(r)
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
