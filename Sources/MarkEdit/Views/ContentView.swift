import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var showSidebar = true
    @State private var showEditor = true
    @State private var showPreview = true

    var body: some View {
        if state.rootURL == nil {
            welcomeScreen
        } else {
            mainLayout
        }
    }

    // MARK: - Welcome Screen

    private var welcomeScreen: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("MarkEdit")
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
        HStack(spacing: 0) {
            if showSidebar { sidebarColumn; divider }
            if showEditor { editorColumn; if showPreview { divider } }
            if showPreview { previewColumn }
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
        .frame(width: 220)
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
            withAnimation { showSidebar.toggle() }
        } label: {
            Image(systemName: "sidebar.left")
                .symbolVariant(showSidebar ? .fill : .none)
        }
        .help(showSidebar ? "Hide Sidebar" : "Show Sidebar")
    }

    private var editorToggleBtn: some View {
        Button {
            withAnimation { showEditor.toggle() }
        } label: {
            Image(systemName: "doc.text")
                .symbolVariant(showEditor ? .fill : .none)
        }
        .help(showEditor ? "Hide Editor" : "Show Editor")
    }

    private var previewToggleBtn: some View {
        Button {
            withAnimation { showPreview.toggle() }
        } label: {
            Image(systemName: "sidebar.right")
                .symbolVariant(showPreview ? .fill : .none)
        }
        .help(showPreview ? "Hide Preview" : "Show Preview")
    }

    // MARK: - Shared

    private var divider: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
    }

    // MARK: - Actions

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a project folder"
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

// MARK: - Panel Label

private struct PanelLabel: View {
    let title: String
    let icon: String

    init(_ title: String, icon: String) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Visual Effect (Blur)

private struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .withinWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}
