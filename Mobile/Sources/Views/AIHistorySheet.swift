import SwiftUI

/// 历史会话弹层：列出全部会话（首条用户消息摘要 + 相对时间 + 消息数），
/// 点击切换恢复，左滑删除，工具栏提供「新会话」。数据来自 ChatModel.convo
/// （桌面端同款 AIConversation），行展示对齐 macOS AIHistoryView。
struct AIHistorySheet: View {
    @Environment(ChatModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .background(PaperTheme.paper)
            .navigationTitle("历史会话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        model.newSession()
                        dismiss()
                    } label: {
                        Label("新会话", systemImage: "square.and.pencil")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    /// 从未发言的空会话不进历史列表（对齐 macOS AIHistoryView 的过滤）。
    private var items: [AISession] {
        model.sessions.filter { !$0.messages.isEmpty }
    }

    private var sessionList: some View {
        List(items) { session in
            Button {
                model.activateSession(session.id)
                dismiss()
            } label: {
                row(session)
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    model.deleteSession(session.id)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(PaperTheme.paper)
    }

    private func row(_ session: AISession) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bubble.left")
                .font(.subheadline)
                .foregroundStyle(session.id == model.activeSessionID ? PaperTheme.accent : PaperTheme.inkSecondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title(for: session))
                    .font(.body)
                    .foregroundStyle(PaperTheme.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(session.updatedAt, style: .relative)
                    Text("·")
                    Text("\(session.messages.count) 条消息")
                }
                .font(.caption)
                .foregroundStyle(PaperTheme.inkSecondary)
            }
            Spacer(minLength: 4)
            if session.id == model.activeSessionID {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PaperTheme.accent)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    /// 摘要 = 会话标题（即首条用户消息前 40 字，AIConversation 自动生成）；
    /// 缺标题时兜底取首条用户消息，最后退化为「未命名会话」。
    private func title(for session: AISession) -> String {
        if !session.title.isEmpty { return session.title }
        if let firstUser = session.messages.first(where: { $0.role == .user }) {
            return String(firstUser.text.prefix(40))
        }
        return "未命名会话"
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(PaperTheme.inkSecondary)
            Text("暂无历史会话")
                .font(.subheadline)
                .foregroundStyle(PaperTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaperTheme.paper)
    }
}
