import SwiftUI

struct AppShell<Sidebar: View, Editor: View, Preview: View>: View {
    @Environment(AppState.self) private var state
    @Environment(\.controlActiveState) private var controlActiveState
    @Bindable var workspaceUI: WorkspaceUIState

    /// Shared namespace so the focus toggle can "fly" (hero / matchedGeometry)
    /// between the toolbar and its floating position over the document.
    @Namespace private var focusNS
    /// Shared namespace so the sidebar toggle flies between the sidebar card
    /// (expanded) and the top-left toolbar (collapsed).
    @Namespace private var sidebarNS
    /// Transient hint shown when entering focus mode (Craft-style).
    @State private var showFocusHint = false
    /// 鼠标悬停到顶部时浮现的退出按钮。
    @State private var showFocusExitHover = false

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
                    // Canvas behind the floating sidebar card — matches the editor
                    // window background so the gutter around the card reads as part
                    // of the window, not as a transparent hole to the desktop.
                    // SidebarVibrancyView blends behind the window at the compositor
                    // level and doesn't need this layer to be transparent.
                    theme.windowBackground
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
                            // 原生 NSVisualEffectView sidebar material：
                            // 聚焦时带强调色光泽，失焦时自动去饱和，和 Finder/Craft 一致。
                            ZStack {
                                SidebarVibrancyView()
                                // 浅色主题叠一层半透明白，避免桌面深色透进来；
                                // 窗口激活时略薄让 vibrancy 强调色透出来，失焦时加厚变灰。
                                if !theme.isDark {
                                    Color.white.opacity(controlActiveState == .key ? 0.60 : 0.78)
                                        .animation(.easeInOut(duration: 0.2), value: controlActiveState)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        // Hairline border with a top-lit highlight → a subtle
                        // glowing rim that makes the card read as "floating".
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: theme.isDark
                                            ? [Color.white.opacity(0.22),
                                               Color.white.opacity(0.05)]
                                            : [Color.white.opacity(1.0),
                                               Color.white.opacity(0.40)],
                                        startPoint: .top, endPoint: .bottom
                                    ),
                                    lineWidth: 1
                                )
                                .blendMode(.plusLighter)
                        )
                        .shadow(color: .black.opacity(theme.isDark ? 0.55 : 0.22),
                                radius: 18, x: 0, y: 6)
                        .shadow(color: .black.opacity(theme.isDark ? 0.25 : 0.08),
                                radius: 4, x: 0, y: 1)
                        .shadow(color: Color.white.opacity(theme.isDark ? 0.06 : 0.25),
                                radius: 6, x: 0, y: 0)
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
                    Color.clear.frame(height: 38)
                } else if workspaceUI.activeMainView != .document {
                    // Calendar / Todos 有各自的头部栏 — 跳过全局 TopToolbar（含文件 tab 栏）
                    Color.clear.frame(height: 0)
                } else {
                    TopToolbar(workspaceUI: workspaceUI, focusNS: focusNS)
                }

                HStack(spacing: 0) {
                    ZStack {
                        theme.windowBackground
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        switch workspaceUI.activeMainView {
                        case .todos:
                            TodoMainView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        case .calendar:
                            CalendarMainView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        case .document:
                            ZStack {
                                if state.showingDiffReview {
                                    // AI diff 审阅：接管整个文档区域，动画过渡
                                    DiffReviewOverlay()
                                        .environment(state)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .transition(
                                            .asymmetric(
                                                insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .center)),
                                                removal:   .opacity
                                            )
                                        )
                                } else {
                                    HStack(spacing: 0) {
                                        if workspaceUI.showsEditor {
                                            // 专注模式：iA Writer 风格居中窄列（仅独占编辑器时）
                                            if workspaceUI.isFocusMode && !workspaceUI.showsPreview {
                                                Spacer(minLength: 0)
                                                editor().frame(maxWidth: 740)
                                                Spacer(minLength: 0)
                                            } else {
                                                editor().frame(maxWidth: .infinity)
                                            }
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
                                    .transition(.opacity)
                                }
                            }
                            .animation(.spring(response: 0.35, dampingFraction: 0.88), value: state.showingDiffReview)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.easeInOut(duration: 0.22), value: workspaceUI.activeMainView)
                    // Focus toggle flies here (hero) when focus mode is on.
                    .overlay(alignment: .topTrailing) {
                        if workspaceUI.isFocusMode {
                            FocusToggleButton(workspaceUI: workspaceUI)
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
                    // 鼠标移到顶部时浮现的退出按钮（专注模式悬浮触发区）
                    .overlay(alignment: .top) {
                        if workspaceUI.isFocusMode {
                            FocusExitHoverZone(workspaceUI: workspaceUI)
                        }
                    }
                    // Floating AI assistant launcher — pinned to the bottom-trailing
                    // corner of the document area (clear of the right rail). Fades
                    // out while its hero panel is open so the panel appears to grow
                    // out of this button.
                    .overlay(alignment: .bottomTrailing) {
                        AIAssistantButton()
                            .padding(.trailing, 18)
                            .padding(.bottom, 18)
                            .opacity(state.showingAIAssistant ? 0 : 1)
                            .allowsHitTesting(!state.showingAIAssistant)
                            .animation(DS.Motion.fast, value: state.showingAIAssistant)
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
                if workspaceUI.isFocusMode {
                    withAnimation(DS.Motion.fast) { workspaceUI.isFocusMode = false }
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
    let focusNS: Namespace.ID

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

            ToolbarActionGroup(workspaceUI: workspaceUI, focusNS: focusNS)
        }
        .frame(height: 44)
        .background(.bar, ignoresSafeAreaEdges: .top)  // macOS 原生 toolbar material：聚焦时鲜艳，失焦时变灰
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
    let focusNS: Namespace.ID

    var body: some View {
        EmptyView()
    }
}

// MARK: - Document Statistics

/// Detailed statistics computed from document text.
struct DocStats {
    let cjkCount: Int      // Chinese/Japanese/Korean characters
    let latinWords: Int    // English/Latin word count
    let totalChars: Int    // All non-whitespace characters
    let lineCount: Int     // Line count

    /// Short label for the status bar chip.
    var chipLabel: String {
        switch (cjkCount > 0, latinWords > 0) {
        case (true, true):  return "\(cjkCount.formatted())字"
        case (true, false): return "\(cjkCount.formatted())字"
        default:            return "\(latinWords)w"
        }
    }

    /// Estimated reading time in minutes (CJK: 350 char/min, Latin: 200 wpm).
    var readingMinutes: Int {
        let t = Double(cjkCount) / 350.0 + Double(latinWords) / 200.0
        return max(1, Int(t.rounded()))
    }

    static func compute(from text: String) -> DocStats {
        var cjk = 0
        var allChars = 0

        for scalar in text.unicodeScalars {
            let v = scalar.value
            guard v > 0x20 else { continue }   // skip whitespace + control
            allChars += 1
            if isCJKScalar(v) { cjk += 1 }
        }

        // Count only Latin/non-CJK words via Unicode word-boundary enumeration.
        var latin = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, range, _, _ in
            guard let first = text[range].unicodeScalars.first else { return }
            if !isCJKScalar(first.value) { latin += 1 }
        }

        let lines = max(1, text.components(separatedBy: "\n").count)
        return DocStats(cjkCount: cjk, latinWords: latin, totalChars: allChars, lineCount: lines)
    }

    private static func isCJKScalar(_ v: UInt32) -> Bool {
        (v >= 0x4E00 && v <= 0x9FFF)   ||
        (v >= 0x3400 && v <= 0x4DBF)   ||
        (v >= 0x20000 && v <= 0x2A6DF) ||
        (v >= 0xF900 && v <= 0xFAFF)   ||
        (v >= 0x2E80 && v <= 0x2EFF)   ||
        (v >= 0xAC00 && v <= 0xD7AF)   ||
        (v >= 0x3040 && v <= 0x30FF)    // Hiragana + Katakana
    }
}

private struct StatusBarHost: View {
    @Environment(AppState.self) private var state
    @State private var showStatsPopover = false
    /// 控制"已保存" chip 的显隐，保存成功后显示，2 秒后自动淡出。
    @State private var showSavedChip = false
    @State private var savedChipTask: Task<Void, Never>? = nil

    var body: some View {
        let theme = state.themeStore.current
        HStack(spacing: 0) {
            if let tab = state.selectedTab {
                let stats = DocStats.compute(from: tab.content)

                statusChip("\(state.cursorLine):\(state.cursorColumn)", icon: "character.cursor.ibeam")
                statusDivider(theme)

                // Tappable word-count chip → shows detailed stats popover
                Button {
                    showStatsPopover.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "text.word.spacing")
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(stats.chipLabel)
                            .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showStatsPopover, arrowEdge: .bottom) {
                    StatsPopover(stats: stats)
                }

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

            // "已保存"短暂提示 chip
            if showSavedChip {
                statusDivider(theme)
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.green.opacity(0.8))
                    Text(L("statusBar.saved"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .leading)))
            }

            Spacer()

            // 分享状态（右对齐）
            ShareStatusChip(state: state, theme: theme)
        }
        .animation(DS.Motion.fast, value: showSavedChip)
        .onChange(of: state.lastSavedAt) { _, _ in
            savedChipTask?.cancel()
            showSavedChip = true
            savedChipTask = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                showSavedChip = false
            }
        }
        .frame(height: 22)
        .background(.bar)  // 与 tab bar 保持一致的 material
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
}

// MARK: - Share Status Chip

/// 状态栏右侧的分享状态指示器。
/// - LAN 分享进行中：显示 wifi 图标（accent 色），点击复制当前文件链接
/// - GitHub Gist 有上次发布链接：显示云图标，点击复制链接
/// - 两者都无：不显示
private struct ShareStatusChip: View {
    let state: AppState
    let theme: PreviewTheme
    @State private var isHovered = false

    var lanURL: String? {
        guard state.shareServer.isRunning,
              let tab = state.selectedTab else { return nil }
        return state.shareServer.shareURLForFile(tab.url)
    }

    var body: some View {
        HStack(spacing: 0) {
            // LAN 分享状态
            if state.shareServer.isRunning {
                Button {
                    if let url = lanURL {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url, forType: .string)
                    }
                } label: {
                    shareChipLabel(icon: "wifi", text: L("statusBar.sharing"))
                }
                .buttonStyle(.plain)
                .help(lanURL.map { L("statusBar.copyLANLink") + "\n" + $0 }
                      ?? L("statusBar.sharing"))
            }

            // GitHub Gist 上次发布链接
            if let gistURL = state.githubGistManager.lastResultURL {
                if state.shareServer.isRunning {
                    theme.separator.frame(width: 1, height: 10).opacity(0.5).padding(.horizontal, 6)
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(gistURL, forType: .string)
                } label: {
                    shareChipLabel(icon: "cloud", text: "Gist")
                }
                .buttonStyle(.plain)
                .help(L("statusBar.copyGistLink") + "\n" + gistURL)
            }
        }
        .animation(DS.Motion.fast, value: state.shareServer.isRunning)
        .animation(DS.Motion.fast, value: state.githubGistManager.lastResultURL != nil)
    }

    private func shareChipLabel(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.appAccent)
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.appAccent.opacity(0.85))
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Stats Popover

