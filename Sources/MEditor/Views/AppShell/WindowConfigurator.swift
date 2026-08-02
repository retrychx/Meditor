import SwiftUI
import AppKit

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            guard let w = v.window else { return }
            context.coordinator.attach(to: w)
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject {
        private var observation: NSKeyValueObservation?
        private weak var window: NSWindow?

        func attach(to window: NSWindow) {
            self.window = window
            configure(window)
            observation = window.observe(\.toolbar, options: [.new]) { [weak self] w, _ in
                if w.toolbar != nil { self?.configure(w) }
            }
            // 系统会在 resize / 窗口激活切换时重排标准按钮，需重放我们的位置。
            let nc = NotificationCenter.default
            for name in [NSWindow.didResizeNotification,
                         NSWindow.didBecomeKeyNotification,
                         NSWindow.didResignKeyNotification] {
                nc.addObserver(self, selector: #selector(reapply),
                               name: name, object: window)
            }
        }

        @objc private func reapply() {
            guard let w = window else { return }
            DispatchQueue.main.async { Self.repositionTrafficLights(w) }
        }

        private func configure(_ w: NSWindow) {
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.styleMask.insert(.fullSizeContentView)
            // Keep the compact titlebar (no toolbar). A unified/tall toolbar would
            // lower the traffic lights but also add an empty full-width header
            // strip above the tab bar, so we avoid it.
            w.toolbar = nil


            // macOS 26 起 titlebar 私有视图结构变化（Liquid Glass），原先的
            // 容器压缩/装饰隐藏手术会导致红绿灯按钮不渲染，已停用。
            // 只做轻量的按钮位置微调（setFrameOrigin），不做视图层级手术。
            DispatchQueue.main.async {
                Self.repositionTrafficLights(w)
                self.installDoubleClickZoom(w)
            }
        }

        /// 把红绿灯按钮从窗口角上往内收一点，让它们完整落在侧边栏卡片里
        /// （默认位置贴着圆角裁切区，看起来像悬在卡片外）。
        private static func repositionTrafficLights(_ w: NSWindow) {
            let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            let buttons = types.compactMap { w.standardWindowButton($0) }
            guard buttons.count == 3, let bar = buttons[0].superview else { return }

            // Titlebar view 非 flipped：y 向上增长，顶 = bar.bounds.height。
            let topGap: CGFloat = 15     // 窗口顶到按钮顶的距离
            let leftPad: CGFloat = 16    // 窗口左缘到第一个按钮的距离
            let spacing: CGFloat = 20    // 标准按钮间距

            for (i, btn) in buttons.enumerated() {
                let size = btn.frame.size
                let x = leftPad + CGFloat(i) * spacing
                let y = bar.bounds.height - topGap - size.height
                btn.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }

        // MARK: - Double-click zoom

        /// Installs a double-click gesture on the tab-bar / chrome area so that
        /// double-clicking the top of the window zooms it (standard macOS behaviour).
        /// The system titlebar is transparent, so the normal title-bar
        /// double-click zone doesn't cover the full width.
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
