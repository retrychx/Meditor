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
            guard let contentView = w.contentView else { return }
            for sub in contentView.superview?.subviews ?? [] {
                let typeName = String(describing: type(of: sub))
                if typeName.contains("Titlebar") || typeName.contains("titlebar") {
                    // Shrink the titlebar container to *just* the traffic lights so
                    // everything to their right (sidebar, tabs, the show-sidebar
                    // button) stays clickable instead of being captured by the
                    // titlebar drag region.
                    var f = sub.frame
                    f.size.width = 80
                    sub.frame = f
                    sub.autoresizingMask = [.minYMargin]
                    // Allow the traffic-light buttons to be pushed *below* the
                    // default compact-titlebar height without being clipped.
                    sub.clipsToBounds = false
                    // The titlebar's NSTitlebarBackgroundView / _NSTitlebarDecorationView
                    // draw an opaque (white) bar with the window's rounded corner.
                    // Once the container is shrunk, that rounded white nub pokes
                    // into the content — hide those backing views (the traffic-light
                    // widgets are siblings, so they stay visible).
                    Self.hideTitlebarBacking(sub)
                    break
                }
            }
            repositionTrafficLights(w)
        }

        /// Recursively hide the titlebar's background/decoration drawing views so
        /// no white bar / rounded nub shows. Traffic-light widgets are left alone.
        static func hideTitlebarBacking(_ view: NSView) {
            let name = String(describing: type(of: view))
            if name.contains("TitlebarBackground") || name.contains("TitlebarDecoration") {
                view.isHidden = true
                return
            }
            view.clipsToBounds = false
            view.layer?.cornerRadius = 0
            view.layer?.mask = nil
            for s in view.subviews { hideTitlebarBacking(s) }
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
