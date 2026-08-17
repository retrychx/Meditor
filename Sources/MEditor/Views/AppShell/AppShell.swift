import SwiftUI

@MainActor
struct AppShell<Sidebar: View, Editor: View, Preview: View>: View {
    @Environment(AppState.self) private var state
    @Bindable var workspaceUI: WorkspaceUIState

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
        // Apple 方案（备忘录/Finder 同款）：NavigationSplitView —— 侧边栏通顶、
        // 红绿灯落在侧边栏材质里、分隔线与拖拽宽度全交系统，
        // 不再对 titlebar 做任何私有视图手术。
        NavigationSplitView(columnVisibility: columnVisibility) {
            sidebar()
                .navigationSplitViewColumnWidth(
                    min: 220, ideal: workspaceUI.clampedSidebarWidth, max: 320
                )
        } detail: {
            VStack(spacing: 0) {
                // 文件 tab 栏已进系统 toolbar（principal 位），这里直接是内容区
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
        .background(theme.windowBackground)
        .background(keyboardShortcutHost)
        // ESC 监视器：ZStack 显式叠加、独立 1×1 隐形 frame（不依赖 .background()
        // 对隐式尺寸的继承——曾经挂在 ContentView 顶层 Group.background 和这里的
        // .background 上均从未触发 makeNSView，实测证实是隐式尺寸解析问题）。
        .overlay(alignment: .topLeading) {
            FocusEscapeMonitor(workspaceUI: workspaceUI, state: state)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
        }
        .environment(\.sidebarToggleNS, sidebarNS)
    }

    /// 侧边栏显隐 → NavigationSplitView 列可见性（专注模式强制 detailOnly，
    /// 退出后自动恢复 showsSidebar 的持久值）。
    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { workspaceUI.showsSidebarInLayout ? .all : .detailOnly },
            // 专注模式下 getter 被强制成 detailOnly，split view 布局同步时会把
            // 这个「被迫值」回写——不回写就误存成用户偏好，下次启动侧栏默认关。
            set: { if !workspaceUI.isFocusMode { workspaceUI.showsSidebar = $0 != .detailOnly } }
        )
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
                // AI 面板打开时 Esc 归面板关闭（与 FocusEscapeMonitor 的门控一致），
                // 避免一次 Esc 同时关面板又退专注模式
                if workspaceUI.isFocusMode && !state.showingAIAssistant {
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

// MARK: - Focus mode ESC monitor

/// ESC 退出专注模式。两条独立路径叠加，覆盖焦点落在编辑器（NSTextView）或
/// 预览（WKWebView）时的所有情况：
///  1. `NSEvent.addLocalMonitorForEvents` —— 覆盖编辑器 NSTextView 持有焦点的
///     场景，理论上不依赖焦点链。
///  2. `.previewWebViewDidPressEscape` 通知 —— WKWebView 把键盘事件转发给独立
///     WebContent 进程处理，会绕开 (1) 的本地事件监视器（文件写入验证：monitor
///     装载成功但焦点在预览里时按任意键都不触发 handler）。`EscapeAwareWebView`
///     子类在 `keyDown` 里拦截 ESC 后广播这个通知，这里统一接收退出。
/// 弹层（diff 审阅/快捷打开/设置等）自己有 ESC 处理，此时放行不消费。
struct FocusEscapeMonitor: NSViewRepresentable {
    let workspaceUI: WorkspaceUIState
    let state: AppState

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        context.coordinator.install(workspaceUI: workspaceUI, state: state)
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        private var monitor: Any?
        private var notificationObserver: NSObjectProtocol?

        func install(workspaceUI: WorkspaceUIState, state: AppState) {
            remove()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // 本地监视器在主线程事件分发中同步触发，且必须同步返回（消费/放行）
                MainActor.assumeIsolated {
                    guard event.keyCode == 53 else { return event } // 非 ESC 直接放行
                    guard Self.shouldExitFocus(workspaceUI: workspaceUI, state: state) else { return event }
                    withAnimation(DS.Motion.fast) { workspaceUI.isFocusMode = false }
                    return nil
                }
            }
            notificationObserver = NotificationCenter.default.addObserver(
                forName: .previewWebViewDidPressEscape, object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    guard Self.shouldExitFocus(workspaceUI: workspaceUI, state: state) else { return }
                    withAnimation(DS.Motion.fast) { workspaceUI.isFocusMode = false }
                }
            }
        }

        func remove() {
            if let m = monitor { NSEvent.removeMonitor(m) }
            monitor = nil
            if let o = notificationObserver { NotificationCenter.default.removeObserver(o) }
            notificationObserver = nil
        }

        private static func shouldExitFocus(workspaceUI: WorkspaceUIState, state: AppState) -> Bool {
            workspaceUI.isFocusMode
                && !state.showingDiffReview
                && !state.showingQuickOpen
                && !state.showingGlobalSearch
                && !state.showingSettings
                && !state.showingBeautifySheet
                && !state.showingTemplatePicker
                && !state.showingCloseConfirmation
                // AI 面板打开时 Esc 归面板（先关面板，再按一次才退出专注模式），
                // 否则本地监视器抢在 keyDown 前消费事件，面板的 Esc 关闭永远收不到
                && !state.showingAIAssistant
        }
    }
}
