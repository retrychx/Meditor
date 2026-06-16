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

    /// Chrome background: sidebar + top bar. Craft-style palette.
    var chromeBackground: Color {
        switch self {
        case .github:
            // Craft-style sidebar: visibly darker than editor white
            return Color(red: 0.933, green: 0.933, blue: 0.933)  // #EEEEEE
        case .nord:
            return Color(red: 0.141, green: 0.161, blue: 0.200)  // #242933
        case .dracula:
            return Color(red: 0.129, green: 0.133, blue: 0.173)  // #21222c
        }
    }

    /// Window canvas behind everything — slightly deeper than sidebar.
    /// Craft uses this to make the editor card "float".
    var windowBackground: Color {
        switch self {
        case .github:
            return Color(nsColor: .textBackgroundColor)           // pure white editor
        case .nord:
            return Color(red: 0.118, green: 0.133, blue: 0.165)  // #1e2229
        case .dracula:
            return Color(red: 0.106, green: 0.110, blue: 0.145)  // #1b1c25
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

    // MARK: - Craft-extracted interaction tokens (light #1F2225 / dark #F4F4F4)

    /// Primary text — Craft: #1F2225 warm near-black (not pure black)
    var craftPrimary: Color {
        switch self {
        case .github:  return Color(red: 0.122, green: 0.133, blue: 0.145)  // #1F2225
        case .nord:    return Color(red: 0.847, green: 0.871, blue: 0.914)  // #D8DEE9
        case .dracula: return Color(red: 0.973, green: 0.973, blue: 0.949)  // #F8F8F2
        }
    }

    /// Secondary text — Craft: #9EA4AA
    var craftSecondary: Color {
        switch self {
        case .github:  return Color(red: 0.620, green: 0.643, blue: 0.667)  // #9EA4AA
        case .nord:    return Color(red: 0.600, green: 0.627, blue: 0.667)  // nord secondary
        case .dracula: return Color(red: 0.620, green: 0.643, blue: 0.667)  // dracula secondary
        }
    }

    /// Hover overlay — Craft: rgba(31,34,37,0.08)
    var craftHover: Color {
        switch self {
        case .github:  return Color(red: 0.122, green: 0.133, blue: 0.145).opacity(0.08)
        case .nord:    return Color.white.opacity(0.06)
        case .dracula: return Color.white.opacity(0.06)
        }
    }

    /// Selected overlay — Craft: rgba(31,34,37,0.13)
    var craftSelected: Color {
        switch self {
        case .github:  return Color(red: 0.122, green: 0.133, blue: 0.145).opacity(0.13)
        case .nord:    return Color.white.opacity(0.1)
        case .dracula: return Color.white.opacity(0.1)
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
