import SwiftUI

/// Floating action strip shown at the editor's bottom when text is selected.
/// Tapping an action triggers AI processing and morphs the content area into
/// an inline split diff view — no sheet, no modal.
@MainActor
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
                    Text(L("ai.inline.working", loadingLabel))
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
                Text(action.displayName)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.05), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(action.displayName)
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

        // 全文上下文 8K 门控（与聊天面板 systemContext 的 8000 字符策略一致），
        // 大文档不再整篇内联进 prompt（成本审计 8.2 #2）
        let fullDoc = state.selectedTab?.content ?? ""
        let docContext = fullDoc.count > 8000
            ? String(fullDoc.prefix(8000)) + "\n…（文档过长已截断，可用 read_document 的 start_line/end_line 按需读取）"
            : fullDoc
        let userMsg = "Selected text:\n\n\(selectedText)\n\nFull document:\n\n\(docContext)"

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
        loadingLabel = action.displayName

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
        state.diffReview.beginStreaming(original: fullContent, actionLabel: action.displayName)
        // 快照过期防护：AI 运行期间用户可能继续编辑——写回时以当前文档为起点
        // 重定位合并；目标段落已被改动则拒绝覆盖并提示，由用户放弃本次结果
        state.diffReview.currentContentProvider = { [weak state] in state?.selectedTab?.content }
        state.diffReview.onRebaseConflict = { [weak state] in
            state?.showToast(L("ai.inline.targetLost"),
                             icon: "exclamationmark.triangle")
        }
        // 捕获 generation token：dismiss / 新一轮流式后在途回调写入被丢弃
        let streamGen = state.diffReview.streamGeneration

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
        // 注册到 diffReview（与预览流一致）：dismiss（取消按钮 / 关闭 diff 视图）才能
        // 取消到这次运行；且 bar 销毁后 runner 由 diffReview 强持有，run 不会在途中被释放
        state.diffReview.activeRunner = agentRunner

        // 监听流式 streaming chunks → diff preview
        agentRunner.onChunk = { [weak state] chunk in
            guard let state else { return }
            // 仅当 chunk 是最终文本时替换（AgentRunner 目前一次性输出）；
            // generation 校验：dismiss 后迟到的 chunk 不得写回
            state.diffReview.writeStreamedContent(spliced(chunk), generation: streamGen)
        }

        agentRunner.onComplete = { [weak state, weak agentRunner] in
            guard let state else { return }
            let runner = agentRunner
            // 只在自己的 runner 仍注册时释放引用（避免清掉后一轮运行的注册）
            if let runner, state.diffReview.activeRunner === runner {
                state.diffReview.activeRunner = nil
            }
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
                state.showToast(L("ai.inline.emptyResponse"), icon: "exclamationmark.triangle")
                return
            }

            let modified = spliced(finalText)
            state.diffReview.commitStreamWithModified(modified, generation: streamGen) { merged in
                if let tab = state.selectedTab {
                    // 走 updateTabContent：同步预览 + 标 isModified（否则防抖保存会漏掉）
                    state.updateTabContent(tab.id, content: merged)
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
