import SwiftUI

// MARK: - Chat / input panel

/// 浮现于编辑器上方的 AI 助手面板。
/// 支持多 provider：OpenAI 兼容接口（远程）或本地 Claude CLI（复用登录态）。
/// 通过 AppSettings 配置 provider；未配置时显示引导界面。
@MainActor
struct AIAssistantPanel: View {
    @Environment(AppState.self) var state
    let onClose: () -> Void

    @Environment(AppSettings.self) private var settings
    @State private var showHistory = false
    @State var atBottom = true
    @State var streamScrollWork: DispatchWorkItem?   // 流式滚动 debounce
    @State var mentionTokens: [AtMentionToken] = []
    @State var showMentionPicker = false
    @State var mentionQuery: String = ""
    @FocusState var inputFocused: Bool

    /// 首次使用引导：显示 @mention 能力提示。
    @AppStorage("ai.hasSeenMentionHint") var hasSeenMentionHint = false
    /// 首次打开时显示 @mention 能力卡片。
    @State var showMentionTip = false

    var theme: PreviewTheme { state.themeStore.current }
    var accent: AIAccentStyle { AIAccentStyle.current(settings) }
    var convo: AIConversation { state.aiConversation }
    /// 业务协调器（无状态，随取随建）：承载 runCompletion 等已下沉的业务逻辑。
    private var coordinator: AIChatCoordinator {
        AIChatCoordinator(settings: settings, conversation: convo, appState: state)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            // @mention picker：作为独立布局元素显示在输入框正上方，绝不遮挡
            if showMentionPicker {
                mentionPickerPopoverContent
                    .padding(.horizontal, 24)
                    .padding(.bottom, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.97, anchor: .bottom).combined(with: .opacity),
                        removal:   .scale(scale: 0.97, anchor: .bottom).combined(with: .opacity)
                    ))
            }
            composerFooter
        }
        .background(theme.editorBackground)
        .animation(DS.Motion.springFast, value: showMentionPicker)
        .onAppear {
            DispatchQueue.main.async {
                // 如果是内联选中文本触发，预填输入框并清除待消费标记
                if let pending = state.aiUI.pendingSelectionPrompt {
                    convo.input = pending
                    state.aiUI.pendingSelectionPrompt = nil
                }
                inputFocused = true

                // 首次打开：延迟显示 @mention 能力提示卡片
                if !hasSeenMentionHint && convo.messages.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        withAnimation(DS.Motion.spring) { showMentionTip = true }
                    }
                }
            }
        }
        // 面板已打开时再次「问 AI」：onAppear 不会重触发，这里负责把选区带入输入框
        .onChange(of: state.aiUI.pendingSelectionPrompt) { _, pending in
            guard let pending, !pending.isEmpty else { return }
            if convo.input.isEmpty {
                convo.input = pending
            } else {
                convo.input += "\n\n" + pending
            }
            state.aiUI.pendingSelectionPrompt = nil
            inputFocused = true
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                AIHeaderButton(icon: "clock.arrow.circlepath", help: L("ai.history"), theme: theme) {
                    showHistory.toggle()
                }
                .popover(isPresented: $showHistory, arrowEdge: .bottom) {
                    AIHistoryView(convo: convo, theme: theme) { showHistory = false }
                }
                Spacer()
                Button(action: newChat) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.bubble")
                            .font(.system(size: 11, weight: .semibold))
                        Text(L("ai.newChat"))
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundStyle(theme.craftPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule(style: .continuous).fill(theme.craftHover))
                    .overlay(Capsule().strokeBorder(theme.separator.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help(L("ai.newChat"))
                Spacer()
                AIHeaderButton(icon: "xmark", help: L("common.close"), theme: theme, action: onClose)
            }
            .padding(.horizontal, 12)
            .frame(height: 52)

            // Context-limit warning banner — shown when the conversation is near
            // the model's context window so the user can start a new chat in time.
            if convo.isApproachingContextLimit {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                    Text("Context nearly full — start a new chat to avoid truncation.")
                        .font(.system(size: 11))
                }
                .foregroundStyle(Color(hex: "92400E"))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "FEF3C7"))
                .transition(.opacity)
            }
        }
        .background(
            theme.editorBackground
                .overlay(alignment: .bottom) { theme.separator.opacity(0.4).frame(height: 1) }
        )
    }

    // MARK: Body

    @ViewBuilder
    private var content: some View {
        if convo.messages.isEmpty {
            suggestionsView
        } else {
            transcriptView
        }
    }

    // MARK: Logic

    private func newChat() {
        withAnimation(DS.Motion.fast) {
            convo.newSession()
            convo.showAllSuggestions = false
        }
        mentionTokens = []
        inputFocused = true
    }

    func send() {
        let trimmed = convo.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !convo.isResponding else { return }

        // 若带有「引用选段」，作为 markdown 引用拼到提问前，给 AI 完整上下文
        let messageText: String
        if let quoted = state.aiUI.quotedContext, !quoted.isEmpty {
            let quotedBlock = quoted
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { "> \($0)" }
                .joined(separator: "\n")
            messageText = quotedBlock + "\n\n" + trimmed
        } else {
            messageText = trimmed
        }

        withAnimation(DS.Motion.standard) {
            convo.messages.append(AIChatMessage(role: .user, text: messageText))
            convo.input = ""
        }
        state.aiUI.quotedContext = nil
        // 保存当次 @tokens，供 runCompletion 注入上下文，然后清空
        let tokensSnapshot = mentionTokens
        mentionTokens = []
        convo.persist()
        coordinator.runCompletion(mentionTokens: tokensSnapshot)
    }

    /// Drop the last assistant reply (if any) and re-run the request.
    func regenerate() {
        guard !convo.isResponding else { return }
        if convo.messages.last?.role == .assistant {
            convo.messages.removeLast()
        }
        coordinator.runCompletion()
    }
}

// MARK: - Header button

private struct AIHeaderButton: View {
    let icon: String
    let help: String
    let theme: PreviewTheme
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.craftSecondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(hovered ? theme.craftHover : Color.clear))
                .overlay(Circle().strokeBorder(theme.separator.opacity(0.6), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
        .animation(DS.Motion.micro, value: hovered)
    }
}
