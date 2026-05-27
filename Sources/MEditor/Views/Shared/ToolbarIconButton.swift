import SwiftUI
import AppKit

/// Wraps NSButton to render an SF Symbol at an exact point size,
/// bypassing SwiftUI toolbar's icon size normalization.
struct ToolbarIconButton: NSViewRepresentable {
    let systemName: String
    let size: CGFloat
    let action: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let btn = NSButton()
        btn.bezelStyle = .texturedRounded
        btn.isBordered = false
        btn.target = context.coordinator
        btn.action = #selector(Coordinator.tapped)
        configure(btn)
        return btn
    }

    func updateNSView(_ btn: NSButton, context: Context) {
        configure(btn)
    }

    private func configure(_ btn: NSButton) {
        let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        btn.image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        btn.imageScaling = .scaleProportionallyDown
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    class Coordinator: NSObject {
        let action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}

/// Wraps NSPopUpButton to show a pull-down menu with an SF Symbol icon at exact size.
struct ToolbarIconMenuButton: NSViewRepresentable {
    let systemName: String
    let size: CGFloat
    let items: [(title: String, action: () -> Void)]
    var isDisabled: Bool = false

    func makeNSView(context: Context) -> NSPopUpButton {
        let btn = NSPopUpButton()
        btn.bezelStyle = .texturedRounded
        btn.isBordered = false
        btn.pullsDown = true
        btn.preferredEdge = .minY
        configure(btn, context: context)
        return btn
    }

    func updateNSView(_ btn: NSPopUpButton, context: Context) {
        configure(btn, context: context)
    }

    private func configure(_ btn: NSPopUpButton, context: Context) {
        let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        let img = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)

        btn.menu?.removeAllItems()
        // Item 0 is the button face for pullsDown
        let face = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        face.image = img
        btn.menu?.addItem(face)

        for (i, item) in items.enumerated() {
            let mi = NSMenuItem(title: item.title, action: #selector(Coordinator.menuAction(_:)), keyEquivalent: "")
            mi.target = context.coordinator
            mi.tag = i
            btn.menu?.addItem(mi)
        }
        btn.isEnabled = !isDisabled
        // Hide the arrow indicator
        if let arrowCell = btn.cell as? NSPopUpButtonCell {
            arrowCell.arrowPosition = .noArrow
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(items: items) }

    class Coordinator: NSObject {
        var items: [(title: String, action: () -> Void)]
        init(items: [(title: String, action: () -> Void)]) { self.items = items }

        @objc func menuAction(_ sender: NSMenuItem) {
            let idx = sender.tag
            guard idx < items.count else { return }
            items[idx].action()
        }
    }
}
