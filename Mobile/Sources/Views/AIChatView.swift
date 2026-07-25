import SwiftUI

/// AI 对话面板：消息列表 + 输入框，接共享的 AgentRunner 流式回复。
/// 会话状态（ChatModel）由 App 注入，Tab 与文档页悬浮入口共用。
struct AIChatView: View {
    @Environment(ChatModel.self) private var model
    @Environment(DocumentStore.self) private var store
    @FocusState private var inputFocused: Bool
    @State private var copiedID: UUID?
    /// 「已复制」确认的重置任务：视图消失时取消，不再用不跟踪取消的 asyncAfter。
    @State private var copyResetTask: Task<Void, Never>?
    /// 消息列表是否贴底：贴底时流式输出自动跟随滚底；用户上翻阅读时不强制拽回。
    @State private var pinnedToBottom = true
    /// 技能 chips / 空态的入场动画开关。
    @State private var chipsAppeared = false
    @State private var emptyStateVisible = false
    @State private var sealStamped = false
    /// 历史会话弹层。
    @State private var showHistory = false

    /// 列表底部锚点 id（贴底检测与滚动目标共用）。
    private let bottomAnchorID = "chat-bottom"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.messages.isEmpty {
                    emptyState
                } else {
                    messageList
                }
                undoBanner
                skillChips
                inputBar
            }
            .background(PaperTheme.paper)
            .navigationTitle("AI 助手")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showHistory = true } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("历史会话")
                }
            }
            .sheet(isPresented: $showHistory) {
                AIHistorySheet()
                    .presentationDetents([.medium, .large])
            }
            .onDisappear {
                copyResetTask?.cancel()
                copiedID = nil
            }
        }
    }

    // MARK: - 消息列表

    private var messageList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(model.messages) { msg in
                    bubbleRow(msg)
                        // 新消息到达：slide-up + fade
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
                }
                // 底部锚点：进出视口维护「贴底」状态，也是滚动到底的目标。
                Color.clear
                    .frame(height: 1)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .id(bottomAnchorID)
                    .onAppear { pinnedToBottom = true }
                    .onDisappear { pinnedToBottom = false }
            }
            .listStyle(.plain)
            .listRowSpacing(2)
            .scrollContentBackground(.hidden)
            .background(PaperTheme.paper)
            // 仅消息条数变化时带插入动画；流式文本增长不触发
            .animation(PaperTheme.Motion.quick, value: model.messages.count)
            // 拖动列表时键盘随手势收回
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) { _ in
                // 新消息（发送/回复开始）始终跳到底。
                pinnedToBottom = true
                scrollToBottom(proxy)
            }
            .onChange(of: model.messages.last?.text) { _ in
                // 流式增长：仅贴底时跟随。
                guard pinnedToBottom else { return }
                scrollToBottom(proxy)
            }
            .onAppear { proxy.scrollTo(bottomAnchorID, anchor: .bottom) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(PaperTheme.Motion.quick) {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
    }

    private func bubbleRow(_ msg: ChatModel.ChatMessage) -> some View {
        let isUser = msg.role == .user
        // 进行中的最后一条：实时步骤；历史消息：用快照回放
        let isLive = !isUser && model.isResponding && msg.id == model.messages.last?.id
        let displaySteps = isLive ? (model.runner?.steps ?? []) : msg.steps
        let thinking = isLive && msg.text.isEmpty && displaySteps.isEmpty
        return HStack(alignment: .top) {
            if isUser { Spacer(minLength: 44) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if !displaySteps.isEmpty {
                    AgentStepsView(steps: displaySteps)
                        .padding(.vertical, 2)
                }
                if thinking {
                    Text("思考中…")
                        .font(.body)
                        .italic()
                        .foregroundStyle(PaperTheme.inkSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(PaperTheme.card)
                        .clipShape(bubbleShape(isUser: false))
                        .shadow(color: PaperTheme.cardShadow, radius: 8, y: 2)
                } else if isUser {
                    Text(msg.text)
                        .font(.body)
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .lineSpacing(4)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(PaperTheme.accent)
                        .clipShape(bubbleShape(isUser: true))
                } else if !msg.text.isEmpty {
                    MarkdownText(
                        markdown: msg.text,
                        textColor: PaperTheme.ink,
                        secondaryColor: PaperTheme.inkSecondary,
                        codeBackground: PaperTheme.codeBackground,
                        accent: PaperTheme.accent
                    )
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(PaperTheme.card)
                    .clipShape(bubbleShape(isUser: false))
                    .shadow(color: PaperTheme.cardShadow, radius: 8, y: 2)
                }
                if !isUser && !model.isResponding && !msg.text.isEmpty {
                    actionRow(msg)
                }
            }
            if !isUser { Spacer(minLength: 44) }
        }
    }

    /// 助手消息操作：复制全文 / 插入当前文档。
    private func actionRow(_ msg: ChatModel.ChatMessage) -> some View {
        HStack(spacing: 16) {
            Button {
                Pasteboard.copy(msg.text)
                copiedID = msg.id
                copyResetTask?.cancel()
                let id = msg.id
                copyResetTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.4))
                    guard !Task.isCancelled, copiedID == id else { return }
                    copiedID = nil
                }
            } label: {
                Label(copiedID == msg.id ? "已复制" : "复制",
                      systemImage: copiedID == msg.id ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: copiedID == msg.id)
            }
            if store.hasDocument {
                Button { model.insertIntoDocument(msg.text) } label: {
                    Label("插入文档", systemImage: "text.insert")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(PaperTheme.inkSecondary)
        .buttonStyle(.pressable)
        .padding(.leading, 4)
    }

    /// AI 改动撤销条：一轮 run 改完文档后出现；用户再手动编辑则自动隐藏。
    private var undoBanner: some View {
        Group {
            if store.canUndoAI && !model.isResponding {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.footnote)
                    Text("AI 已修改文档")
                        .font(.footnote)
                    Spacer()
                    Button("撤销") { model.undoAIChanges() }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(PaperTheme.accent)
                        .buttonStyle(.pressable)
                }
                .foregroundStyle(PaperTheme.inkSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(PaperTheme.card)
                .overlay(alignment: .top) {
                    Rectangle().fill(PaperTheme.hairline).frame(height: 0.5)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(PaperTheme.Motion.standard, value: store.canUndoAI && !model.isResponding)
    }

    /// 用户气泡右对齐、右下角收紧到 4；助手气泡左对齐、左下角收紧。
    private func bubbleShape(isUser: Bool) -> UnevenRoundedRectangle {
        let r = PaperTheme.Radius.bubble
        return isUser
            ? UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r, bottomTrailingRadius: 4, topTrailingRadius: r, style: .continuous)
            : UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: 4, bottomTrailingRadius: r, topTrailingRadius: r, style: .continuous)
    }

    // MARK: - 输入栏

    private var inputBar: some View {
        @Bindable var model = model
        let canSend = !model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.isResponding
        return VStack(spacing: 0) {
            Rectangle()
                .fill(PaperTheme.hairline)
                .frame(height: 0.5)
            HStack(alignment: .bottom, spacing: 10) {
                TextField("给助手发消息", text: $model.input, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: PaperTheme.Radius.xlarge, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: PaperTheme.Radius.xlarge, style: .continuous)
                            .strokeBorder(
                                inputFocused ? PaperTheme.accent.opacity(0.55) : PaperTheme.hairline,
                                lineWidth: 1
                            )
                    }
                    .animation(PaperTheme.Motion.quick, value: inputFocused)
                if model.isResponding {
                    Button(action: model.cancel) {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(PaperCircleButtonStyle())
                    .accessibilityLabel("停止")
                } else {
                    Button(action: model.send) {
                        Image(systemName: "arrow.up")
                            .symbolEffect(.bounce, value: model.isResponding)
                    }
                    .buttonStyle(PaperCircleButtonStyle())
                    .disabled(!canSend)
                    .opacity(canSend ? 1 : 0.35)
                    .scaleEffect(canSend ? 1 : 0.88)
                    .animation(PaperTheme.Motion.quick, value: canSend)
                    .accessibilityLabel("发送")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(PaperTheme.card)
    }

    // MARK: - 技能快捷指令

    /// 已启用技能的快捷 chip：横滑一排，点按直接发送对应指令；出现时不齐整地错落淡入。
    private var skillChips: some View {
        let skills = MobileSkillStore.shared.enabledSkills
        return Group {
            if !skills.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(skills.enumerated()), id: \.element.id) { index, skill in
                            Button {
                                model.sendQuick(skill.quickPrompt)
                            } label: {
                                Label(skill.quickTrigger, systemImage: skill.icon)
                                    .font(.footnote)
                                    .foregroundStyle(PaperTheme.ink)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(PaperTheme.card, in: Capsule())
                                    .overlay {
                                        Capsule().strokeBorder(PaperTheme.hairline, lineWidth: 0.5)
                                    }
                            }
                            .buttonStyle(.pressable)
                            .disabled(model.isResponding)
                            .opacity(chipsAppeared ? (model.isResponding ? 0.45 : 1) : 0)
                            .offset(y: chipsAppeared ? 0 : 10)
                            .animation(
                                PaperTheme.Motion.quick.delay(Double(index) * 0.05),
                                value: chipsAppeared
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .onAppear { chipsAppeared = true }
            }
        }
    }

    // MARK: - 空态

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "text.bubble")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(PaperTheme.inkSecondary)
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("把初稿交给它打磨")
                    .font(PaperTheme.Typography.uiTitle3())
                    .foregroundStyle(PaperTheme.ink)
                SealStamp(size: 22)
                    .alignmentGuide(.lastTextBaseline) { $0[.bottom] }
                    .scaleEffect(sealStamped ? 1 : 1.8)
                    .opacity(sealStamped ? 1 : 0)
                    .rotationEffect(.degrees(sealStamped ? 0 : 12))
            }
            Text("问点什么，或让 AI 帮你修改当前文档。")
                .font(.subheadline)
                .foregroundStyle(PaperTheme.inkSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaperTheme.paper)
        .opacity(emptyStateVisible ? 1 : 0)
        .offset(y: emptyStateVisible ? 0 : 14)
        .onAppear {
            withAnimation(PaperTheme.Motion.gentle) { emptyStateVisible = true }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.62).delay(0.4)) {
                sealStamped = true
            }
        }
        // 空态下点击空白处收回键盘
        .onTapGesture { inputFocused = false }
    }
}
