import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var workspaceUI = WorkspaceUIState()

    var body: some View {
        Group {
            if state.rootURL == nil {
                welcomeScreen
            } else {
                mainLayout
            }
        }
        .preferredColorScheme(state.themeStore.current.isDark ? .dark : .light)
        .environment(workspaceUI)
        .background(WindowConfigurator())
        .sheet(isPresented: Binding(
            get: { state.showingQuickOpen },
            set: { state.showingQuickOpen = $0 }
        )) {
            QuickOpenSheet()
                .environment(state)
                .environment(workspaceUI)
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
        AppShell(workspaceUI: workspaceUI, onExport: performExport) {
            sidebarColumn
        } editor: {
            editorColumn
        } preview: {
            previewColumn
        }
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
