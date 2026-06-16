import SwiftUI

struct CommentsPanel: View {
    @Environment(AppState.self) private var state

    let theme: PreviewTheme

    @State private var draft = ""
    @State private var comments: [DocumentComment] = []

    private let store = DocumentCommentStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let tab = state.selectedTab {
                composer(for: tab.url)

                if comments.isEmpty {
                    placeholderPanel(
                        title: L("rightPanel.comments.emptyTitle"),
                        message: L("rightPanel.comments.emptyMessage")
                    )
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(comments) { comment in
                            CommentRow(
                                comment: comment,
                                theme: theme,
                                onToggleResolved: {
                                    comments = store.toggleResolved(comment.id, for: tab.url)
                                },
                                onDelete: {
                                    comments = store.delete(comment.id, for: tab.url)
                                }
                            )
                        }
                    }
                }
            } else {
                placeholderPanel(
                    title: L("rightPanel.comments.noDocumentTitle"),
                    message: L("rightPanel.comments.noDocumentMessage")
                )
            }
        }
        .onAppear { reload() }
        .onChange(of: state.selectedTab?.url) { _, _ in
            draft = ""
            reload()
        }
    }

    private func composer(for url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("rightPanel.comments.add"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.craftSecondary)
                .textCase(.uppercase)

            TextEditor(text: $draft)
                .font(.system(size: 12))
                .foregroundStyle(theme.craftPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 64, maxHeight: 96)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.craftHover.opacity(0.86))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.separator.opacity(theme.isDark ? 0.24 : 0.18), lineWidth: 1)
                )

            Button {
                comments = store.add(draft, for: url)
                draft = ""
            } label: {
                Label(L("rightPanel.comments.addButton"), systemImage: "plus.bubble")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func reload() {
        guard let url = state.selectedTab?.url else {
            comments = []
            return
        }
        comments = store.comments(for: url)
    }

    private func placeholderPanel(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.craftPrimary)

            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(theme.craftSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CommentRow: View {
    let comment: DocumentComment
    let theme: PreviewTheme
    let onToggleResolved: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Button(action: onToggleResolved) {
                    Image(systemName: comment.isResolved ? "checkmark.circle.fill" : "circle")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(comment.isResolved ? Color.green : theme.craftSecondary)
                }
                .buttonStyle(.plain)
                .help(comment.isResolved ? L("rightPanel.comments.markOpen") : L("rightPanel.comments.markResolved"))

                Text(Self.dateFormatter.string(from: comment.createdAt))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.craftSecondary)

                Spacer()

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.craftSecondary)
                        .opacity(isHovered ? 1 : 0.45)
                }
                .buttonStyle(.plain)
                .help(L("common.delete"))
            }

            Text(comment.text)
                .font(.system(size: 12))
                .foregroundStyle(comment.isResolved ? theme.craftSecondary : theme.craftPrimary)
                .strikethrough(comment.isResolved, color: theme.craftSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isHovered ? theme.craftHover : theme.craftHover.opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(theme.separator.opacity(theme.isDark ? 0.22 : 0.16), lineWidth: 1)
        )
        .onHover { isHovered = $0 }
        .animation(DS.Motion.micro, value: isHovered)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
