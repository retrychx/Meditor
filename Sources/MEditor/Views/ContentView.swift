import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var showSidebar = true
    @State private var showEditor = true
    @State private var showPreview = true

    // Panel widths
    @State private var sidebarWidth: CGFloat = 220
    @State private var previewWidth: CGFloat = 300

    var body: some View {
        Group {
            if state.rootURL == nil {
                welcomeScreen
            } else {
                mainLayout
            }
        }
        .alert("Error", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("OK") { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
        .alert("Save changes?", isPresented: Binding(
            get: { state.showingCloseConfirmation },
            set: { if !$0 { state.showingCloseConfirmation = false; state.pendingCloseTab = nil } }
        )) {
            Button("Save", role: .none) { state.confirmCloseTab(save: true) }
            Button("Don't Save", role: .destructive) { state.confirmCloseTab(save: false) }
            Button("Cancel", role: .cancel) { state.showingCloseConfirmation = false; state.pendingCloseTab = nil }
        } message: {
            if let tab = state.pendingCloseTab {
                Text("Save changes to \"\(tab.name)\" before closing?")
            }
        }
    }

    // MARK: - Welcome Screen

    private var welcomeScreen: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("MEditor")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Markdown & HTML Editor")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Open Folder\u{2026}") {
                openFolder()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
            Text("or drag a folder here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Main Layout

    private var mainLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if showSidebar {
                    sidebarColumn
                        .frame(width: sidebarWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    if showEditor {
                        draggableDivider(
                            width: $sidebarWidth,
                            minValue: 150,
                            maxValue: 400
                        )
                        .transition(.opacity)
                    }
                }
                if showEditor {
                    editorColumn
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)
                }
                if showPreview {
                    if showEditor {
                        draggableDivider(
                            width: $previewWidth,
                            minValue: 200,
                            maxValue: 600,
                            invert: true
                        )
                        .transition(.opacity)
                    }
                    previewColumn
                        .frame(
                            minWidth: 200,
                            idealWidth: previewWidth,
                            maxWidth: showEditor ? 600 : .infinity
                        )
                        .layoutPriority(showEditor ? 0 : 1)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: showSidebar)
            .animation(.easeInOut(duration: 0.2), value: showEditor)
            .animation(.easeInOut(duration: 0.2), value: showPreview)

            statusBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItemGroup {
                sidebarToggleBtn
                editorToggleBtn
                previewToggleBtn
            }
        }
    }

    // MARK: - Columns

    private var sidebarColumn: some View {
        VStack(spacing: 0) {
            PanelLabel("Files", icon: "folder")
            Divider()
            FileSidebar()
        }
        .background(VisualEffect(material: .sidebar))
    }

    private var editorColumn: some View {
        VStack(spacing: 0) {
            PanelLabel("Editor", icon: "doc.text")
            Divider()
            EditorView()
        }
    }

    private var previewColumn: some View {
        VStack(spacing: 0) {
            PanelLabel("Preview", icon: "eye")
            Divider()
            PreviewPanel()
        }
    }

    // MARK: - Toolbar Buttons

    private var sidebarToggleBtn: some View {
        Button {
            showSidebar.toggle()
        } label: {
            Image(systemName: "sidebar.left")
                .symbolVariant(showSidebar ? .fill : .none)
        }
        .help(showSidebar ? "Hide Sidebar" : "Show Sidebar")
    }

    private var editorToggleBtn: some View {
        Button {
            showEditor.toggle()
        } label: {
            Image(systemName: "doc.text")
                .symbolVariant(showEditor ? .fill : .none)
        }
        .help(showEditor ? "Hide Editor" : "Show Editor")
    }

    private var previewToggleBtn: some View {
        Button {
            showPreview.toggle()
        } label: {
            Image(systemName: "sidebar.right")
                .symbolVariant(showPreview ? .fill : .none)
        }
        .help(showPreview ? "Hide Preview" : "Show Preview")
    }

    // MARK: - Draggable Divider

    private func draggableDivider(
        width: Binding<CGFloat>,
        minValue: CGFloat,
        maxValue: CGFloat,
        invert: Bool = false
    ) -> some View {
        // Use 1px visible line but 6px hit target
        ZStack(alignment: .center) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)

            Rectangle()
                .fill(Color.clear)
                .frame(width: 6)
        }
        .contentShape(Rectangle())
        .frame(width: 6)
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

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            if state.openTabs.isEmpty {
                Text("No file open")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if let _ = state.selectedTab {
                Text("Ln \(state.cursorLine), Col \(state.cursorColumn)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Divider()
                    .frame(height: 12)
                Text(state.currentFileSize)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Divider()
                    .frame(height: 12)
                Text("UTF-8")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(Divider(), alignment: .top)
    }

    // MARK: - Actions

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a project folder"
        if panel.runModal() == .OK, let url = panel.url {
            state.beginAccessing(url)
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
