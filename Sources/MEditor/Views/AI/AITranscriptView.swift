import SwiftUI

/// Reports the transcript's bottom-marker offset within the scroll viewport,
/// used to decide whether to auto-follow streaming output.
private struct AIBottomOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Transcript（消息流 + agent 步骤 + 滚动跟随）

extension AIAssistantPanel {
    var transcriptView: some View {
        GeometryReader { outer in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // 历史消息（响应中排除最后一条 reply 占位，交由下方单独渲染，
                        // 使 steps 能放在 reply 之上且能随 runner.steps 更新）
                        ForEach(displayMessages) { message in
                            if !message.text.isEmpty {
                                bubble(message).id(message.id)
                            }
                        }

                    if convo.isResponding {
                        // 当前轮 Agent steps —— 放在 reply 之上（过程在上、结论在下，减少抖动）
                        if let runner = convo.agentRunner, !runner.steps.isEmpty {
                            agentStepsPanel(runner)
                        }
                    } else if let lastState = convo.lastRunState, !lastState.steps.isEmpty {
                        // 完成后：展示历史步骤（Runner 已 nil，但 state 保留）
                        agentStepsPanelFromState(lastState)
                    }
                    if convo.isResponding {
                        // 当前轮 reply（在 steps 之下流式增长）
                        if let last = convo.messages.last,
                           last.role == .assistant, !last.text.isEmpty {
                            bubble(last).id(last.id)
                        }
                        // 进行态提示
                        let streaming = !(convo.messages.last?.text.isEmpty ?? true)
                        let hasSteps  = !(convo.agentRunner?.steps.isEmpty ?? true)
                        if streaming {
                            StreamingCursorView()
                        } else if !hasSteps {
                            HStack(spacing: 8) {
                                AIAssistantOrb(size: 18, glow: true)
                                Text(L("ai.thinking"))
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(theme.craftSecondary)
                                TypingDots(color: theme.craftSecondary)
                            }
                        }
                        // 有 steps 但还没最终文本：steps 内的 thinking 步骤已表示进行中
                    }
                    if let pending = convo.pendingCommand {
                        commandConfirmBar(pending)
                    }
                    if !convo.isResponding && convo.messages.last?.role == .assistant {
                        Button(action: regenerate) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10.5, weight: .semibold))
                                Text(L("ai.regenerate"))
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .foregroundStyle(theme.craftSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .overlay(
                                Capsule().strokeBorder(theme.separator.opacity(0.6), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                    // Bottom anchor — ensures the last line fully clears the
                    // composer and that scroll-to-end reaches the true bottom.
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                        .background(
                            GeometryReader { g in
                                Color.clear.preference(
                                    key: AIBottomOffsetKey.self,
                                    value: g.frame(in: .named("aiScroll")).maxY
                                )
                            }
                        )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 10)
            }
            .coordinateSpace(name: "aiScroll")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onPreferenceChange(AIBottomOffsetKey.self) { maxY in
                // The bottom marker sits within ~1 viewport when the user is at
                // the end; only then do we follow streaming output.
                atBottom = maxY <= outer.size.height + 40
            }
            .onChange(of: convo.messages.count) { _, _ in
                // A new message (send/reply start) always jumps to the bottom.
                scrollToEnd(proxy)
            }
            .onChange(of: convo.messages.last?.text) { _, _ in
                // 流式输出每个 token 都触发：debounce 合并（60ms），避免逐字滚动导致抖动
                guard atBottom else { return }
                streamScrollWork?.cancel()
                let work = DispatchWorkItem { scrollToEnd(proxy) }
                streamScrollWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
            }
            .onChange(of: convo.agentRunner?.steps.count) { _, _ in
                // 新增 step 时无条件滚动（不检查 atBottom）：
                // 因为 onPreferenceChange 会在 onChange 之前触发，将 atBottom 设为
                // false（底部锚点已超出视口），导致 if atBottom 检查失效。
                // 使用 async 让布局先 settle，再执行滚动。
                DispatchQueue.main.async { scrollToEnd(proxy) }
            }
            .onChange(of: convo.pendingCommand?.id) { _, newID in
                // 待确认命令出现时滚到底，避免长命令把"执行/拒绝"按钮推到视口外
                if newID != nil { DispatchQueue.main.async { scrollToEnd(proxy) } }
            }
            .onAppear {
                DispatchQueue.main.async { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            }
        }
    }

    /// 响应中排除最后一条 reply 占位（交由 transcript 单独渲染，使 steps 能置于其上）。
    private var displayMessages: [AIChatMessage] {
        if convo.isResponding, convo.messages.last?.role == .assistant {
            return Array(convo.messages.dropLast())
        }
        return convo.messages
    }

    /// 当前轮的 Agent 工具步骤面板（紧凑单行，渲染在流式 reply 之上）。
    @ViewBuilder
    private func agentStepsPanel(_ runner: AgentRunner) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(runner.steps) { step in
                AgentStepView(step: step, compact: true)
                    .environment(state)
                    .transition(.opacity)
            }
            .animation(DS.Motion.spring, value: runner.steps.count)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.editorBackground.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.separator.opacity(0.25), lineWidth: 0.5)
        )
    }

    /// 历史步骤面板（Runner 完成后，从 AgentRunState 渲染已结束步骤）
    @ViewBuilder
    private func agentStepsPanelFromState(_ runState: AgentRunState) -> some View {
        let donesteps = runState.steps.filter { if case .thinking = $0 { return false }; return true }
        if !donesteps.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(donesteps) { step in
                    AgentStepView(step: step, compact: true)
                        .environment(state)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.editorBackground.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme.separator.opacity(0.25), lineWidth: 0.5)
            )
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(DS.Motion.standard) { proxy.scrollTo("bottom", anchor: .bottom) }
    }
}

// MARK: - Typing indicator

private struct TypingDots: View {
    let color: Color
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                    .offset(y: animating ? -3 : 0)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

// MARK: - StreamingCursorView

/// 流式输出期间显示的闪烁光标，告知用户 AI 正在写内容。
private struct StreamingCursorView: View {
    @State private var visible = true

    var body: some View {
        Text("◍")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .opacity(visible ? 0.8 : 0.1)
            .padding(.leading, 2)
            .padding(.vertical, 2)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}
