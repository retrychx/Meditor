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
    }

    var messages: [ChatMessage] = []
    var input: String = ""
    var isResponding = false

    private var runner: AgentRunner?
    private var history: [AgentMessage] = []
    private let context: MobileAgentContext
    private let settings: MobileAISettings

    init(store: DocumentStore, settings: MobileAISettings) {
        self.context  = MobileAgentContext(store: store)
        self.settings = settings
    }

    private static let systemPrompt = """
        你是 MEditor 移动端的 AI 助手。用户当前打开了一个 Markdown/HTML 文档，\
        你可以使用工具读取和修改当前文档（read_document / patch_document / write_document），\
        也可以操作 App 沙盒工作区内的文件（list_files / read_file / write_file / search_workspace 等）。\
        回答使用与用户相同的语言，简洁直接。
        """

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }
        input = ""

        messages.append(ChatMessage(role: .user, text: text))
        messages.append(ChatMessage(role: .assistant, text: ""))
        isResponding = true

        var msgs = [AgentMessage(role: .system, content: Self.systemPrompt)]
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

    private func updateLastAssistant(_ text: String) {
        guard !messages.isEmpty else { return }
        messages[messages.count - 1].text = text
    }

    private func finish(_ r: AgentRunner) {
        history = r.finalMessages
        if let error = r.error, messages.last?.text.isEmpty == true {
            updateLastAssistant("[!] \(error)")
        } else if let error = r.error {
            updateLastAssistant((messages.last?.text ?? "") + "\n\n[!] \(error)")
        }
        runner = nil
        isResponding = false
    }
}
