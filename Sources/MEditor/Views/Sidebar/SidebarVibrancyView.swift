import AppKit
import SwiftUI

/// A thin `NSViewRepresentable` wrapper around `NSVisualEffectView` configured
/// for the `.sidebar` material.  Unlike SwiftUI's `.regularMaterial`, this
/// material:
///   - Activates accent-color vibrancy when the window is key/main.
///   - Desaturates gracefully when the window loses focus.
///   - Matches Finder and Craft's native sidebar feel exactly.
struct SidebarVibrancyView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material            = .sidebar
        v.blendingMode        = .behindWindow
        v.state               = .followsWindowActiveState
        v.isEmphasized        = false
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
