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
                ForEach(InlineEditAction.allCases) { action in
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

        let config = AIConfig.current(settings)
        let context = AgentContext(appState: state)

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

        isLoading    = true
        loadingLabel = action.rawValue

        // Save editor selection range before focus is lost
        let savedRange = state.editorSelectedRange
        state.pendingReplaceRange = savedRange

        // Full document as context for diff review
        let fullContent = state.selectedTab?.content ?? selectedText

        // Helper: splice `replacement` into `fullContent` at `savedRange`
        func spliced(_ replacement: String) -> String {
            guard let swiftRange = Range(savedRange, in: fullContent) else {
                // Fallback: string search
                return fullContent.replacingOccurrences(of: selectedText, with: replacement, options: .literal)
            }
            return fullContent.replacingCharacters(in: swiftRange, with: replacement)
        }

        // Enter diff mode immediately
        state.diffReview.beginStreaming(original: fullContent, actionLabel: action.rawValue)

        var accumulated = ""
        let task = agent.process(
            text: selectedText,
            action: action,
            settings: settings,
            pluginManager: state.pluginManager,
            onChunk: { chunk in
                accumulated += chunk
                state.diffReview.streamedContent = spliced(accumulated)
            },
            onComplete: { _, error in
                isLoading    = false
                loadingLabel = ""

                if let error {
                    state.diffReview.dismiss()
                    state.showToast(error.localizedDescription, icon: "exclamationmark.triangle")
                    return
                }

                let modified = spliced(accumulated)
                state.diffReview.commitStreamWithModified(modified) { merged in
                    if let tab = state.selectedTab {
                        tab.content = merged
                        tab.contentRevision &+= 1   // 通知编辑器刷新视图
                        state.scheduleDebounceSave()
                    }
                }
            }
        )
        state.diffReview.activeStreamTask = task
    }
}
