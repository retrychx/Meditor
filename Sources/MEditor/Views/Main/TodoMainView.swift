import SwiftUI

/// 全宽待办主视图 — 点击底部 tab 的"待办"后替换主内容区。
struct TodoMainView: View {
    @Environment(AppState.self) private var state
    @State private var todos: [TodoItem] = []
    @State private var isLoading = false

    private var theme: PreviewTheme { state.themeStore.current }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().opacity(0.3)
            content
        }
        .background(theme.windowBackground)
        .task(id: state.rootURL) {
            await reload()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.appAccent)

            Text(L("sidebar.tasks"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.craftPrimary)

            Spacer()

            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.craftSecondary)
                }
                .buttonStyle(.plain)
                .help(L("todo.refresh"))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if state.rootURL == nil {
            emptyMessage(L("todo.noRoot"), icon: "folder.badge.questionmark")
        } else if todos.isEmpty && !isLoading {
            emptyMessage(L("todo.empty"), icon: "checkmark.circle")
        } else {
            todoList
        }
    }

    private var todoList: some View {
        List {
            let pending = todos.filter { !$0.isChecked }
            let done = todos.filter { $0.isChecked }

            if !pending.isEmpty {
                Section(header: sectionHeader("待办 (\(pending.count))")) {
                    ForEach(pending) { item in
                        TodoMainRow(item: item, theme: theme,
                                    onTap: { jumpTo(item) }, onToggle: { toggle(item) })
                    }
                }
                .listRowInsets(.init(top: 2, leading: 24, bottom: 2, trailing: 24))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if !done.isEmpty {
                Section(header: sectionHeader("已完成 (\(done.count))")) {
                    ForEach(done) { item in
                        TodoMainRow(item: item, theme: theme,
                                    onTap: { jumpTo(item) }, onToggle: { toggle(item) })
                    }
                }
                .listRowInsets(.init(top: 2, leading: 24, bottom: 2, trailing: 24))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .kerning(0.2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 2)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func emptyMessage(_ text: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    // MARK: - Actions

    private func reload() async {
        guard let root = state.rootURL else { todos = []; return }
        isLoading = true
        todos = await TodoScanner.scan(rootURL: root)
        isLoading = false
    }

    private func jumpTo(_ item: TodoItem) {
        let fileItem = FileItem(url: item.fileURL, isDirectory: false)
        state.openFile(fileItem)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            state.requestEditorScroll(to: item.lineIndex)
        }
    }

    private func toggle(_ item: TodoItem) {
        guard let idx = todos.firstIndex(where: { $0.id == item.id }) else { return }
        do {
            try TodoScanner.toggle(item: item)
            todos[idx].isChecked.toggle()
        } catch {
            state.setError(error.localizedDescription)
        }
    }
}

// MARK: - Row

private struct TodoMainRow: View {
    let item: TodoItem
    let theme: PreviewTheme
    let onTap: () -> Void
    let onToggle: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(item.isChecked ? Color.appAccent : theme.craftSecondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.text)
                    .font(.system(size: 14))
                    .foregroundStyle(item.isChecked ? theme.craftSecondary : theme.craftPrimary)
                    .strikethrough(item.isChecked, color: theme.craftSecondary)
                    .lineLimit(2)
                Text(item.fileURL.lastPathComponent)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.craftSecondary.opacity(0.6))
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { onTap() }
        .animation(DS.Motion.micro, value: isHovered)
    }
}
