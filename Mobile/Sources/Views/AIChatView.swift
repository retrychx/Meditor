import SwiftUI

/// AI 对话面板：消息列表 + 输入框，接共享的 AgentRunner 流式回复。
struct AIChatView: View {
    @State private var model: ChatModel

    init(store: DocumentStore, settings: MobileAISettings) {
        _model = State(initialValue: ChatModel(store: store, settings: settings))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.messages.isEmpty {
                    emptyState
                } else {
                    messageList
                }
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
    }

    private func bubbleRow(_ msg: ChatModel.ChatMessage) -> some View {
        let isUser = msg.role == .user
        let thinking = msg.text.isEmpty && !isUser && model.isResponding
        return HStack(alignment: .top) {
            if isUser { Spacer(minLength: 44) }
            Text(thinking ? "思考中…" : msg.text)
                .font(.body)
                .italic(thinking)
                .foregroundStyle(thinking ? PaperTheme.inkSecondary : (isUser ? .white : PaperTheme.ink))
                .textSelection(.enabled)
                .lineSpacing(4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isUser ? PaperTheme.accent : PaperTheme.card)
                .clipShape(bubbleShape(isUser: isUser))
                .overlay {
                    if !isUser {
                        bubbleShape(isUser: false)
                            .strokeBorder(PaperTheme.hairline, lineWidth: 0.5)
                    }
                }
            if !isUser { Spacer(minLength: 44) }
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
    }
}
