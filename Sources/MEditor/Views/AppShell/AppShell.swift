import SwiftUI

struct AppShell<Sidebar: View, Editor: View, Preview: View>: View {
    @Environment(AppState.self) private var state
    @Bindable var workspaceUI: WorkspaceUIState

    /// Shared namespace so the focus toggle can "fly" (hero / matchedGeometry)
    /// between the toolbar and its floating position over the document.
    @Namespace private var focusNS
    /// Shared namespace so the sidebar toggle flies between the sidebar card
    /// (expanded) and the top-left toolbar (collapsed).
    @Namespace private var sidebarNS
    /// Transient hint shown when entering focus mode (Craft-style).
    @State private var showFocusHint = false

    let onExport: (PreviewExporter.ExportFormat) -> Void
    private let sidebar: () -> Sidebar
    private let editor: () -> Editor
    private let preview: () -> Preview

    init(
        workspaceUI: WorkspaceUIState,
        onExport: @escaping (PreviewExporter.ExportFormat) -> Void,
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder editor: @escaping () -> Editor,
        @ViewBuilder preview: @escaping () -> Preview
    ) {
        self.workspaceUI = workspaceUI
        self.onExport = onExport
        self.sidebar = sidebar
        self.editor = editor
        self.preview = preview
    }

    var body: some View {
        let theme = state.themeStore.current
        HStack(spacing: 0) {
            if workspaceUI.showsSidebarInLayout {
                ZStack {
                    // Neutral canvas that the sidebar card floats on — matches the
                    // tab bar's chrome (unselected-tab) background so the sidebar
                    // and toolbar areas read as one coherent surface.
                    theme.chromeBackground
                        .ignoresSafeArea()

                    // Floating sidebar card — rounded corners, translucent
                    // material fill and a soft drop shadow, inset from the window
                    // edges. This detached / hovering look is the "floating" feel
                    // of the Finder & Craft sidebars.
                    sidebar()
                        // Inner top inset so the first row clears the traffic
                        // lights, which now sit *inside* the card.
                        .padding(.top, 40)
                        .scrollContentBackground(.hidden)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.regularMaterial)
                        )
                        // Soft vertical tint over the material — mimics the
                        // luminance gradient of Craft's native sidebar vibrancy.
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: theme.isDark
                                            ? [Color.white.opacity(0.06), Color.clear,
                                               Color.black.opacity(0.05)]
                                            : [Color.white.opacity(0.45), Color.clear,
                                               Color.black.opacity(0.035)],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        // Hairline border with a top-lit highlight → a subtle
                        // glowing rim that makes the card read as "floating".
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: theme.isDark
                                            ? [Color.white.opacity(0.18),
                                               Color.white.opacity(0.04)]
                                            : [Color.white.opacity(0.95),
                                               Color.white.opacity(0.30)],
                                        startPoint: .top, endPoint: .bottom
                                    ),
                                    lineWidth: 1
                                )
                                .blendMode(.plusLighter)
                        )
                        .shadow(color: .black.opacity(theme.isDark ? 0.45 : 0.16),
                                radius: 9, x: 0, y: 2)
                        // Very soft outer glow — kept faint so it doesn't wash the
                        // thin canvas margins (which must match the tab-bar chrome).
                        .shadow(color: Color.white.opacity(theme.isDark ? 0.05 : 0.18),
                                radius: 4, x: 0, y: 0)
                        .padding(.leading, 9)
                        .padding(.trailing, 5)
                        .padding(.top, 6)
                        .padding(.bottom, 10)
                        // Reach up under the transparent titlebar so the system
                        // traffic lights land *inside* the card (Craft uses the
                        // standard lights too — it just extends the material up).
                        .ignoresSafeArea(.container, edges: .top)
                }
                .frame(width: workspaceUI.clampedSidebarWidth)
                .frame(maxHeight: .infinity)
                .background(NonDraggableView())
                .transition(.move(edge: .leading).combined(with: .opacity))

                DraggableDivider(
                    width: Binding(
                        get: { workspaceUI.clampedSidebarWidth },
                        set: { workspaceUI.setSidebarWidth($0) }
                    ),
                    minValue: 220,
                    maxValue: 320
                )
                .transition(.opacity)
            }

            VStack(spacing: 0) {
                if workspaceUI.isFocusMode {
                    // Immersive view: hide the toolbar, keep a thin draggable strip
                    // so the window stays movable and traffic lights have clearance.
                    Color.clear.frame(height: 38)
                } else {
                    TopToolbar(workspaceUI: workspaceUI, onExport: onExport, focusNS: focusNS)
                }

                HStack(spacing: 0) {
                    ZStack {
                        theme.windowBackground
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        HStack(spacing: 0) {
                            if workspaceUI.showsEditor {
                                editor()
                                    .frame(maxWidth: .infinity)
                            }

                            if workspaceUI.showsEditor && workspaceUI.showsPreview {
                                theme.separator
                                    .opacity(theme.isDark ? 0.36 : 0.2)
                                    .frame(width: 1)
                            }

                            if workspaceUI.showsPreview {
                                preview()
                                    .frame(maxWidth: .infinity)
                            }

                            if !workspaceUI.hasVisibleWorkspacePane {
                                theme.windowBackground
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Focus toggle flies here (hero) when focus mode is on.
                    .overlay(alignment: .topTrailing) {
                        if workspaceUI.isFocusMode {
                            FocusToggleButton(workspaceUI: workspaceUI)
                                .matchedGeometryEffect(id: "focusToggle", in: focusNS)
                                .padding(.top, 12)
                                .padding(.trailing, 14)
                        }
                    }
                    .overlay(alignment: .top) {
                        if workspaceUI.isFocusMode && showFocusHint {
                            FocusHintToast()
                                .padding(.top, 14)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }

                    if !workspaceUI.isFocusMode {
                        RightPanelRail(workspaceUI: workspaceUI)
                    }

                    if workspaceUI.showsRightPanelInLayout {
                        RightPanelHost(workspaceUI: workspaceUI)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !workspaceUI.isFocusMode {
                    StatusBarHost()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Opaque canvas lives ONLY on the editor/right side so the sidebar
            // column stays transparent and the `.behindWindow` sidebar material
            // can sample the desktop — that's what gives the floating vibrancy.
            .background(theme.windowBackground)
            .onChange(of: workspaceUI.isFocusMode) { _, focused in
                if focused {
                    showFocusHint = true
                    Task {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        withAnimation(DS.Motion.fast) { showFocusHint = false }
                    }
                } else {
                    showFocusHint = false
                }
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(theme.windowBackground)
        .background(keyboardShortcutHost)
        .environment(\.sidebarToggleNS, sidebarNS)
    }

    private var keyboardShortcutHost: some View {
        Group {
            Button("") {
                withAnimation(DS.Motion.panel) {
                    workspaceUI.toggleSidebar()
                }
            }
            .keyboardShortcut("b", modifiers: [.command, .option])

            Button("") {
                withAnimation(DS.Motion.fast) {
                    workspaceUI.rightPanel = .search
                }
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button("") {
                withAnimation(DS.Motion.fast) {
                    if workspaceUI.isFocusMode {
                        workspaceUI.isFocusMode = false
                    } else {
                        workspaceUI.closeRightPanel()
                    }
                }
            }
            .keyboardShortcut(.escape, modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

private struct TopToolbar: View {
    @Environment(AppState.self) private var state
    @Environment(\.sidebarToggleNS) private var sidebarNS
    @Bindable var workspaceUI: WorkspaceUIState
    let onExport: (PreviewExporter.ExportFormat) -> Void
    let focusNS: Namespace.ID

    @State private var showSharePopover = false

    private var theme: PreviewTheme { state.themeStore.current }

    var body: some View {
        HStack(spacing: 0) {
            if !workspaceUI.showsSidebarInLayout {
                // Reserve room for the traffic lights, then a show-sidebar button
                // at the very top-left (Craft-style), to the left of the tabs.
                Color.clear.frame(width: 84, height: 1)
                ChromeButton(
                    systemName: "sidebar.left",
                    help: L("tooltip.showSidebar")
                ) {
                    withAnimation(DS.Motion.panel) { workspaceUI.showsSidebar = true }
                }
                .heroMatch("sidebarToggle", in: sidebarNS)
                .padding(.trailing, 2)
            }

            // Tab bar
            tabZone
                .frame(maxWidth: .infinity)

            // Right: action buttons
            ToolbarActionGroup(
                workspaceUI: workspaceUI,
                showSharePopover: $showSharePopover,
                onExport: onExport,
                focusNS: focusNS
            )
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(height: 44)
        .background(theme.chromeBackground, ignoresSafeAreaEdges: .top)
        .background(NonDraggableView())
        .overlay(alignment: .bottom) {
            theme.separator.opacity(theme.isDark ? 0.3 : 0.12).frame(height: 1)
        }
    }

    @ViewBuilder
    private var tabZone: some View {
        if !state.openTabs.isEmpty {
            EditorTabBar()
                .padding(.leading, 0)
                .padding(.trailing, 4)
                .clipped()
        } else {
            Color.clear
        }
    }
}

private struct ToolbarActionGroup: View {
    @Environment(AppState.self) private var state
    @Bindable var workspaceUI: WorkspaceUIState
    @Binding var showSharePopover: Bool
    let onExport: (PreviewExporter.ExportFormat) -> Void
    let focusNS: Namespace.ID

    var body: some View {
        HStack(spacing: 2) {
            ChromeButton(
                systemName: "scope",
                help: L("tooltip.focusMode"),
                isActive: workspaceUI.isFocusMode
            ) {
                withAnimation(DS.Motion.springFast) { workspaceUI.toggleFocusMode() }
            }
            .matchedGeometryEffect(id: "focusToggle", in: focusNS)

            ChromeMenuButton(
                systemName: "square.and.arrow.up",
                help: L("export.title"),
                isDisabled: !state.previewExporter.isExportAvailable,
                items: exportItems
            )

            Divider().frame(height: 14).padding(.horizontal, 2)

            ChromeButton(
                systemName: "doc.text",
                help: workspaceUI.showsEditor ? L("tooltip.hideEditor") : L("tooltip.showEditor"),
                isActive: workspaceUI.showsEditor
            ) { workspaceUI.toggleEditor() }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            ChromeButton(
                systemName: "sidebar.right",
                help: workspaceUI.showsPreview ? L("tooltip.hidePreview") : L("tooltip.showPreview"),
                isActive: workspaceUI.showsPreview
            ) { workspaceUI.togglePreview() }
            .keyboardShortcut("v", modifiers: [.command, .shift])
        }
        .padding(.trailing, 8)
    }

    private var exportItems: [(title: String, action: () -> Void)] {
        let isHTML = state.previewMode == .html
        return isHTML
            ? [(L("export.markdown"), { onExport(.markdown) }), (L("export.pdf"), { onExport(.pdf) }), (L("export.image"), { onExport(.image) })]
            : [(L("export.html"), { onExport(.html) }), (L("export.pdf"), { onExport(.pdf) }), (L("export.image"), { onExport(.image) })]
    }
}

private struct StatusBarHost: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let theme = state.themeStore.current
        HStack(spacing: 0) {
            if let tab = state.selectedTab {
                statusChip("\(state.cursorLine):\(state.cursorColumn)", icon: "character.cursor.ibeam")
                statusDivider(theme)
                statusChip("\(wordCount(tab.content))w")
                statusDivider(theme)
                statusChip(state.currentFileSize)
                statusDivider(theme)

                let lang = FileTypeConfiguration.shared
                    .editorLanguage(for: tab.url.pathExtension.lowercased())?.rawValue
                    .capitalized ?? "Text"
                statusChip(lang)

                if tab.isModified {
                    statusDivider(theme)
                    HStack(spacing: 3) {
                        Circle().fill(Color.orange).frame(width: 5, height: 5)
                        Text(L("statusBar.modified"))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                }
            }

            Spacer()
        }
        .frame(height: 22)
        .background(theme.chromeBackground)
        .overlay(alignment: .top) {
            Color.black.opacity(0.06).frame(height: 1)
        }
    }

    private func statusDivider(_ theme: PreviewTheme) -> some View {
        theme.separator
            .frame(width: 1, height: 10)
            .opacity(0.5)
            .padding(.horizontal, 6)
    }

    private func statusChip(_ text: String, icon: String? = nil) -> some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            Text(text)
                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
    }

    private func wordCount(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(
            in: text.startIndex...,
            options: [.byWords, .substringNotRequired]
        ) { _, _, _, _ in
            count += 1
        }
        return count
    }
}


// MARK: - Focus mode floating controls

/// Floating focus-mode toggle shown over the document in focus mode. Shares the
/// "focusToggle" matchedGeometry id with the toolbar's scope button so it flies
/// between the two positions (hero transition).
private struct FocusToggleButton: View {
    @Environment(AppState.self) private var state
    @Bindable var workspaceUI: WorkspaceUIState
    @State private var isHovered = false
    @State private var breathe = false

    var body: some View {
        let theme = state.themeStore.current
        Button {
            withAnimation(DS.Motion.springFast) { workspaceUI.toggleFocusMode() }
        } label: {
            Image(systemName: "scope")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(.regularMaterial)
                        .shadow(color: .black.opacity(theme.isDark ? 0.40 : 0.14),
                                radius: 5, x: 0, y: 1)
                )
                // Breathing accent halo — slow pulse that signals focus is active.
                .background(
                    Circle()
                        .fill(Color.accentColor)
                        .opacity(breathe ? 0.30 : 0.08)
                        .scaleEffect(breathe ? 1.55 : 1.08)
                        .blur(radius: 6)
                )
                .overlay(
                    Circle().strokeBorder(
                        Color.primary.opacity(isHovered ? 0.14 : 0.06), lineWidth: 1)
                )
                .scaleEffect(isHovered ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(L("tooltip.exitFocus"))
        .animation(DS.Motion.micro, value: isHovered)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }
}

/// Transient hint surfaced when entering focus mode (Craft-style).
private struct FocusHintToast: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let theme = state.themeStore.current
        HStack(spacing: 6) {
            Image(systemName: "scope")
                .font(.system(size: 11, weight: .medium))
            Text(L("focus.hint"))
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(theme.craftSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(theme.isDark ? 0.40 : 0.12),
                        radius: 6, x: 0, y: 2)
        )
    }
}


// MARK: - Shared hero namespace (sidebar toggle flies toolbar ↔ sidebar card)

private struct SidebarToggleNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var sidebarToggleNS: Namespace.ID? {
        get { self[SidebarToggleNamespaceKey.self] }
        set { self[SidebarToggleNamespaceKey.self] = newValue }
    }
}

extension View {
    /// Applies matchedGeometryEffect only when a namespace is available, so views
    /// in different subtrees can opt into a shared hero transition via environment.
    @ViewBuilder
    func heroMatch(_ id: String, in ns: Namespace.ID?) -> some View {
        if let ns {
            self.matchedGeometryEffect(id: id, in: ns)
        } else {
            self
        }
    }
}
