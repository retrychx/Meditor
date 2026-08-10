import SwiftUI
import UniformTypeIdentifiers

// MARK: - Tab Bar

@MainActor
struct EditorTabBar: View {
    @Environment(AppState.self) private var state
    @State private var draggedTabID: UUID?

    private var theme: PreviewTheme { state.themeStore.current }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(state.openTabs.enumerated()), id: \.element.id) { idx, tab in
                    let isSelected = tab.id == state.selectedTabID
                    let prevSelected = idx > 0 && state.openTabs[idx - 1].id == state.selectedTabID
                    TabItem(
                        tab: tab,
                        isSelected: isSelected,
                        isDark: theme.isDark,
                        showLeadingSeparator: idx > 0 && !isSelected && !prevSelected,
                        onSelect: { state.selectTab(tab.id) },
                        onClose: { state.closeTab(tab.id) }
                    )
                    .opacity(draggedTabID == tab.id ? 0.45 : 1)
                    .animation(DS.Motion.fast, value: draggedTabID)
                    .onDrag {
                        draggedTabID = tab.id
                        return NSItemProvider(object: tab.id.uuidString as NSString)
                    }
                    .onDrop(of: [UTType.text],
                            delegate: TabDropDelegate(tab: tab, draggedTabID: $draggedTabID, state: state))
                    .contextMenu {
                        Button(L("tab.close")) { state.closeTab(tab.id) }
                        Button(L("tab.closeOthers")) {
                            state.openTabs.filter { $0.id != tab.id }.forEach { state.closeTab($0.id) }
                        }
                        Button(L("tab.closeAll")) { state.openTabs.forEach { state.closeTab($0.id) } }
                        Divider()
                        Button(L("tab.showInFinder")) {
                            NSWorkspace.shared.activateFileViewerSelecting([tab.url])
                        }
                        Divider()
                        Button(L("menu.saveAsTemplate")) {
                            state.selectedTab.map { _ in
                                state.showingSaveTemplate = true
                            }
                        }
                        .disabled(state.selectedTab == nil)
                    }
                }
            }
            .padding(.horizontal, 6)
            .frame(maxHeight: .infinity)   // pill 在 toolbar 行内纵向撑满
            .animation(.easeInOut(duration: 0.18), value: state.openTabs.map(\.id))
        }
        // toolbar 对无限高度测量会塌掉——给定内容高度，pill 才能在其中拉高
        .frame(height: 44)
        // macOS 26 会给 toolbar 里的 ScrollView 自动加圆角底板——关掉
        .scrollContentBackground(.hidden)
        // 滚动到边缘时系统会叠一层玻璃/渐隐圆晕（前缘那团圆角就是这么来的）——关掉
        .disableScrollEdgeEffectsIfAvailable()
        // macOS 26 的 NSToolbar 还会给每个 item 套 Liquid Glass 胶囊——拆掉
        .background(ToolbarItemGlassDisabler())
        // item 尺寸大于内容尺寸时，即便拆了胶囊描边，NSToolbarItem 自身默认的
        // 浅色圆角容器背景仍会在未被内容覆盖的尾部露出一块——垫一层与 toolbar
        // 同色的实底盖住它（比 .scrollContentBackground(.hidden) 更彻底）。
        // AI 助手/设置弹窗打开时，内容区会叠一层黑色调光遮罩，但那层遮罩挂在
        // ContentView 内容区、不会盖到 NSToolbar 原生层——这层不透明实底如果
        // 不跟着变暗，tab 条会「浮」在变暗的下方内容之上，视觉脱节。这里跟着
        // state.aiUI.overlayShown / state.settingsOverlayShown 叠一层同样强度
        // 的暗化——这两个值分别和各自的真实遮罩共享同一处 withAnimation
        // (spring(0.42, 0.80)) 调用，不是自己另开一套动画/延迟去模拟，
        // 保证暗化像素级同步。两个遮罩不透明度不同（AI 0.30 / 设置 0.28），
        // 分别匹配，不用同一个数值。
        .background(
            GeometryReader { proxy in
                theme.windowBackground
                    .overlay(Color.black.opacity(dimmedOpacity))
                    .frame(width: max(proxy.size.width, 0), height: max(proxy.size.height, 0))
            }
        )
    }

    private var dimmedOpacity: Double {
        if state.aiUI.overlayShown { return 0.30 }
        if state.settingsOverlayShown { return 0.28 }
        return 0
    }
}

// MARK: - Tab Item

private struct TabItem: View {
    let tab: EditorTab
    let isSelected: Bool
    let isDark: Bool
    /// 未选中 tab 之间的细分隔线（Safari 式）；选中 pill 两侧不画。
    let showLeadingSeparator: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            if showLeadingSeparator {
                Rectangle()
                    .fill(Color.primary.opacity(isDark ? 0.16 : 0.12))
                    .frame(width: 1, height: 14)
                    .padding(.horizontal, 3)
            }
            Button(action: onSelect) {
                HStack(spacing: 5) {
                    // File icon
                    Image(systemName: FileTypeConfiguration.shared.icon(for: tab.url.pathExtension))
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 11))
                        .foregroundStyle(
                            isSelected ? AnyShapeStyle(Color.appAccent) : AnyShapeStyle(Color.secondary.opacity(0.5))
                        )

