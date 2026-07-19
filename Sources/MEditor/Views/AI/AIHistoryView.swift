import SwiftUI

// MARK: - History popover

@MainActor
struct AIHistoryView: View {
    @Bindable var convo: AIConversation
    let theme: PreviewTheme
    let onPick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("ai.history.title"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.craftSecondary)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 6)

            let items = convo.history.filter { !$0.messages.isEmpty }
            if items.isEmpty {
                Text(L("ai.history.empty"))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.craftSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(items) { session in
                            AIHistoryRow(
                                title: session.title.isEmpty ? L("ai.session.untitled") : session.title,
                                isActive: session.id == convo.activeID,
                                theme: theme,
                                onSelect: { convo.activate(session.id); onPick() },
                                onDelete: { convo.delete(session.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 280)
        .background(theme.editorBackground)
    }
}

// MARK: - History row

private struct AIHistoryRow: View {
    let title: String
    let isActive: Bool
    let theme: PreviewTheme
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left")
                .font(.system(size: 11))
                .foregroundStyle(isActive ? Color.appAccent : theme.craftSecondary)
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.craftPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if hovered {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.craftSecondary)
                }
                .buttonStyle(.plain)
                .help(L("common.delete"))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? Color.appAccent.opacity(0.12) : (hovered ? theme.craftHover : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovered = $0 }
    }
}
