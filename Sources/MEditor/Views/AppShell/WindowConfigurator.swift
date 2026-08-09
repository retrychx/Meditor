import SwiftUI
import AppKit

/// 窗口配置：只做 titleVisibility 隐藏 + 双击放大手势。
/// 布局是 Apple 原生方案（NavigationSplitView + hiddenTitleBar + 系统 toolbar），
/// 不对 titlebar 私有视图做任何手术，macOS 升级不再塌。
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            context.coordinator.attachWhenReady(to: v)
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject {
        private var observation: NSKeyValueObservation?
        private weak var window: NSWindow?

        /// makeNSView 时窗口可能尚未挂链（不同启动路径时序不同）——
        /// 轮询等待 window 出现再配置，否则 titleVisibility 等设置会静默丢失
        /// （裸二进制启动时曾观察到「MEditor」标题残留）。
        func attachWhenReady(to view: NSView, attempts: Int = 20) {
            if let w = view.window {
                attach(to: w)
            } else if attempts > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.attachWhenReady(to: view, attempts: attempts - 1)
                }
            }
        }

        func attach(to window: NSWindow) {
            self.window = window
            configure(window)
            // SwiftUI 安装/更新 toolbar（包括后续增删 toolbar item）时会把
            // titleVisibility 重置回 visible，「MEditor」标题因此反复冒出来。
            // didUpdate 每次窗口事件后触发——幂等重放隐藏，成本可忽略。
            observation = window.observe(\.toolbar, options: [.new]) { w, _ in
                if w.toolbar != nil { w.titleVisibility = .hidden }
            }
            NotificationCenter.default.addObserver(
                forName: NSWindow.didUpdateNotification, object: window, queue: .main
            ) { w in
                guard let win = w.object as? NSWindow, win.titleVisibility != .hidden else { return }
                win.titleVisibility = .hidden
            }
        }

        private func configure(_ w: NSWindow) {
            w.titleVisibility = .hidden
            DispatchQueue.main.async {
                self.installDoubleClickZoom(w)
            }
        }

        // MARK: - Double-click zoom

        /// Installs a double-click gesture on the top chrome area so that
        /// double-clicking the top of the window zooms it (standard macOS behaviour).
        private func installDoubleClickZoom(_ w: NSWindow) {
            guard let contentView = w.contentView else { return }
            // Walk up to the window's root view (superview of contentView).
            guard let root = contentView.superview else { return }

            // Remove any previously installed recognizer to avoid duplicates.
            root.gestureRecognizers
                .filter { $0 is ChromeDoubleClickZoom }
                .forEach { root.removeGestureRecognizer($0) }

            let gr = ChromeDoubleClickZoom(window: w)
            root.addGestureRecognizer(gr)
        }
    }
}

/// An `NSClickGestureRecognizer` that triggers `window.zoom(_:)` on double-click,
/// but only when the click lands in the top chrome strip (≤ 52 pt from top).
private final class ChromeDoubleClickZoom: NSClickGestureRecognizer {
    private weak var zoomWindow: NSWindow?

    init(window: NSWindow) {
        self.zoomWindow = window
        super.init(target: nil, action: nil)
        numberOfClicksRequired = 2
        target = self
        action = #selector(handleDoubleClick)
        // Don't eat single clicks — let them pass through.
        delaysPrimaryMouseButtonEvents = false
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleDoubleClick(_ sender: NSGestureRecognizer) {
        guard let v = sender.view else { return }
        let loc = sender.location(in: v)
        // Only trigger zoom when the click is in the top chrome strip.
        let chromeHeight: CGFloat = 52
        guard loc.y >= v.bounds.height - chromeHeight else { return }
        zoomWindow?.zoom(nil)
    }
}

/// Marks a SwiftUI region as non-window-draggable.
struct NonDraggableView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NonDraggable() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private class NonDraggable: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
    }
}
