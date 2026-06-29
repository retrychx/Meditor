import SwiftUI

// MARK: - File Action

enum FileAction: Hashable {
    case newFile(URL)
    case newFolder(URL)
    case rename(FileItem)
    case delete(FileItem)
    case copyAbsolutePath(FileItem)
    case copyRelativePath(FileItem)
    case revealInFinder(FileItem)
}

// MARK: - FileSidebar (Craft-style)

struct FileSidebar: View {
    @Environment(AppState.self) private var state
    @Environment(WorkspaceUIState.self) private var workspaceUI
    @State private var searchText = ""
    @State private var showCreateAlert = false
    @State private var createName = ""
    @State private var createParentURL: URL?
    @State private var createIsFolder = false

    @State private var showRenameAlert = false
    @State private var renameName = ""
    @State private var renameTarget: FileItem?

    @State private var showDeleteConfirmation = false
    @State private var itemToDelete: FileItem?

    @State private var userDocFiles: [URL] = []
    @State private var appDocFiles: [URL] = []
    @State private var userDocExpanded = true
    @State private var appDocExpanded  = true
    @State private var looseExpanded   = true

    private var displayedTree: [FileItem] {
        guard !searchText.isEmpty else { return state.fileTree }
        if !state.indexedFiles.isEmpty {
            return state.indexedFiles.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return flattenLoadedMatches(state.fileTree)
    }

    private func flattenLoadedMatches(_ items: [FileItem]) -> [FileItem] {
        var result: [FileItem] = []
        for item in items {
            if !item.isDirectory && item.name.localizedCaseInsensitiveContains(searchText) { result.append(item) }
            if let children = item.children { result.append(contentsOf: flattenLoadedMatches(children)) }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Space Switcher (Craft top row) ──
            SpaceSwitcherRow()

            // ── Search bar ──
            SidebarSearchBar(text: $searchText)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 8)

            // ── 始终显示文件树 ──
            if searchText.isEmpty { mainContent } else { searchResultsView }

            // ── Pinned app views (Tasks / Calendar Tab 切换条) ──
            if searchText.isEmpty {
                PinnedViewsBar(activeMainView: workspaceUI.activeMainView) { newView in
                    workspaceUI.activeMainView = newView
                }
            }


            // ── Bottom toolbar ──
            SidebarBottomBar(
                onNewFile: {
                    state.templateCreateParentURL = state.rootURL
                    createIsFolder = false
                    state.showingTemplatePicker = true
                },
                onNewFolder: {
                    createParentURL = state.rootURL; createIsFolder = true
                    createName = ""; showCreateAlert = true
                }
            )
        }
        .background(.clear)
        .onChange(of: state.selectedTabID) { _, _ in
            expandToSelectedFile()
        }
        .sheet(isPresented: $showCreateAlert) {
            InputDialog(
                title: L(createIsFolder ? "menu.newFolder" : "menu.newFile"),
                message: L(createIsFolder ? "create.messageFolder" : "create.messageFile"),
                placeholder: L(createIsFolder ? "create.folderName" : "create.fileName"),
                confirmTitle: L("common.create"),
                text: $createName,
                onConfirm: { createItem(); showCreateAlert = false },
                onCancel: { resetCreateState(); showCreateAlert = false }
            )
        }
        .sheet(isPresented: $showRenameAlert) {
            InputDialog(
                title: L("rename.title"),
                message: renameTarget.map { L("rename.messageFormat", $0.name) } ?? "",
                placeholder: L("rename.newName"),
                confirmTitle: L("rename.title"),
                text: $renameName,
                onConfirm: { renameItem(); showRenameAlert = false },
                onCancel: { resetRenameState(); showRenameAlert = false }
            )
        }
        .confirmationDialog(
            L("delete.confirmFormat", itemToDelete?.name ?? ""),
            isPresented: $showDeleteConfirmation, titleVisibility: .visible
        ) {
            Button(L("common.delete"), role: .destructive) {
                if let item = itemToDelete { deleteItem(item) }
                itemToDelete = nil
            }
            Button(L("common.cancel"), role: .cancel) { itemToDelete = nil }
        }
    }

    // MARK: - Main content (when not searching)

