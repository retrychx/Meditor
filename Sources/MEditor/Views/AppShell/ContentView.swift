import SwiftUI

@MainActor
struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var workspaceUI = WorkspaceUIState()
    @State private var settings = AppSettings.shared
    /// 窗口内容区实测宽度（GeometryReader 回传），用于动态计算 tab 条宽度。
    @State private var windowContentWidth: CGFloat = 1280

    /// toolbar 里 tab 条的宽度：窗口宽 - 侧栏（可见时） - 系统开关/标题间距/右边距。
    private var tabsStripWidth: CGFloat {
        let sidebar: CGFloat = workspaceUI.showsSidebarInLayout ? workspaceUI.clampedSidebarWidth : 0
        return max(240, windowContentWidth - sidebar - 150)
    }

    var body: some View {
        Group {
            if state.rootURL == nil {
                welcomeScreen
            } else {
                mainLayout
            }
        }
        .preferredColorScheme(state.themeStore.current.isDark ? .dark : .light)
        // Global accent — the AI-assistant accent style is applied app-wide so
        // every control (create buttons, pickers, toggles, selection highlights)
        // honors the user's choice (system blue vs shadcn mono).
        .tint(AIAccentStyle.current(settings).fill(state.themeStore.current))
        .environment(workspaceUI)
        .background(WindowConfigurator())
        // tab 栏进系统 toolbar——顶部只有一条横带：左端系统侧栏开关，接着是文件 tab。
        // 注意：toolbar 按视图理想宽度排布，ScrollView 会把所有 tab 的宽度加起来
        // 要求——超宽会被整体塞进 ">>" 溢出菜单；但定死宽度又会在右侧留一大块空。
        // 所以宽度跟随窗口实测：窗口宽 - 侧栏宽 - 开关与边距。
        .toolbar {
            // automatic（跟随系统侧栏开关之后左对齐）而不是 principal（居中），
            // 否则 tab 条悬浮在横带中央、左右都是空当，看起来很奇怪。
            ToolbarItem(placement: .automatic) {
                EditorTabBar()
                    .frame(width: tabsStripWidth)
                    .environment(state)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { windowContentWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, w in windowContentWidth = w }
            }
        )
        .overlayPreferenceValue(SettingsAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if state.showingSettings {
                    let rect: CGRect = anchor.map { proxy[$0] }
                        ?? CGRect(x: proxy.size.width / 2, y: proxy.size.height, width: 0, height: 0)
                    SettingsHeroOverlay(originRect: rect, containerSize: proxy.size)
                        .environment(state)
                        .environment(workspaceUI)
                }
            }
        }
        .overlayPreferenceValue(AIAssistantAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if state.showingAIAssistant {
                    let rect: CGRect = anchor.map { proxy[$0] }
                        ?? CGRect(x: proxy.size.width, y: proxy.size.height, width: 0, height: 0)
                    AIAssistantHeroOverlay(originRect: rect, containerSize: proxy.size)
                        .environment(state)
                        .environment(workspaceUI)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { state.showingBeautifySheet },
            set: { state.showingBeautifySheet = $0 }
        )) {
            BeautifySheet()
                .environment(state)
                .environment(settings)
                .presentationBackground(.regularMaterial)
        }
        .sheet(isPresented: Binding(
            get: { state.showingQuickOpen },
            set: { state.showingQuickOpen = $0 }
        )) {
            QuickOpenSheet()
                .environment(state)
                .environment(workspaceUI)
                .presentationBackground(.regularMaterial)
        }
        .sheet(isPresented: Binding(
            get: { state.showingTemplatePicker },
            set: { state.showingTemplatePicker = $0 }
        )) {
            TemplatePickerSheet(store: state.templateManager.store) { template in
                state.createFromTemplate(template)
            }
            .environment(state)
            .presentationBackground(.regularMaterial)
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
        // Close Project confirmation — prevents accidental data loss from the menu item.
        .confirmationDialog(
            "Close Project?",
            isPresented: Binding(
                get: { state.showingCloseProjectConfirmation },
                set: { state.showingCloseProjectConfirmation = $0 }
            ),
            titleVisibility: .visible
        ) {
            Button("Close", role: .destructive) {
                state.showingCloseProjectConfirmation = false
                state.rootURL = nil
                state.openTabs.removeAll()
                state.selectedTabID = nil
                state.fileTreeManager.clear()
                state.clearPreview()
            }
            Button("Cancel", role: .cancel) {
                state.showingCloseProjectConfirmation = false
            }
        } message: {
            Text("All open tabs will be closed. Unsaved changes will be lost.")
        }
        // Diff review is now inline inside AppShell's document area (no overlay).
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
        AppShell(workspaceUI: workspaceUI, onExport: performExport) {
            sidebarColumn
        } editor: {
            editorColumn
        } preview: {
            previewColumn
        }
        .toastOverlay(message: Binding(
            get: { state.toastMessage },
            set: { state.toastMessage = $0 }
        ))
        .claudeFilePromptOverlay(prompt: Binding(
            get: { state.claudeFilePrompt },
            set: { state.claudeFilePrompt = $0 }
        ))
    }

    private var sidebarColumn: some View {
        FileSidebar()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editorColumn: some View {
        EditorView()
            .background(state.themeStore.current.editorBackground)
    }

    private var previewColumn: some View {
        PreviewPanel()
            .background(state.themeStore.current.editorBackground)
    }

    private func performExport(_ format: PreviewExporter.ExportFormat) {
        let suggestedName = state.selectedTab?.url.deletingPathExtension().lastPathComponent ?? "Untitled"
        state.previewExporter.export(format: format, suggestedName: suggestedName) { result in
            if case .failure(let error) = result {
                state.setError(error.localizedDescription)
            }
        }
    }

    // MARK: - Actions

    private func openFolder() {
        Task {
            if let url = await state.filePickerService.pickFolder(message: L("panel.chooseFolder")) {
                state.openFolder(url)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            let isDirectory = isDir.boolValue
            DispatchQueue.main.async {
                if isDirectory {
                    state.openFolder(url)
                } else {
                    state.openFile(FileItem(url: url, isDirectory: false))
                }
            }
        }
        return true
    }
}
