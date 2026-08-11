import SwiftUI

// MARK: - Message bubble

extension AIAssistantPanel {
    func bubble(_ message: AIChatMessage) -> some View {
        HStack(alignment: .top, spacing: 9) {
            if message.role == .user {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.system(size: 13))
                    .foregroundStyle(accent.onFill(theme))
                    .textSelection(.enabled)
                    .lineSpacing(3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(accent.fill(theme))
                    )
            } else {
                AIAssistantOrb(size: 20, glow: true).padding(.top, 1)
                VStack(alignment: .leading, spacing: 6) {
                    // 正在流式增长的 reply（最后一条 assistant 消息）
                    let isStreamingReply = convo.isResponding && message.id == convo.messages.last?.id
                    Group {
                        if isStreamingReply {
                            // 流式进行中降级为纯文本渲染：整条 Markdown 随每个 chunk
                            // （约 50ms 一次）重解析，回复越长成本越高；纯文本近乎零成本。
                            // 完成后 isResponding 复位，自动切回 MarkdownText 渲染。
                            Text(message.text)
                                .font(.system(size: 13))
                                .foregroundStyle(theme.craftPrimary)
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            MarkdownText(
                                markdown: message.text,
                                textColor: theme.craftPrimary,
                                secondaryColor: theme.craftSecondary,
                                codeBackground: theme.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.045),
                                accent: Color.appAccent
                            )
                        }
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(theme.isDark ? Color.white.opacity(0.03) : Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(theme.separator.opacity(theme.isDark ? 0.5 : 0.7), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(theme.isDark ? 0.18 : 0.04), radius: 5, x: 0, y: 1)

                    if !isStreamingReply {
                        HStack(spacing: 12) {
                            AIMessageAction(icon: "doc.on.doc", title: L("ai.copy"), theme: theme) {
                                Pasteboard.copy(message.text)
                            }
                            AIMessageAction(icon: "text.insert", title: L("ai.insertToDoc"), theme: theme) {
                                state.insertIntoEditor(message.text)
                            }
                            Spacer()
                        }
                        .padding(.leading, 2)
                    }
                }
            }
        }
    }
}

// MARK: - Bubble action button

private struct AIMessageAction: View {
    let icon: String
    let title: String
    let theme: PreviewTheme
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10.5, weight: .medium))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(hovered ? theme.craftPrimary : theme.craftSecondary)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(title)
    }
}