    private var mainContent: some View {
        List {
            // User document section
            let userPath = AppSettings.shared.userDocPath
            if let _ = userPath, !userDocFiles.isEmpty {
                Section(isExpanded: $userDocExpanded) {
                    ForEach(userDocFiles, id: \.path) { url in
                        DocFileRow(url: url, isSelected: state.selectedFileID == url)
                            .onTapGesture { state.openFile(FileItem(url: url, isDirectory: false)) }
                    }
                } header: {
                    CraftSectionHeader(title: "用户文档")
                }
                .listRowInsets(.init(top: 1, leading: 12, bottom: 1, trailing: 12))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // App document section
            if !appDocFiles.isEmpty {
                Section(isExpanded: $appDocExpanded) {
                    ForEach(appDocFiles, id: \.path) { url in
                        DocFileRow(url: url, isSelected: state.selectedFileID == url)
                            .onTapGesture { state.openFile(FileItem(url: url, isDirectory: false)) }
                    }
                } header: {
                    CraftSectionHeader(title: "App 文档")
                }
                .listRowInsets(.init(top: 1, leading: 12, bottom: 1, trailing: 12))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // 散文件 section（不属于任何 Workspace 的独立文件）
            if !state.looseFiles.files.isEmpty {
                Section(isExpanded: $looseExpanded) {
                    ForEach(state.looseFiles.files) { file in
                        LooseFileRow(
                            file: file,
                            isSelected: state.selectedTab?.url == file.url
                        )
                        .onTapGesture { state.openLooseFile(file.url) }
                        .contextMenu {
                            Button("在 Finder 中显示") {
                                NSWorkspace.shared.activateFileViewerSelecting([file.url])
                            }
                            Button("复制路径") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(file.url.path, forType: .string)
                            }
                            Divider()
                            Button("从列表移除", role: .destructive) {
                                state.looseFiles.remove(file.id)
                            }
                        }
                    }
                } header: {
                    CraftSectionHeader(title: "散文件")
                }
                .listRowInsets(.init(top: 1, leading: 12, bottom: 1, trailing: 12))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // Workspace folders section
            if !state.fileTree.isEmpty {
                Section {
                    ForEach(state.fileTree) { item in
                        SidebarTreeNode(
                            item: item,
                            searchText: "",
                            onAction: handleFileAction,
                            onTap: { selectSidebarItem($0) }
                        )
                    }
                } header: {
                    CraftSectionHeader(title: L("sidebar.folders"))
                }
                .listRowInsets(.init(top: 1, leading: 12, bottom: 1, trailing: 12))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { refreshDocFiles() }
        .onReceive(NotificationCenter.default.publisher(for: .docPathChanged)) { _ in
            refreshDocFiles()
        }
    }

    private func refreshDocFiles() {
        userDocFiles = listDocFiles(at: AppSettings.shared.userDocPath)
        appDocFiles  = listDocFiles(at: AppSettings.shared.appDocPath)
    }

    private func listDocFiles(at url: URL?) -> [URL] {
        guard let url else { return [] }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let allowed: Set<String> = ["md", "html"]
        return contents
            .filter { u in
                guard let res = try? u.resourceValues(forKeys: [.isDirectoryKey]) else { return false }
                return res.isDirectory == false && allowed.contains(u.pathExtension.lowercased())
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    @ViewBuilder
    private var searchResultsView: some View {
        if displayedTree.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(L("common.noMatches"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(displayedTree, id: \.id) { item in
                FileRow(item: item, isSelected: item.id == state.selectedFileID,
                        searchText: searchText, onAction: handleFileAction)
                    .help(item.url.path)
                    .contentShape(Rectangle())
                    .onTapGesture { state.openFile(item) }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Actions

    private func handleFileAction(_ action: FileAction) {
        switch action {
        case .newFile(let parentURL):
            state.templateCreateParentURL = parentURL
            createIsFolder = false
            state.showingTemplatePicker = true
        case .newFolder(let parentURL):
            createParentURL = parentURL; createIsFolder = true; createName = ""; showCreateAlert = true
        case .rename(let item):
            renameTarget = item; renameName = item.name; showRenameAlert = true
        case .delete(let item):
            itemToDelete = item; showDeleteConfirmation = true
        case .copyAbsolutePath(let item):
            copyToPasteboard(item.url.path)
        case .copyRelativePath(let item):
            copyToPasteboard(FilePathFormatter.relativePath(for: item.url, rootURL: state.rootURL))
        case .revealInFinder(let item):
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        }
    }

    private func createItem() {
        guard let parentURL = createParentURL, !createName.isEmpty else { resetCreateState(); return }
        let fileName = createIsFolder ? createName : (createName.hasSuffix(".md") ? createName : "\(createName).md")
        state.createFileOrFolder(name: fileName, isFolder: createIsFolder, parentURL: parentURL)
        resetCreateState()
    }

    private func resetCreateState() { createName = ""; createParentURL = nil }

    private func renameItem() {
        guard let target = renameTarget, !renameName.isEmpty else { resetRenameState(); return }
        state.renameFileItem(from: target.url, newName: renameName)
        resetRenameState()
    }

    private func resetRenameState() { renameName = ""; renameTarget = nil }
    private func deleteItem(_ item: FileItem) { state.deleteFileItem(at: item.url) }

    private func copyToPasteboard(_ value: String) {
        Pasteboard.copy(value)
    }

    private func selectSidebarItem(_ item: FileItem) { state.selectFile(item) }

    /// Expand all ancestor directories of the currently selected tab's file
    /// so the highlighted row is visible in the tree.
    private func expandToSelectedFile() {
        guard let url = state.selectedTab?.url,
              let root = state.rootURL else { return }
        let rootPath = root.standardizedFileURL.path
        var dir = url.deletingLastPathComponent().standardizedFileURL
        while dir.path.hasPrefix(rootPath), dir.path != rootPath {
            workspaceUI.setExpanded(FileItem(url: dir, isDirectory: true), true)
            state.loadChildrenIfNeeded(for: FileItem(url: dir, isDirectory: true))
            dir = dir.deletingLastPathComponent().standardizedFileURL
        }
    }
}

// MARK: - Space Switcher

private struct SidebarTitlebarRow: View {
    @Bindable var workspaceUI: WorkspaceUIState
    @Environment(AppState.self) private var state
    @State private var isHovered = false

    var body: some View {
        let theme = state.themeStore.current
        HStack(spacing: 0) {
            // macOS traffic lights occupy this area. We keep it empty so the
            // real window controls visually belong to the sidebar, like Craft.
            Color.clear.frame(width: 78)

            Spacer()

            Button {
                withAnimation(DS.Motion.springFast) {
                    workspaceUI.showsSidebar = false
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.craftSecondary.opacity(isHovered ? 0.9 : 0.58))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isHovered ? theme.craftHover : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("b", modifiers: [.command, .option])
            .help(L("tooltip.hideSidebar"))
            .onHover { isHovered = $0 }
        }
        .frame(height: 36)
        .padding(.trailing, 8)
    }
}

private struct SpaceSwitcherRow: View {
    @Environment(AppState.self) private var state
    @Environment(WorkspaceUIState.self) private var workspaceUI
    @Environment(\.sidebarToggleNS) private var sidebarNS
    @State private var isHovered = false
    @State private var isCollapseHovered = false

    var body: some View {
        let theme = state.themeStore.current
        HStack(spacing: 9) {
            // Workspace icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.orange.opacity(0.18))
                    .frame(width: 26, height: 26)
                Image(systemName: "folder.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(nsColor: .systemOrange))
            }

            Text(state.rootURL?.lastPathComponent ?? "MEditor")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.craftPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // Collapse button — lives inside the sidebar card while expanded.
            Button {
                withAnimation(DS.Motion.panel) { workspaceUI.showsSidebar = false }
            } label: {
                Image(systemName: "sidebar.left")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.craftSecondary.opacity(isCollapseHovered ? 0.95 : 0.55))
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isCollapseHovered ? theme.craftHover : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .onHover { isCollapseHovered = $0 }
            .help(L("tooltip.hideSidebar"))
            .heroMatch("sidebarToggle", in: sidebarNS)
            .animation(DS.Motion.micro, value: isCollapseHovered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(DS.Motion.micro, value: isHovered)
    }
}

// MARK: - Search Bar

private struct SidebarSearchBar: View {
    @Binding var text: String
    @Environment(AppState.self) private var state

    var body: some View {
        let theme = state.themeStore.current
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.craftSecondary)
                .font(.system(size: 11))
            TextField(L("common.search"), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.craftPrimary)
            if !text.isEmpty {
                Button { withAnimation(DS.Motion.micro) { text = "" } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(theme.craftSecondary)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.craftHover)
        )
    }
}

// MARK: - Top Nav Entry (All Docs / Recent / Favorites)

private struct TopNavEntry: View {
    let icon: String
    let label: String
    var isSelected = false
    @Environment(AppState.self) private var state
    @State private var isHovered = false

    var body: some View {
        let theme = state.themeStore.current
        HStack(spacing: 8) {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? theme.craftPrimary : theme.craftSecondary)
                .frame(width: 20, alignment: .center)
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? theme.craftPrimary : theme.craftPrimary.opacity(0.72))
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.10) : isHovered ? Color.primary.opacity(0.05) : Color.clear)
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(DS.Motion.micro, value: isHovered)
    }
}

private struct CraftSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .kerning(0.2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)
            .padding(.top, 5)
            .padding(.bottom, 1)
    }
}

private struct PinnedViewsBar: View {
    let activeMainView: ActiveMainView
    let onSelect: (ActiveMainView) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)
            HStack(spacing: 0) {
                PinnedTabButton(
                    icon: "checkmark.circle",
                    label: L("sidebar.tasks"),
                    isSelected: activeMainView == .todos
                ) { onSelect(activeMainView == .todos ? .document : .todos) }

                PinnedTabButton(
                    icon: "calendar",
                    label: L("sidebar.calendar"),
                    isSelected: activeMainView == .calendar
                ) { onSelect(activeMainView == .calendar ? .document : .calendar) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }
}

private struct PinnedTabButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Color.appAccent : .secondary)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Color.appAccent : .primary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected
                          ? Color.appAccent.opacity(0.12)
                          : isHovered ? Color.primary.opacity(0.05) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(DS.Motion.micro, value: isHovered)
        .animation(DS.Motion.fast, value: isSelected)
    }
}

private struct SidebarBottomBar: View {
    @Environment(AppState.self) private var state
    @Environment(WorkspaceUIState.self) private var workspaceUI
    let onNewFile: () -> Void
    let onNewFolder: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)
            HStack {
                SidebarIconButton(icon: "doc.badge.plus", help: L("sidebar.newDocument"), action: onNewFile)
                    .disabled(state.rootURL == nil)
                Spacer()
                SidebarIconButton(icon: "folder.badge.plus", help: L("sidebar.newFolder"), action: onNewFolder)
                    .disabled(state.rootURL == nil)
                // 专注模式切换
                SidebarIconButton(
                    icon: workspaceUI.isFocusMode ? "scope" : "scope",
                    help: workspaceUI.isFocusMode ? L("tooltip.exitFocus") : L("tooltip.focusMode"),
                    isActive: workspaceUI.isFocusMode
                ) {
                    withAnimation(DS.Motion.springFast) { workspaceUI.toggleFocusMode() }
                }
                SidebarIconButton(icon: "gearshape", help: L("menu.preferences")) {
                    state.showingSettings = true
                }
                .anchorPreference(key: SettingsAnchorKey.self, value: .bounds) { $0 }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.clear)
        }
    }
}

private struct SidebarIconButton: View {
    let icon: String
    let help: String
    var isActive: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 14))
                .foregroundStyle(
                    isActive ? Color.appAccent
                    : Color.secondary.opacity(isHovered ? 1 : 0.55)
                )
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            isActive ? Color.appAccent.opacity(0.12)
                            : isHovered ? Color.primary.opacity(0.07) : Color.clear
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .animation(DS.Motion.micro, value: isHovered)
    }
}

