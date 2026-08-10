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

// MARK: - Focus mode ESC monitor

/// ESC 退出专注模式。隐藏 Button 的 keyboardShortcut 和 onExitCommand 在编辑器
/// （NSTextView）或 WKWebView 持有焦点时都收不到 ESC——本地事件监视器挂在
/// App 事件分发层，不依赖焦点链，窗口是 key 就能收到。
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

        func install(workspaceUI: WorkspaceUIState, state: AppState) {
            remove()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // 本地监视器在主线程事件分发中同步触发，且必须同步返回（消费/放行）
                MainActor.assumeIsolated {
                    guard event.keyCode == 53 else { return event } // 非 ESC 直接放行
                    guard workspaceUI.isFocusMode,
                          !state.showingDiffReview,
                          !state.showingQuickOpen,
                          !state.showingSettings,
                          !state.showingBeautifySheet,
                          !state.showingTemplatePicker,
                          !state.showingCloseConfirmation
                    else { return event }
                    withAnimation(DS.Motion.fast) { workspaceUI.isFocusMode = false }
                    return nil
                }
            }
        }

        func remove() {
            if let m = monitor { NSEvent.removeMonitor(m) }
            monitor = nil
        }
    }
}
