import SwiftUI
import AppKit

/// Walks up the view hierarchy from inside the NavigationSplitView sidebar column
/// and patches the system-provided NSVisualEffectView to use .sidebar material.
struct SidebarMaterialFixer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { Self.fix(v) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.fix(nsView) }
    }

    static func fix(_ view: NSView) {
        // Walk up to find the column's NSVisualEffectView
        var v: NSView? = view
        while let current = v {
            if let vev = current as? NSVisualEffectView,
               current.frame.width < 400 {   // sidebar is narrow
                vev.material = .sidebar
                vev.blendingMode = .behindWindow
                vev.state = .followsWindowActiveState
                return
            }
            v = current.superview
        }
    }
}
