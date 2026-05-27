import SwiftUI

/// Displays a keyboard shortcut hint (e.g. "⌘S") in a consistent style.
struct KeyboardShortcutLabel: View {
    let shortcut: String

    var body: some View {
        Text(shortcut)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