                    // File name
                    Text(tab.name)
                        .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                        .foregroundStyle(
                            isSelected
                                ? AnyShapeStyle(Color.primary)
                                : AnyShapeStyle(Color.secondary.opacity(isHovered ? 0.95 : 0.7))
                        )
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)

                    // Dot or close button
                    closeOrDot
                        .frame(width: 14, height: 14)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                // 宽一点的 pill：选中态不再窄巴巴地包住截断标题
                .frame(minWidth: 104, maxWidth: 240, maxHeight: .infinity)
                .background(tabBackground)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help(tab.url.path)
        }
    }

    @ViewBuilder
    private var tabBackground: some View {
        if isSelected {
            // 选中态：更实的卡片 + 更强的阴影，在磨砂背景上明显凸起
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isDark ? Color(white: 0.26) : Color.white)
                .shadow(color: .black.opacity(isDark ? 0.45 : 0.18), radius: 6, x: 0, y: 2)
                .shadow(color: .black.opacity(isDark ? 0.2 : 0.06), radius: 1, x: 0, y: 0)
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
        }
        // 未选中：不要圆角 pill（hover 圆角时有时无、和选中态形状重复），
        // 用 TabItem 行内的细分隔线区隔，hover 只加深文字。
    }

    @ViewBuilder
    private var closeOrDot: some View {
        ZStack {
            if isHovered || isSelected {
                Button(action: onClose) {
                    ZStack {
                        Circle()
                            .fill(Color.primary.opacity(0.1))
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.secondary)
                    }
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            } else if tab.isModified {
                Circle()
                    .fill(Color.orange.opacity(0.85))
                    .frame(width: 5, height: 5)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(DS.Motion.fast, value: isHovered)
        .animation(DS.Motion.fast, value: tab.isModified)
    }
}

// MARK: - Drop Delegate

struct TabDropDelegate: DropDelegate {
    let tab: EditorTab
    @Binding var draggedTabID: UUID?
    let state: AppState

    func performDrop(info: DropInfo) -> Bool { draggedTabID = nil; return true }

    func dropEntered(info: DropInfo) {
        guard let from = draggedTabID, from != tab.id,
              let src = state.openTabs.firstIndex(where: { $0.id == from }),
              let dst = state.openTabs.firstIndex(where: { $0.id == tab.id }) else { return }
        state.moveTab(from: src, to: dst)
        draggedTabID = tab.id
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
}

// MARK: - Toolbar item glass disabler

/// macOS 26：NSToolbar 自动给每个 item 背后垫 Liquid Glass 材质
/// （tab 条两端看到的圆角胶囊边）。官方移除方式是 NSToolbarItem.isBordered = false，
/// SwiftUI 未暴露——从标记视图向上找到所属 item 关掉。
/// 参考 WWDC25 "Build an AppKit app with the new design"。
private struct ToolbarItemGlassDisabler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { context.coordinator.arm(containing: v) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // toolbar 会重建 item（窗口状态变化时）——每次 SwiftUI 更新时幂等重放
        DispatchQueue.main.async { context.coordinator.arm(containing: nsView) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// 找到所属 NSToolbarItem 并关 isBordered；同时订阅窗口更新——
    /// toolbar 隐藏/显示（如进出专注模式）会重建 item 并把 isBordered 重置回 true，
    /// didUpdate 每次窗口事件后触发，幂等重放、成本可忽略。
    @MainActor
    final class Coordinator: NSObject {
        private weak var markerView: NSView?
        private var observedWindow: NSWindow?

        func arm(containing view: NSView) {
            markerView = view
            disarm()
            guard let window = view.window, observedWindow !== window else { return }
            observedWindow = window
            NotificationCenter.default.addObserver(
                forName: NSWindow.didUpdateNotification, object: window, queue: .main
            ) { _ in
                // block 在 .main 队列执行，直接assume；强捕获 self 避免 @Sendable
                // 闭包里 weak var 捕获在严格并发检查（CI Xcode 16）下报错
                MainActor.assumeIsolated { self.disarm() }
            }
        }

        /// 只处理包含标记视图的那个 item——不动系统侧栏开关等其它 item 的玻璃。
        func disarm() {
            // isBordered 是 macOS 26 SDK（Xcode 26 / Swift 6.2）才有的 API——
            // CI 的 Xcode 16 编译期找不到符号，用 compiler 守卫整段摘掉
            #if compiler(>=6.2)
            guard let view = markerView, let toolbar = view.window?.toolbar else { return }
            for item in toolbar.items {
                guard let itemView = item.view, view.isDescendant(of: itemView) else { continue }
                if #available(macOS 26.0, *), item.isBordered {
                    item.isBordered = false
                }
            }
            #endif
        }
    }
}

// MARK: - Scroll edge effects

private extension View {
    /// 关掉 macOS 26 滚动边缘的玻璃/渐隐圆晕；低版本系统本来就没有，直接透传。
    /// #if compiler 守卫：API 只在 macOS 26 SDK（Xcode 26 / Swift 6.2）里存在，
    /// CI 的 Xcode 16（macOS 15 SDK）编译期就找不到符号，#available 救不了。
    @ViewBuilder
    func disableScrollEdgeEffectsIfAvailable() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self
                .scrollEdgeEffectStyle(.none, for: .leading)
                .scrollEdgeEffectStyle(.none, for: .trailing)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
