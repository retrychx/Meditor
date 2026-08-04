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
            DispatchQueue.main.async {
                Self.constrainTitlebarToLights(w)
                Self.makeTitlebarBackgroundTransparent(w)
                Self.repositionTrafficLights(w)
            }
        }

        private func configure(_ w: NSWindow) {
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.styleMask.insert(.fullSizeContentView)
            // Keep the compact titlebar (no toolbar). A unified/tall toolbar would
            // lower the traffic lights but also add an empty full-width header
            // strip above the tab bar, so we avoid it.
            w.toolbar = nil


            // 只做两件轻量事：压缩 titlebar 容器宽度 + 微调按钮位置。
            // macOS 26 上「隐藏装饰视图」的旧手术会让按钮不渲染，绝不做；
            // 单纯改容器宽度不影响按钮渲染（已验证）。
            DispatchQueue.main.async {
                Self.constrainTitlebarToLights(w)
                Self.makeTitlebarBackgroundTransparent(w)
                Self.repositionTrafficLights(w)
                self.installDoubleClickZoom(w)
            }
        }

        /// 只隐藏 NSTitlebarBackgroundView：它在 92px 容器里画出一块与侧边栏
        /// 卡片不同色的小补丁。按钮是它的兄弟视图而非子视图，隐藏背景不影响
        /// 按钮渲染（与旧版"隐藏一切非按钮分支"的激进手术不同）。
        private static func makeTitlebarBackgroundTransparent(_ w: NSWindow) {
            guard let close = w.standardWindowButton(.closeButton),
                  let titlebarView = close.superview else { return }
            for sub in titlebarView.subviews {
                if String(describing: type(of: sub)).contains("TitlebarBackground") {
                    sub.isHidden = true
                }
            }
        }

        /// 把 titlebar 容器宽度压到只覆盖红绿灯：
        /// NSTitlebarBackgroundView 跟随容器全宽，压宽后不再在 tab 条上罩一层
        /// 磨砂横条；同时右侧区域不再被 titlebar 拖动区吃掉点击。
        /// 不做任何 isHidden/背景清除——那是 macOS 26 上按钮消失的根因。
        private static func constrainTitlebarToLights(_ w: NSWindow) {
            guard let contentView = w.contentView, let themeFrame = contentView.superview,
                  let close = w.standardWindowButton(.closeButton) else { return }
            // 从按钮向上找到 themeFrame 的直接子容器（不依赖私有类名）
            var container: NSView = close
            while let parent = container.superview, parent !== themeFrame {
                container = parent
            }
            guard container.superview === themeFrame else { return }

            let lightsWidth: CGFloat = 92
            var f = container.frame
            guard f.width > lightsWidth else { return }
            f.size.width = lightsWidth
            container.frame = f
            container.autoresizingMask = [.minYMargin]
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
