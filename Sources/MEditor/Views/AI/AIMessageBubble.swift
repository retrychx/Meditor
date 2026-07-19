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
                    MarkdownText(
                        markdown: message.text,
                        textColor: theme.craftPrimary,
                        secondaryColor: theme.craftSecondary,
                        codeBackground: theme.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.045),
                        accent: Color.appAccent
                    )
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

                    if !convo.isResponding || message.id != convo.messages.last?.id {
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
