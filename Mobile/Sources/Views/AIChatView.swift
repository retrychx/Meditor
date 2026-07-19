import SwiftUI

/// AI 对话面板：消息列表 + 输入框，接共享的 AgentRunner 流式回复。
/// 会话状态（ChatModel）由 App 注入，Tab 与文档页悬浮入口共用。
struct AIChatView: View {
    @Environment(ChatModel.self) private var model
    @Environment(DocumentStore.self) private var store
    @FocusState private var inputFocused: Bool
    @State private var copiedID: UUID?

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
        }
    }

    // MARK: - 消息列表

    private var messageList: some View {
        List(model.messages) { msg in
            bubbleRow(msg)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
        .listStyle(.plain)
        .listRowSpacing(2)
        .scrollContentBackground(.hidden)
        .background(PaperTheme.paper)
        // 拖动列表时键盘随手势收回
        .scrollDismissesKeyboard(.interactively)
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
                        .overlay {
                            bubbleShape(isUser: false)
                                .strokeBorder(PaperTheme.hairline, lineWidth: 0.5)
                        }
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
                    .overlay {
                        bubbleShape(isUser: false)
                            .strokeBorder(PaperTheme.hairline, lineWidth: 0.5)
                    }
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    if copiedID == msg.id { copiedID = nil }
                }
            } label: {
                Label(copiedID == msg.id ? "已复制" : "复制",
                      systemImage: copiedID == msg.id ? "checkmark" : "doc.on.doc")
            }
            if store.hasDocument {
                Button { model.insertIntoDocument(msg.text) } label: {
                    Label("插入文档", systemImage: "text.insert")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(PaperTheme.inkSecondary)
        .buttonStyle(.plain)
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
                }
                .foregroundStyle(PaperTheme.inkSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(PaperTheme.card)
                .overlay(alignment: .top) {
                    Rectangle().fill(PaperTheme.hairline).frame(height: 0.5)
                }
            }
        }
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
                    .background(PaperTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(PaperTheme.hairline, lineWidth: 1)
                    }
                if model.isResponding {
                    Button(action: model.cancel) {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(PaperCircleButtonStyle())
                    .accessibilityLabel("停止")
                } else {
                    Button(action: model.send) {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(PaperCircleButtonStyle())
                    .disabled(!canSend)
                    .opacity(canSend ? 1 : 0.35)
                    .accessibilityLabel("发送")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(PaperTheme.card)
    }

    // MARK: - 技能快捷指令

    /// 已启用技能的快捷 chip：横滑一排，点按直接发送对应指令。
    private var skillChips: some View {
        let skills = MobileSkillStore.shared.enabledSkills
        return Group {
            if !skills.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(skills) { skill in
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
                            .buttonStyle(.plain)
                            .disabled(model.isResponding)
                            .opacity(model.isResponding ? 0.45 : 1)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
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
            Text("把初稿交给它打磨")
                .font(PaperTheme.Typography.serifTitle3())
                .foregroundStyle(PaperTheme.ink)
            Text("问点什么，或让 AI 帮你修改当前文档。")
                .font(.subheadline)
                .foregroundStyle(PaperTheme.inkSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaperTheme.paper)
        // 空态下点击空白处收回键盘
        .onTapGesture { inputFocused = false }
    }
}
