import SwiftUI

/// Floating action strip shown at the editor's bottom when text is selected.
/// Tapping an action opens InlineEditSheet.
struct InlineEditBar: View {
    @Environment(AppState.self) private var state

    let selectedText: String

    @State private var pendingAction: InlineEditAction? = nil

    var body: some View {
        HStack(spacing: 2) {
            ForEach(InlineEditAction.allCases) { action in
                actionButton(action)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .sheet(item: $pendingAction) { action in
            InlineEditSheet(originalText: selectedText, action: action)
                .environment(state)
        }
    }

    private func actionButton(_ action: InlineEditAction) -> some View {
        Button {
            state.pendingReplaceRange = state.editorSelectedRange
            pendingAction = action
        } label: {
            HStack(spacing: 4) {
                Image(systemName: action.icon)
                    .font(.system(size: 10, weight: .medium))
                Text(action.rawValue)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.05), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(action.rawValue)
    }
}
