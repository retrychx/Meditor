import Foundation

/// AI 助手面板业务协调器。
///
/// 承载原本写在 `AIAssistantPanel`（SwiftUI View）私有方法里的纯业务逻辑：
/// 请求编排（`runCompletion`）、AgentRunner 启动（`launchAgentRunner`）、
/// system prompt 构建（`systemContext`）。纯搬运、不改行为（prompt 文本逐字保留、
/// 调用时序保留），View 侧只保留绑定与回调。依赖经 init 注入，便于测试。
@MainActor
final class AIChatCoordinator {
    private let settings: AppSettings
    private let convo: AIConversation
    private let state: AppState

    init(settings: AppSettings, conversation: AIConversation, appState: AppState) {
        self.settings = settings
        self.convo = conversation
        self.state = appState
    }

    /// 助手面板走 AgentRunner（带工具调用能力），兼容流式文本回退。
    func runCompletion(mentionTokens: [AtMentionToken] = []) {
        guard convo.messages.last?.role == .user else { return }
        convo.isResponding = true

        let config  = AIConfig.current(settings, scene: .agent)
        let context = AgentContext.make(appState: state)
        let tools   = BuiltinAgentTools.all

        // @mention 所需的主线程上下文快照（不能在 Task.detached 里访问 MainActor 属性）
        let docName    = state.selectedTab?.name
        let docContent = state.selectedTab?.content
        let wsRoot     = state.rootURL
        let wsFiles    = Array(state.fileItemMap.values)

        let userTurnCount = convo.messages.filter { $0.role == .user }.count
        let baseSys = systemContext(includeFullDoc: userTurnCount == 1)

        Task {
            // @mention IO 在后台执行
            let mentionCtx = await AtMentionContextBuilder.build(
                tokens: mentionTokens,
                currentDocName: docName,
                currentDocContent: docContent,
                workspaceRoot: wsRoot,
                workspaceFiles: wsFiles
            )
            var sysContent = baseSys
            if !mentionCtx.isEmpty { sysContent += mentionCtx }
            await MainActor.run {
                launchAgentRunner(sysContent: sysContent, config: config, context: context, tools: tools)
            }
        }
    }

    private func launchAgentRunner(
        sysContent: String,
        config: AIConfig,
        context: AgentContext,
        tools: [any AgentTool]
    ) {
        // 对话过长时自动截断，保留最近 10 轮对话。agentHistory 同步从最老一端滑动裁剪
        // （保持 tool_calls / tool result 配对完整），而非整体清空。
        if convo.truncateIfOverLimit(keepRecentPairs: 10) {
            // 截断发生：插入一条系统提示（不影响正常流程）
            let notice = AIChatMessage(role: .assistant, text: "⚠️ 对话历史过长，已自动保留最近 10 轮对话。")
            convo.messages.insert(notice, at: max(0, convo.messages.count - 1))
        }

        // 构建 AgentMessage 列表：优先使用已保存的 agentHistory（保留工具调用上下文）
        var agentMessages: [AgentMessage]
        let savedHistory = convo.agentHistory
        if !savedHistory.isEmpty, let newUserMsg = convo.messages.last, newUserMsg.role == .user {
            // 用历史记录（含工具调用）+ 新的用户消息，更新 system prompt
            agentMessages = savedHistory
            if agentMessages.first?.role == .system {
                agentMessages[0] = AgentMessage(role: .system, content: sysContent)
            } else {
                agentMessages.insert(AgentMessage(role: .system, content: sysContent), at: 0)
            }
            agentMessages.append(AgentMessage(role: .user, content: newUserMsg.text))
        } else {
            // 回退：从 AIChatMessage 重建（丢失工具调用上下文，适用于首轮或旧会话）
            agentMessages = [AgentMessage(role: .system, content: sysContent)]
            agentMessages += convo.messages.map {
                AgentMessage(role: $0.role == .user ? .user : .assistant, content: $0.text)
            }
        }

        // 在消息列表末尾加一个空 assistant 占位，用于流式显示
        let replyMessage = AIChatMessage(role: .assistant, text: "")
        let replyID      = replyMessage.id
        convo.messages.append(replyMessage)

        // 启动 AgentRunner（maxSteps 走注入的 settings，与上方 AIConfig.current(settings, ...) 一致）
        let runner = AgentRunner(maxSteps: settings.aiAgentMaxSteps)
        convo.agentRunner = runner

        // 流式 chunk 回调 → 更新占位 bubble
        runner.onChunk = { [weak convo] chunk in
            guard let convo else { return }
            if let idx = convo.messages.firstIndex(where: { $0.id == replyID }) {
                convo.messages[idx].text = chunk
            }
        }

        // 完成回调
        runner.onComplete = { [weak convo, weak runner] in
            guard let convo else { return }
            let finalText = runner?.finalText ?? ""
            let errText   = runner?.error

            if let err = errText, !err.isEmpty {
                if let idx = convo.messages.firstIndex(where: { $0.id == replyID }) {
                    convo.messages[idx].text = "错误：\(err)"
                }
            } else if !finalText.isEmpty {
                if let idx = convo.messages.firstIndex(where: { $0.id == replyID }) {
                    convo.messages[idx].text = finalText
                    // 输出达到 max_tokens 上限被截断时，在答案下方追加一行提示
                    if runner?.state.wasTruncated == true {
                        convo.messages[idx].text += "\n\n⚠️ 输出达到长度上限，内容可能被截断。"
                    }
                }
            } else {
                // Agent 做了工具调用但没有最终文本
                let errorSteps = runner?.steps.filter(\.isError) ?? []
                if !errorSteps.isEmpty {
                    // 有失败的工具步骤 → 生成错误摘要，不要静默消失
                    let lines = errorSteps.compactMap { step -> String? in
                        if case .toolCallDone(_, let name, _, let result, true) = step {
                            let short = result.prefix(120)
                            return "• \(name)：\(short)"
                        }
                        return nil
                    }
                    let summary = "⚠️ 部分操作未能完成：\n" + lines.joined(separator: "\n")
                    if let idx = convo.messages.firstIndex(where: { $0.id == replyID }) {
                        convo.messages[idx].text = summary
                    }
                } else {
                    // 工具全部成功，结果已体现在文档里，删掉空占位
                    convo.messages.removeAll { $0.id == replyID }
                }
            }

            // 保存完整的 agent 消息历史（含工具调用），下次对话时直接使用
            if let fm = runner?.finalMessages, !fm.isEmpty {
                convo.agentHistory = fm
            }

            // 保存本次运行状态快照（历史步骤持久化，Runner 置 nil 后仍可展示）
            convo.lastRunState = runner?.state

            convo.isResponding = false
            convo.agentRunner  = nil
            convo.persist()
        }

        runner.run(messages: agentMessages, tools: tools, config: config, context: context)
    }

