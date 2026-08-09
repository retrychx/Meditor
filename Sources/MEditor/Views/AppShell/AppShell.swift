import SwiftUI

@MainActor
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
                    // 专注模式：内容从系统 toolbar 下方开始，无需预留固定高度
                    Color.clear.frame(height: 0)
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
        // 内容从系统 toolbar 下方开始（不忽略顶部 safe area）——
        // 否则 TopToolbar 的 tab 栏会被原生 toolbar 磨砂带盖住。
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

@MainActor
private struct TopToolbar: View {
    @Environment(AppState.self) private var state
    @Environment(\.sidebarToggleNS) private var sidebarNS
    @Bindable var workspaceUI: WorkspaceUIState
    let focusNS: Namespace.ID

    private var theme: PreviewTheme { state.themeStore.current }

    var body: some View {
        HStack(spacing: 0) {
            // Tab bar（侧边栏切换已进系统 toolbar，红绿灯不再落内容区）
            tabZone
                .frame(maxWidth: .infinity)
        }
        .frame(height: 44)
        // 普通背景：系统 toolbar 是唯一的顶部磨砂带，避免双条
        .background(theme.windowBackground)
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