private struct StatsPopover: View {
    let stats: DocStats
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.appAccent)
                Text("文档统计")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider().opacity(0.5)

            // Stats rows
            VStack(spacing: 0) {
                if stats.cjkCount > 0 {
                    statsRow(label: "汉字", value: stats.cjkCount.formatted(), icon: "character")
                }
                if stats.latinWords > 0 {
                    statsRow(label: "英文词", value: "\(stats.latinWords)", icon: "textformat.abc")
                }
                statsRow(label: "字符", value: stats.totalChars.formatted(), icon: "character.cursor.ibeam")
                statsRow(label: "行数", value: "\(stats.lineCount)", icon: "list.bullet")
                statsRow(label: "阅读时间", value: "约 \(stats.readingMinutes) 分钟", icon: "clock")
            }
            .padding(.vertical, 4)
        }
        .frame(width: 200)
        .background(.regularMaterial)
    }

    private func statsRow(label: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
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
                .foregroundStyle(Color.appAccent)
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
                        .fill(Color.appAccent)
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

/// 专注模式下鼠标移到顶部时浮现的退出按钮（Escape 已有快捷键，此处提供鼠标路径）。
private struct FocusExitHoverZone: View {
    @Bindable var workspaceUI: WorkspaceUIState
    @State private var isHovered = false

    var body: some View {
        Color.clear
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .overlay(alignment: .topLeading) {
                if isHovered {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            workspaceUI.isFocusMode = false
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 12, weight: .medium))
                            Text(L("tooltip.exitFocus"))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    // 留出 macOS 流量灯宽度
                    .padding(.leading, 86)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .topLeading)))
                }
            }
            .animation(.easeOut(duration: 0.18), value: isHovered)
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
