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
            // The system re-lays-out the standard window buttons on resize and
            // when the window (de)activates, so re-apply our custom positions.
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
            DispatchQueue.main.async { self.constrainTitlebarToSidebar(w) }
        }

        private func configure(_ w: NSWindow) {
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.styleMask.insert(.fullSizeContentView)
            // Keep the compact titlebar (no toolbar). A unified/tall toolbar would
            // lower the traffic lights but also add an empty full-width header
            // strip above the tab bar, so we avoid it.
            w.toolbar = nil


            // Shrink the titlebar container to sidebar width so the
            // traffic lights only occupy the left column.
            // The tab bar area (right of sidebar) becomes fully clickable.
            DispatchQueue.main.async {
                self.constrainTitlebarToSidebar(w)
                self.installDoubleClickZoom(w)
            }
        }

        private func constrainTitlebarToSidebar(_ w: NSWindow) {
            guard let contentView = w.contentView, let themeFrame = contentView.superview else { return }
            let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            let buttons = buttonTypes.compactMap { w.standardWindowButton($0) }
            guard let firstButton = buttons.first else { return }

            // 从红绿灯按钮向上找到 titlebar 容器（themeFrame 的直接子视图）。
            // 不依赖私有类名，macOS 版本间类名会变。
            var container: NSView = firstButton
            while let parent = container.superview, parent !== themeFrame {
                container = parent
            }
            guard container.superview === themeFrame else { return }

            // Shrink the titlebar container to *just* the traffic lights so
            // everything to their right (sidebar, tabs, the show-sidebar
            // button) stays clickable instead of being captured by the
            // titlebar drag region.
            var f = container.frame
            f.size.width = 80
            container.frame = f
            container.autoresizingMask = [.minYMargin]
            // Allow the traffic-light buttons to be pushed *below* the
            // default compact-titlebar height without being clipped.
            container.clipsToBounds = false
            container.layer?.backgroundColor = nil
            container.layer?.cornerRadius = 0
            container.layer?.mask = nil

            // 容器内：只保留按钮所在分支，背景/装饰视图全部隐藏——
            // 否则 titlebar 的不透明白底（带窗口圆角）会戳进内容区。
            Self.hideChrome(in: container, keeping: buttons)

            // 容器外：新版 macOS 可能把毛玻璃/圆角装饰做成容器的兄弟节点，
            // 类名随版本变化（Titlebar*/Backdrop/Glass/Decoration…）。
            // 只隐藏"标题栏高度"的条带视图，避免误伤全窗口背景。
            for sibling in themeFrame.subviews
            where sibling !== container && sibling !== contentView && sibling.frame.height <= 80 {
                let name = String(describing: type(of: sibling))
                if name.contains("Titlebar") || name.contains("Backdrop")
                    || name.contains("Glass") || name.contains("Decoration") {
                    sibling.isHidden = true
                }
            }

            repositionTrafficLights(w)
        }

        /// 隐藏 view 子树中所有「不包含红绿灯按钮」的分支；
        /// 按钮所在分支保持可见，但清掉自身的背景绘制。
        /// 类名无关，对 macOS 各版本的私有视图结构都成立。
        static func hideChrome(in view: NSView, keeping buttons: [NSView]) {
            func subtreeContainsButton(_ v: NSView) -> Bool {
                if buttons.contains(where: { $0 === v }) { return true }
                return v.subviews.contains(where: subtreeContainsButton)
            }
            for sub in view.subviews {
                if subtreeContainsButton(sub) {
                    sub.clipsToBounds = false
                    sub.layer?.backgroundColor = nil
                    sub.layer?.cornerRadius = 0
                    sub.layer?.mask = nil
                    hideChrome(in: sub, keeping: buttons)
                } else {
                    sub.isHidden = true
                }
            }
        }

        /// Push the standard traffic-light buttons lower (Craft / Finder feel)
        /// without adding a tall toolbar — we only move the system buttons, so the
        /// SwiftUI content layout is untouched and no empty header strip appears.
        private func repositionTrafficLights(_ w: NSWindow) {
            let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            let buttons = types.compactMap { w.standardWindowButton($0) }
            guard buttons.count == 3, let bar = buttons[0].superview else { return }

            // Titlebar view is not flipped: y grows upward, top == bar.bounds.height.
            let topGap: CGFloat = 16     // distance from window top to button top
            let leftPad: CGFloat = 19    // distance from window left to first button
            let spacing: CGFloat = 20    // standard inter-button spacing

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
        /// This is needed because the system titlebar is shrunk to 80 px (traffic
        /// lights only), so the normal title-bar double-click zone doesn't cover the
        /// full width.
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
