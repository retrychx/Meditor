import SwiftUI

struct EditorView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            if !state.openTabs.isEmpty {
                EditorTabBar()
                Divider()
            }

            if let tab = state.selectedTab {
                NativeEditorView(
                    content: tab.content,
                    language: tab.language,
                    onContentChange: { [tabID = tab.id] content in
                        state.updateTabContent(tabID, content: content)
                    }
                )
            } else {
                emptyState
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text("Select a file to edit")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Tab Bar

struct EditorTabBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(state.openTabs) { tab in
                    tabButton(tab)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 32)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func tabButton(_ tab: EditorTab) -> some View {
        let isSelected = tab.id == state.selectedTabID

        return HStack(spacing: 4) {
            Image(systemName: tab.iconName)
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)

            Text(tab.name)
                .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)

            if tab.isModified {
                Circle()
                    .fill(.secondary)
                    .frame(width: 6, height: 6)
            }

            Button {
                state.closeTab(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(2)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.1))
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 0.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            state.selectedTabID = tab.id
            if let selectedTab = state.selectedTab {
                state.previewContent = selectedTab.content
                state.previewLanguage = selectedTab.language
            }
        }
    }
}
