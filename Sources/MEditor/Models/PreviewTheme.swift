import SwiftUI

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

    /// Whether this theme uses a dark background. Used to drive the window's
    /// `colorScheme`, which in turn controls system widgets (titlebar buttons,
    /// menu styles, focus rings, etc.).
    var isDark: Bool {
        switch self {
        case .github:  return false
        case .nord:    return true
        case .dracula: return true
        }
    }

    // MARK: - Shell colors
    //
    // For dark themes we override the macOS system colors so each theme has
    // its own distinct palette (Nord cool blue-grey vs Dracula warm purple).
    // GitHub falls back to system colors so it integrates with any user-chosen
    // light/dark macOS appearance.

    /// Background of the main editor / preview area.
    var editorBackground: Color {
        switch self {
        case .github:  return Color(nsColor: .textBackgroundColor)
        case .nord:    return Color(red: 0.180, green: 0.204, blue: 0.251)   // #2e3440
        case .dracula: return Color(red: 0.157, green: 0.165, blue: 0.212)   // #282a36
        }
    }

    /// Chrome background: sidebar + top bar. Intentionally distinct from editor
    /// to create visual hierarchy without relying on materials.
    var chromeBackground: Color {
        switch self {
        case .github:
            // Warm off-white, like Bear/Notion sidebar — cooler than editor white
            return Color(red: 0.937, green: 0.937, blue: 0.941)  // #EFEFF0
        case .nord:
            return Color(red: 0.141, green: 0.161, blue: 0.200)  // #242933
        case .dracula:
            return Color(red: 0.129, green: 0.133, blue: 0.173)  // #21222c
        }
    }

    /// Primary text color.
    var foreground: Color {
        switch self {
        case .github:  return Color(nsColor: .labelColor)
        case .nord:    return Color(red: 0.847, green: 0.871, blue: 0.914)   // #d8dee9
        case .dracula: return Color(red: 0.973, green: 0.973, blue: 0.949)   // #f8f8f2
        }
    }

    /// Subtle separator / divider color.
    var separator: Color {
        switch self {
        case .github:  return Color(nsColor: .separatorColor)
        case .nord:    return Color(red: 0.231, green: 0.259, blue: 0.322).opacity(0.7)
        case .dracula: return Color(red: 0.267, green: 0.278, blue: 0.353).opacity(0.7)
        }
    }

    // MARK: - NSColor variants for AppKit views

    var editorBackgroundNSColor: NSColor {
        switch self {
        case .github:  return .textBackgroundColor
        case .nord:    return NSColor(red: 0.180, green: 0.204, blue: 0.251, alpha: 1)
        case .dracula: return NSColor(red: 0.157, green: 0.165, blue: 0.212, alpha: 1)
        }
    }

    var foregroundNSColor: NSColor {
        switch self {
        case .github:  return .labelColor
        case .nord:    return NSColor(red: 0.847, green: 0.871, blue: 0.914, alpha: 1)
        case .dracula: return NSColor(red: 0.973, green: 0.973, blue: 0.949, alpha: 1)
        }
    }
}
