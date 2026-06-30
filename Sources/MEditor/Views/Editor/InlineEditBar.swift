import SwiftUI

/// Floating action strip shown at the editor's bottom when text is selected.
/// Tapping an action triggers AI processing and morphs the content area into
/// an inline split diff view — no sheet, no modal.
struct InlineEditBar: View {
    @Environment(AppState.self)    private var state
    @Environment(AppSettings.self) private var settings

    let selectedText: String

    @State private var isLoading:    Bool   = false
    @State private var loadingLabel: String = ""
    @State private var showAgentPanel = false
    @State private var agentRunner    = AgentRunner()

    private let agent = InlineEditAgent()

    /// Plugin skill commands from enabled manual skills
    private var pluginCommands: [(skill: PluginSkill, command: SkillCommand)] {
        state.pluginManager.skills
            .filter { $0.isEnabled && $0.source == .manual && !$0.commands.isEmpty }
            .flatMap { skill in skill.commands.map { (skill, $0) } }
    }

    var body: some View {
        HStack(spacing: 2) {
            if isLoading {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("AI \(loadingLabel)中…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button {
                        state.diffReview.dismiss()
                        isLoading    = false
                        loadingLabel = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            } else {
                // 快速内联操作（根据内容类型动态调整）
                ForEach(contextualActions) { action in
                    actionButton(action)
                }

                // Plugin command buttons (from enabled Skill.md with commands:)
                if !pluginCommands.isEmpty {
                    Divider()
                        .frame(height: 14)
                        .padding(.horizontal, 4)
                    ForEach(pluginCommands, id: \.command.id) { (skill, cmd) in
                        pluginCommandButton(skill: skill, command: cmd)
                    }
                }

                // 问 AI 分隔线 + 按钮
                Divider()
                    .frame(height: 14)
                    .padding(.horizontal, 4)

                askAIButton
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .overlay(alignment: .bottom) {
            if showAgentPanel {
                AgentResultPanel(runner: agentRunner) {
                    showAgentPanel = false
                }
                .environment(state)
                .frame(width: 480)
                .offset(y: -60)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showAgentPanel)
    }

    // MARK: - 内容感知动作列表

    /// 根据选中内容类型返回最相关的 AI 操作，最多 4 个。
    private var contextualActions: [InlineEditAction] {
        let t = selectedText.trimmingCharacters(in: .whitespaces)

        // 代码块：显示解释 + 注释 + 精简
        if t.hasPrefix("```") || t.hasPrefix("    ") {
            return [.explainCode, .addComments, .condense]
        }

        // 标题：显示扩写章节 + 改写
        if t.hasPrefix("#") {
            return [.expandSection, .rewrite]
        }

        // 列表：显示整理 + 扩写
        let lines = t.components(separatedBy: "\n").filter { !$0.isEmpty }
        let isListLike = lines.count >= 2 && lines.prefix(3).allSatisfy {
            $0.hasPrefix("- ") || $0.hasPrefix("* ") || $0.hasPrefix("+ ") ||
            $0.range(of: #"^\d+\. "#, options: .regularExpression) != nil
        }
        if isListLike {
            return [.organizeList, .expand, .condense]
        }

        // 默认：标准四个操作
        return [.rewrite, .expand, .condense, .translate]
    }

    // MARK: - Ask AI button

    /// 把选中文本带入 AI 面板，开启对话。
    private var askAIButton: some View {
        Button {
            guard !selectedText.isEmpty else { return }
            state.openAssistantWithSelection(selectedText)
        } label: {
            HStack(spacing: 4) {
                AIAssistantOrb(size: 12)
                Text(L("ai.askAI"))
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(AIBrand.blue)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(AIBrand.blue.opacity(0.09), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(L("ai.askAIHint"))
    }

    // MARK: - Action button

    private func actionButton(_ action: InlineEditAction) -> some View {
        Button { triggerAction(action) } label: {
            HStack(spacing: 4) {
                Image(systemName: action.icon)
                    .font(.system(size: 10, weight: .medium))
                Text(action.rawValue)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.05), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(action.rawValue)
    }

    // MARK: - Trigger

    // MARK: - Plugin command button

    private func pluginCommandButton(skill: PluginSkill, command: SkillCommand) -> some View {
        Button { triggerPluginCommand(skill: skill, command: command) } label: {
            HStack(spacing: 4) {
                Image(systemName: command.icon)
                    .font(.system(size: 10, weight: .medium))
                Text(command.trigger)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color.appAccent)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.appAccent.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(command.description.isEmpty ? command.trigger : command.description)
    }

    private func triggerPluginCommand(skill: PluginSkill, command: SkillCommand) {
        guard !selectedText.isEmpty else { return }
        guard let skillContent = try? String(contentsOf: skill.skillPath, encoding: .utf8) else { return }

        // Determine which tools are available
        let allTools: [any AgentTool] = BuiltinAgentTools.all
        let tools: [any AgentTool] = command.allowedTools.isEmpty
            ? allTools
            : allTools.filter { command.allowedTools.contains($0.spec.name) }

        let config  = AIConfig.current(settings, scene: .inline)   // plugin 命令也属于内联编辑场景
        let context = AgentContext.make(appState: state)
        // 将 Skill command 声明的 shell 白名单注入上下文，使 RunCommandTool 能够执行白名单检查
        context.setAllowedCommandPatterns(command.allowedCommands.isEmpty ? nil : command.allowedCommands)

        let userMsg = "Selected text:\n\n\(selectedText)\n\nFull document:\n\n\(state.selectedTab?.content ?? "")"

        agentRunner = AgentRunner()
        showAgentPanel = true

        agentRunner.run(
            systemPrompt: skillContent,
            userMessage: userMsg,
            tools: tools,
            config: config,
            context: context
        )
    }

    private func triggerAction(_ action: InlineEditAction) {
        guard !selectedText.isEmpty else { return }
        guard state.pluginManager.isBuiltinEnabled(BuiltinSkills.ID.inlineEditor) else {
            state.showToast(L("ai.error.notConfigured"), icon: "exclamationmark.triangle")
            return
        }

        isLoading    = true
        loadingLabel = action.rawValue

        // 保留选区位置
        let savedRange  = state.editorSelectedRange
        state.pendingReplaceRange = savedRange

        let fullContent = state.selectedTab?.content ?? selectedText

        func spliced(_ replacement: String) -> String {
            guard let swiftRange = Range(savedRange, in: fullContent) else {
                return fullContent.replacingOccurrences(of: selectedText, with: replacement, options: .literal)
            }
            return fullContent.replacingCharacters(in: swiftRange, with: replacement)
        }

        // 进入 diff 流式模式
        state.diffReview.beginStreaming(original: fullContent, actionLabel: action.rawValue)

        // 用 AgentRunner 执行（可访问 read_document / search_document 等工具）
        let config  = AIConfig.current(settings, scene: .inline)   // 内联编辑专用模型
        let context = AgentContext.make(appState: state)
        let tools   = BuiltinAgentTools.all

        // 系统 prompt = 内置 inlineEditor skill + 用户插件附加
        var systemPrompt = BuiltinSkills.inlineEditor.content
        let extra = state.pluginManager.userSkillsPrompt()
        if !extra.isEmpty { systemPrompt += "\n\n---\n\n# 附加技能\n\n" + extra }

        let userMsg = action.userInstruction(for: selectedText,
                                              document: state.selectedTab?.content)

        agentRunner = AgentRunner()

        // 监听流式 streaming chunks → diff preview
        agentRunner.onChunk = { [weak state] chunk in
            guard let state else { return }
            // 流式中间结果 — 拼接到 diff 预览
            let current = state.diffReview.streamedContent ?? fullContent
            // 仅当 chunk 是最终文本时替换（AgentRunner 目前一次性输出）
            state.diffReview.streamedContent = spliced(chunk)
        }

        agentRunner.onComplete = { [weak state, weak agentRunner] in
            guard let state else { return }
            let runner = agentRunner
            isLoading    = false
            loadingLabel = ""

            if let err = runner?.error {
                state.diffReview.dismiss()
                state.showToast(err, icon: "exclamationmark.triangle")
                return
            }

            let finalText = runner?.finalText ?? ""
            guard !finalText.isEmpty else {
                state.diffReview.dismiss()
                state.showToast("AI 未返回内容", icon: "exclamationmark.triangle")
                return
            }

            let modified = spliced(finalText)
            state.diffReview.commitStreamWithModified(modified) { merged in
                if let tab = state.selectedTab {
                    tab.content = merged
                    tab.contentRevision &+= 1
                    state.scheduleDebounceSave()
                }
            }
        }

        agentRunner.run(
            systemPrompt: systemPrompt,
            userMessage: userMsg,
            tools: tools,
            config: config,
            context: context
        )
    }
}
