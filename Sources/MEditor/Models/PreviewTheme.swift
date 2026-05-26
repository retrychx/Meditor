import Foundation

/// Available preview themes. The raw value is used as both the
/// CSS file name (`<rawValue>.css`) and the persisted user preference.
enum PreviewTheme: String, CaseIterable, Identifiable {
    case github
    case nord
    case dracula

    var id: String { rawValue }

    /// Human-readable name for UI display.
    var displayName: String {
        switch self {
        case .github:  return "GitHub"
        case .nord:    return "Nord"
        case .dracula: return "Dracula"
        }
    }

    /// Whether this theme uses a dark background. Used to pick a sensible
    /// fallback editor color scheme that matches the preview pane.
    var isDark: Bool {
        switch self {
        case .github:  return false
        case .nord:    return true
        case .dracula: return true
        }
    }
}