    /// System prompt grounding the assistant in the current document.
    ///
    /// - Parameter includeFullDoc: When `true` (first user turn), injects the
    ///   full document body (up to 8 000 chars). On subsequent turns the model
    ///   already has the document in its conversation history, so we only remind
    ///   it of the document name to avoid re-paying the token cost every round.
    ///   Selected text is always included because it's user-initiated and small.
    private func systemContext(includeFullDoc: Bool = true) -> String {
        var ctx = """
You are a helpful writing assistant embedded in a native macOS Markdown editor.
Rules:
- Always format code in fenced code blocks with the correct language tag.
- Use proper Markdown syntax (## headings, **bold**, _italic_, `inline code`).
- When the user asks to insert or rewrite content, output clean Markdown without any preamble like "Here is..." or "Sure!".
- Keep responses focused and concise; avoid repeating the user's request back to them.
- You have FULL permission to use all provided tools (create_directory, create_file, write_file, etc.) to perform file system operations. These tools are sandboxed to the user's own machine and are safe to use. NEVER refuse a file operation request — always call the appropriate tool directly.
- To read a file's content you MUST call read_file (or read_document for the active tab). The editor loads file content asynchronously, so opening a file does NOT make its content visible to you — never claim you can "see" a file you only opened. If you need the content, call read_file and use its returned text.
- The document tools (read_document, write_document, patch_document, search_document) accept an OPTIONAL 'filename' argument. Omit it to act on the currently active editor tab; pass it (filename / workspace-relative path / absolute path) to act on that specific file directly. You do NOT need to open_file first just to read, rewrite, or patch a specific file — pass its 'filename' to the document tool instead.
"""
        // 注入工作区路径，帮助 AI 正确使用文件/目录工具
        if let rootURL = state.rootURL {
            ctx += "\n\nThe current workspace root is: \(rootURL.path)"
            ctx += "\n- File and directory tools (create_file, write_file, create_directory, etc.) accept EITHER a path relative to the workspace root (e.g. \"docs/api\") OR an absolute path (e.g. \"\(rootURL.path)/docs/api\"). Both forms work."
            ctx += "\n- When the user provides an absolute path, use it directly with the appropriate tool — do NOT refuse or ask the user to run a terminal command."
        }
        // 注入 HTML 主题元信息（简短，不含完整 CSS）
        let themeName = state.themeStore.current.rawValue
        ctx += "\n\n## 创建 / 改版 HTML 文件"
        ctx += "\nWhen the user asks to create a NEW HTML file, or to restyle/redesign an existing one, you MUST FIRST call the get_html_template tool to fetch MEditor's built-in HTML template, and use it as the base."
        ctx += "\n- get_html_template styles: 'doc' (default — MEditor's standard styled document), 'craft' (modern cards), 'tufte' (serif academic), 'dark' (dark code style). If the user doesn't specify, use 'doc'."
        ctx += "\n- Keep the template's <style> block and overall structure; just fill in / replace the body content. Do NOT invent your own CSS from scratch, and do NOT strip the template's styles into a bare semantic-HTML page unless the user explicitly asks for that."
        ctx += "\n- Keep all CSS inlined in a <style> block; never reference external .css files."
        ctx += "\n(Note: \(themeName) is the current PREVIEW theme — that's separate from these file templates.)"
        let selection = state.editorSelectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selection.isEmpty {
            // Selected text is cheap and always relevant — include regardless of turn.
            let sel = selection.count > 4000 ? String(selection.prefix(4000)) + "…" : selection
            let name = state.selectedTab?.name ?? "document"
            ctx += "\n\nThe user selected this text in \"\(name)\":\n\n\(sel)"
        } else if includeFullDoc, let tab = state.selectedTab {
            let body = tab.content.count > 8000 ? String(tab.content.prefix(8000)) + "…" : tab.content
            ctx += "\n\nThe current document is \"\(tab.name)\":\n\n\(body)"
        } else if let tab = state.selectedTab {
            // Subsequent turns: just name — full content is already in conversation history.
            ctx += "\n\nThe user is editing a document named \"\(tab.name)\"."
        }
        let userSkills = state.pluginManager.userSkillsPrompt()
        if !userSkills.isEmpty {
            ctx += "\n\n---\n\n# 用户自定义技能\n\n" + userSkills
        }
        return ctx
    }
}
