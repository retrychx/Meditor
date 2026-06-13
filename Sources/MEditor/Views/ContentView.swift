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
            TemplatePickerSheet(store: state.templateManager.store) { template in
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
        WelcomeView(
            onOpenFolder: openFolder,
            onOpenRecent: { url in state.openFolder(url) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Background bleeds into titlebar — no visible separator
        .background(Color(nsColor: .textBackgroundColor), ignoresSafeAreaEdges: .top)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    private var mainLayout: some View {
        let theme = state.themeStore.current
        return VStack(spacing: 0) {
            // ── Unified top bar (ONE row, full window width) ──
            // Left section matches sidebar width; right section = tabs + actions.
            // This is the only chrome row — no separate sidebar header.
            HStack(spacing: 0) {
                if showSidebar {
                    // Sidebar portion of the top bar
                    sidebarTopBar
                        .frame(width: sidebarWidth)
                    // Hairline divider between sidebar and tab sections
                    theme.separator.frame(width: 1)
                }
                // Tab bar + actions (right portion)
                // Actions group has fixed width; tabs fill the rest and clip
                HStack(spacing: 0) {
                    if !state.openTabs.isEmpty {
                        EditorTabBar()
                            .frame(maxWidth: .infinity)
                            .clipped()
                    } else {
                        Color.clear
                            .frame(maxWidth: .infinity)
                    }
                    // Action buttons: fixed width, never pushed by tabs
                    editorActionButtons
                        .fixedSize(horizontal: true, vertical: false)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 38)
            .background {
                VisualEffect(material: .titlebar, blendingMode: .withinWindow)
                    .ignoresSafeArea(edges: .top)
            }
            .overlay(alignment: .bottom) {
                theme.separator.frame(height: 1).opacity(0.5)
            }

            // ── Content area (sidebar + editor) ──
            HStack(spacing: 0) {
                if showSidebar {
                    sidebarColumn
                        .frame(width: sidebarWidth)
                    draggableDivider(width: $sidebarWidth, minValue: 160, maxValue: 360)
                }

                HStack(spacing: 0) {
                    if showEditor {
                        editorColumn
                            .frame(maxWidth: .infinity)
                    }
                    if showEditor && showPreview {
                        theme.separator.frame(width: 1)
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            statusBar
        }
        .background(theme.editorBackground)
    }

    /// Left portion of the unified top bar (matches sidebar width).
    private var sidebarTopBar: some View {
        let theme = state.themeStore.current
        return HStack(spacing: 0) {
            // Traffic light clearance
            Color.clear.frame(width: 76)

            if let rootURL = state.rootURL {
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange.opacity(0.7))
                    Text(rootURL.lastPathComponent.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .kerning(0.4)
                        .lineLimit(1)
                }
            }

            Spacer()

            ChromeButton(systemName: "sidebar.left", help: L("tooltip.hideSidebar")) {
                withAnimation(DS.Motion.springFast) { showSidebar = false }
            }
            .keyboardShortcut("b", modifiers: .command)
            .padding(.trailing, 4)
        }
        .frame(maxHeight: .infinity)
        .background(VisualEffect(material: .titlebar, blendingMode: .withinWindow))
    }

    private var sidebarColumn: some View {
        FileSidebar()
            // macOS sidebar material: frosted glass that reads env colors
            .background(VisualEffect(material: .sidebar, blendingMode: .behindWindow))
    }

    private var editorColumn: some View {
        EditorView()
            .background(state.themeStore.current.editorBackground)
    }

    private var previewColumn: some View {
        PreviewPanel()
            .background(state.themeStore.current.editorBackground)
    }

    // MARK: - Inline action buttons (replaces NSToolbar)

    private var editorActionButtons: some View {
        HStack(spacing: 2) {
            // Show sidebar toggle when sidebar is hidden
            if !showSidebar {
                ChromeButton(
                    systemName: "sidebar.left",
                    help: L("tooltip.showSidebar"),
                    isActive: false
                ) {
                    withAnimation(DS.Motion.springFast) { showSidebar = true }
                }
                .keyboardShortcut("b", modifiers: .command)

                Divider().frame(height: 14).padding(.horizontal, 2)
            }

            // Share
            ChromeButton(
                systemName: state.shareServer.isRunning ? "wifi" : "wifi.slash",
                help: state.shareServer.isRunning ? L("share.stopWithURL", state.shareServer.shareURL) : L("share.viaLAN"),
                isActive: state.shareServer.isRunning
            ) {
                if state.shareServer.isRunning {
                    state.shareServer.stop()
                } else {
                    state.shareServer.start(rootURL: state.rootURL, openTabs: state.openTabs, preferredPort: AppSettings.shared.sharePort)
                }
            }
            .popover(isPresented: Binding(
                get: { state.shareServer.isRunning && showSharePopover },
                set: { showSharePopover = $0 }
            )) {
                SharePopoverContent(server: state.shareServer, selectedTab: state.selectedTab) {
                    state.shareServer.stop(); showSharePopover = false
                }
            }
            .onChange(of: state.shareServer.isRunning) { _, running in showSharePopover = running }

            // Export
            ChromeMenuButton(
                systemName: "square.and.arrow.up",
                help: L("export.title"),
                isDisabled: !state.previewExporter.isExportAvailable,
                items: exportItems
            )

            // Theme
            ChromeMenuButton(
                systemName: "paintpalette",
                help: L("theme.title"),
                items: PreviewTheme.allCases.map { t in
                    (
                        title: (state.themeStore.current == t ? "✓ " : "  ") + t.displayName,
                        action: { state.themeStore.current = t }
                    )
                }
            )

            Divider().frame(height: 14).padding(.horizontal, 2)

            // Editor / Preview toggles
            ChromeButton(
                systemName: "doc.text",
                help: showEditor ? L("tooltip.hideEditor") : L("tooltip.showEditor"),
                isActive: showEditor
            ) { showEditor.toggle() }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            ChromeButton(
                systemName: "sidebar.right",
                help: showPreview ? L("tooltip.hidePreview") : L("tooltip.showPreview"),
                isActive: showPreview
            ) { showPreview.toggle() }
            .keyboardShortcut("v", modifiers: [.command, .shift])
        }
        .padding(.trailing, 8)
    }

    private var exportItems: [(title: String, action: () -> Void)] {
        let isHTML = state.previewMode == .html
        return isHTML
            ? [
                (L("export.markdown"), { performExport(.markdown) }),
                (L("export.pdf"),      { performExport(.pdf) }),
                (L("export.image"),    { performExport(.image) })
              ]
            : [
                (L("export.html"),  { performExport(.html) }),
                (L("export.pdf"),   { performExport(.pdf) }),
                (L("export.image"), { performExport(.image) })
              ]
    }

    @State private var showSharePopover = false

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
        let theme = state.themeStore.current
        return HStack(spacing: 0) {
            if let tab = state.selectedTab {
                statusItem("\(state.cursorLine):\(state.cursorColumn)", icon: "character.cursor.ibeam", theme: theme)
                statusDivider(theme)
                statusItem("\(wordCount(tab.content)) words", theme: theme)
                statusDivider(theme)
                statusItem(state.currentFileSize, theme: theme)
                statusDivider(theme)
                let lang = FileTypeConfiguration.shared
                    .editorLanguage(for: tab.url.pathExtension.lowercased())?.rawValue
                    .capitalized ?? "Text"
                statusItem(lang, theme: theme)
            }
            Spacer()
        }
        .frame(height: 24)
        .background(theme.chromeBackground)
        .overlay(alignment: .top) {
            theme.separator.frame(height: 1)
        }
    }

    private func statusDivider(_ theme: PreviewTheme) -> some View {
        theme.separator
            .frame(width: 1, height: 12)
            .padding(.horizontal, 8)
    }

    private func statusItem(_ text: String, icon: String? = nil, theme: PreviewTheme) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(theme.foreground.opacity(0.35))
            }
            Text(text)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(theme.foreground.opacity(0.4))
        }
        .padding(.horizontal, 10)
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