// MARK: - Doc File Row

private struct DocFileRow: View {
    let url: URL
    let isSelected: Bool
    @State private var isHovered = false
    @Environment(AppState.self) private var state

    private var icon: String {
        switch url.pathExtension.lowercased() {
        case "html": return "doc.richtext"
        default:     return "doc.text"
        }
    }

    var body: some View {
        let theme = state.themeStore.current
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? theme.craftPrimary : theme.craftSecondary)
                .frame(width: 16, alignment: .center)
            Text(url.lastPathComponent)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? theme.craftPrimary : theme.craftPrimary.opacity(0.82))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected
                      ? Color.primary.opacity(0.10)
                      : isHovered ? Color.primary.opacity(0.05) : Color.clear)
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(DS.Motion.micro, value: isHovered)
    }
}

// MARK: - LooseFileRow

/// 侧边栏「散文件」区的单行条目。
private struct LooseFileRow: View {
    let file: LooseFile
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            // 来源图标
            Image(systemName: file.source == .claude ? "sparkles" : "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(file.source == .claude ? Color.appAccent : .secondary)
                .frame(width: 14)

            // 文件名
            Text(file.name)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? Color.white : .primary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected
                    ? Color.appAccent
                    : (isHovered ? Color.primary.opacity(0.07) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(DS.Motion.micro, value: isHovered)
        .help(file.url.path)
    }
}
