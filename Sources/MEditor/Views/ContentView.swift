import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var showSidebar = AppSettings.shared.showSidebarOnLaunch
    @State private var showEditor = AppSettings.shared.showEditorOnLaunch
    @State private var showPreview = AppSettings.shared.showPreviewOnLaunch

    // Panel widths
    @State private var sidebarWidth: CGFloat = 220

    var body: some View {
        Group {
            if state.rootURL == nil {
                welcomeScreen
            } else {
                mainLayout
            }
        }
        .preferredColorScheme(state.themeStore.current.isDark ? .dark : .light)
        .sheet(isPresented: Binding(
            get: { state.showingQuickOpen },
            set: { state.showingQuickOpen = $0 }
        )) {
            QuickOpenSheet()
                .environment(state)
        }
        .sheet(isPresented: Binding(
            get: { state.showingTemplatePicker },
            set: { state.showingTemplatePicker = $0 }
        )) {
            TemplatePickerSheet(store: state.templateStore) { template in
                state.createFromTemplate(template)
            }
            .environment(state)
        }
        .alert(L("template.saveTitle"), isPresented: Binding(
            get: { state.showingSaveTemplate },
            set: { state.showingSaveTemplate = $0 }
        )) {
            TextField(L("template.namePlaceholder"), text: Binding(
                get: { state.saveTemplateName },
                set: { state.saveTemplateName = $0 }
            ))
            Button(L("common.save")) {
                state.saveCurrentAsTemplate(name: state.saveTemplateName)
                state.saveTemplateName = ""
                state.showingSaveTemplate = false
            }
            Button(L("common.cancel"), role: .cancel) {
                state.saveTemplateName = ""
                state.showingSaveTemplate = false
            }
        } message: {
            Text(L("template.saveMessage"))
        }
        .alert(L("alert.errorTitle"), isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button(L("common.ok")) { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
        .alert(L("alert.saveChangesTitle"), isPresented: Binding(
            get: { state.showingCloseConfirmation },
            set: { if !$0 { state.showingCloseConfirmation = false; state.pendingCloseTab = nil } }
        )) {
            Button(L("common.save"), role: .none) { state.confirmCloseTab(save: true) }
            Button(L("alert.dontSave"), role: .destructive) { state.confirmCloseTab(save: false) }
            Button(L("common.cancel"), role: .cancel) { state.showingCloseConfirmation = false; state.pendingCloseTab = nil }
        } message: {
            if let tab = state.pendingCloseTab {
                Text(L("alert.saveChangesMessage", tab.name))
            }
        }
        .alert(L("alert.fileChanged"), isPresented: Binding(
            get: { state.showingReloadPrompt },
            set: { if !$0 { state.dismissReloadPrompt() } }
        )) {
            Button(L("alert.reload"), role: .none) { state.reloadExternallyModifiedTab() }
            Button(L("alert.keepMine"), role: .cancel) { state.dismissReloadPrompt() }
        } message: {
            if let tab = state.externallyModifiedTab {
                Text(L("alert.fileChangedMessage", tab.name))
            }
        }
        .alert(L("alert.largeFile"), isPresented: Binding(
            get: { state.showingLargeFileWarning },
            set: { if !$0 { state.showingLargeFileWarning = false; state.pendingLargeFile = nil } }
        )) {
            Button(L("alert.openAnyway"), role: .none) {
                if let item = state.pendingLargeFile {
                    state.showingLargeFileWarning = false
                    state.pendingLargeFile = nil
                    state.openFileUnchecked(item)
                }
            }
            Button(L("common.cancel"), role: .cancel) {
                state.showingLargeFileWarning = false
                state.pendingLargeFile = nil
            }
        } message: {
            if let item = state.pendingLargeFile {
                Text(L("alert.largeFileMessage", item.name))
            }
        }
    }

    private var welcomeScreen: some View {
        WelcomeView(onOpenFolder: openFolder)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDrop(providers)
            }
    }

    private var mainLayout: some View {
        let theme = state.themeStore.current
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                if showSidebar {
                    sidebarColumn
                        .frame(width: sidebarWidth)
                    draggableDivider(width: $sidebarWidth, minValue: 160, maxValue: 360)
                }

                VStack(spacing: 0) {
                    if !state.openTabs.isEmpty {
                        EditorTabBar()
                    }
                    HStack(spacing: 0) {
                        if showEditor {
                            editorColumn
                                .frame(maxWidth: .infinity)
                        }

                        if showEditor && showPreview {
                            theme.separator
                                .frame(width: 1)
                        }

                        if showPreview {
                            previewColumn
                                .frame(maxWidth: .infinity)
                        }

                        if !showEditor && !showPreview {
                            theme.editorBackground
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            statusBar
        }
        .background(theme.editorBackground)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                sidebarToggleBtn
            }
            ToolbarItemGroup(placement: .primaryAction) {
                shareButton
                exportMenu
                themeMenu
                editorToggleBtn
                previewToggleBtn
            }
        }
    }

    private var sidebarColumn: some View {
        FileSidebar()
            .background(state.themeStore.current.chromeBackground)
    }

    private var editorColumn: some View {
        EditorView()
            .background(state.themeStore.current.editorBackground)
    }

    private var previewColumn: some View {
        PreviewPanel()
            .background(state.themeStore.current.editorBackground)
    }

    private var sidebarToggleBtn: some View {
        Button {
            showSidebar.toggle()
        } label: {
            Image(systemName: "sidebar.left")
        }
        .help(showSidebar ? L("tooltip.hideSidebar") : L("tooltip.showSidebar"))
        .keyboardShortcut("b", modifiers: .command)
    }

    private var previewToggleBtn: some View {
        Button {
            showPreview.toggle()
        } label: {
            Image(systemName: "sidebar.right")
        }
        .help(showPreview ? L("tooltip.hidePreview") : L("tooltip.showPreview"))
        .keyboardShortcut("v", modifiers: [.command, .shift])
    }

    private var editorToggleBtn: some View {
        Button {
            showEditor.toggle()
        } label: {
            Image(systemName: "doc.text")
        }
        .help(showEditor ? L("tooltip.hideEditor") : L("tooltip.showEditor"))
        .keyboardShortcut("m", modifiers: [.command, .shift])
    }

    @State private var showSharePopover = false

    private var shareButton: some View {
        Button {
            let server = state.shareServer
            if server.isRunning {
                server.stop()
            } else {
                server.rootURL = state.rootURL
                server.allowedFiles = state.openTabs.map(\.url)
                server.start(preferredPort: AppSettings.shared.sharePort)
            }
        } label: {
            Image(systemName: state.shareServer.isRunning ? "wifi" : "wifi.slash")
        }
        .help(state.shareServer.isRunning ? L("share.stopWithURL", state.shareServer.shareURL) : L("share.viaLAN"))
        .popover(isPresented: Binding(
            get: { state.shareServer.isRunning && showSharePopover },
            set: { showSharePopover = $0 }
        )) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L("share.active"))
                    .font(.system(size: 12, weight: .semibold))
                if let tab = state.selectedTab,
                   let url = state.shareServer.shareURLForFile(tab.url) {
                    Text(L("share.currentFile"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(url)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                    Button(L("share.copyURL")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url, forType: .string)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                Divider()
                Button(L("share.stop")) {
                    state.shareServer.stop()
                    showSharePopover = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)
        }
        .onChange(of: state.shareServer.isRunning) { _, isRunning in
            showSharePopover = isRunning
        }
    }

    private var themeMenu: some View {
        ToolbarIconMenuButton(
            systemName: "paintpalette",
            size: 13,
            items: PreviewTheme.allCases.enumerated().map { idx, theme in
                (title: (state.themeStore.current == theme ? "✓ " : "  ") + theme.displayName,
                 action: { state.themeStore.current = theme })
            }
        )
        .frame(width: 24, height: 22)
        .help(L("theme.title"))
    }

    private var exportMenu: some View {
        let isHTML = state.previewMode == .html
        let items: [(String, () -> Void)] = isHTML
            ? [
                (L("export.markdown"), { performExport(.markdown) }),
                (L("export.pdf"), { performExport(.pdf) }),
                (L("export.image"), { performExport(.image) })
            ]
            : [
                (L("export.html"), { performExport(.html) }),
                (L("export.pdf"), { performExport(.pdf) }),
                (L("export.image"), { performExport(.image) })
            ]
        return ToolbarIconMenuButton(
            systemName: "square.and.arrow.up",
            size: 13,
            items: items,
            isDisabled: !state.previewExporter.isExportAvailable
        )
        .frame(width: 24, height: 22)
        .help(L("export.title"))
    }

    private func performExport(_ format: PreviewExporter.ExportFormat) {
        let suggestedName = state.selectedTab?.url.deletingPathExtension().lastPathComponent ?? "Untitled"
        state.previewExporter.export(format: format, suggestedName: suggestedName) { result in
            if case .failure(let error) = result {
                state.setError(error.localizedDescription)
            }
        }
    }

    // MARK: - Draggable Divider

    private func draggableDivider(
        width: Binding<CGFloat>,
        minValue: CGFloat,
        maxValue: CGFloat,
        invert: Bool = false
    ) -> some View {
        Color(nsColor: .separatorColor).opacity(0.4)
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 5)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() }
                        else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .local)
                            .onChanged { value in
                                let delta = value.translation.width
                                let newWidth = width.wrappedValue + (invert ? -delta : delta)
                                width.wrappedValue = max(minValue, min(maxValue, newWidth))
                            }
                    )
            }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 10) {
            if let tab = state.selectedTab {
                Text("Ln \(state.cursorLine), Col \(state.cursorColumn)")
                    .fixedSize()
                Text("·")
                Text("\(wordCount(tab.content)) words")
                Text("·")
                Text(state.currentFileSize)
                Text("·")
                Text("UTF-8")
            }
            Spacer()
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .frame(height: 20)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }

    private func wordCount(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    // MARK: - Actions

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = L("panel.chooseFolder")
        if panel.runModal() == .OK, let url = panel.url {
            state.openFolder(url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            DispatchQueue.main.async {
                if isDir.boolValue {
                    state.openFolder(url)
                } else {
                    state.openFile(FileItem(url: url, isDirectory: false))
                }
            }
        }
        return true
    }
}
