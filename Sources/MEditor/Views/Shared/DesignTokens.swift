import SwiftUI

// MARK: - Design System Tokens
//
// Single source of truth for all colors, spacing, typography, and motion.
// Use these constants everywhere — never hardcode values in views.

enum DS {

    // MARK: - Spacing (4-pt grid)
    enum Space {
        static let xxs: CGFloat = 2
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 12
        static let lg:  CGFloat = 16
        static let xl:  CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Corner Radius
    enum Radius {
        static let xs:  CGFloat = 3
        static let sm:  CGFloat = 5
        static let md:  CGFloat = 8
        static let lg:  CGFloat = 12
        static let xl:  CGFloat = 16
        static let full: CGFloat = 999
    }

    // MARK: - Typography
    enum Font {
        /// UI labels, menus
        static func label(_ size: CGFloat = 13, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .default)
        }
        /// Monospaced — status bar, paths, sizes
        static func mono(_ size: CGFloat = 11, weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            .system(size: size, weight: weight, design: .monospaced)
        }
        /// Section headers, panel titles
        static var caption: SwiftUI.Font { .system(size: 11, weight: .medium) }
        static var footnote: SwiftUI.Font { .system(size: 10.5, weight: .regular) }
    }

    // MARK: - Animation
    enum Motion {
        static let micro:    Animation = .easeOut(duration: 0.10)
        static let fast:     Animation = .easeOut(duration: 0.15)
        static let standard: Animation = .easeOut(duration: 0.22)
        static let spring:   Animation = .spring(response: 0.28, dampingFraction: 0.72)
        static let springFast: Animation = .spring(response: 0.18, dampingFraction: 0.75)
        /// Smoother spring for panel slide in/out (sidebar collapse/expand).
        static let panel: Animation = .spring(response: 0.34, dampingFraction: 0.86)
    }

    // MARK: - Elevation (shadow system)
    enum Shadow {
        /// Cards, sidebar header
        static var sm: some View {
            EmptyView()
        }
        static func card() -> some ShapeStyle { AnyShapeStyle(SwiftUI.Color.black.opacity(0.07)) }

        static let cardRadius: CGFloat = 8
        static let cardY: CGFloat = 2

        static let popoverRadius: CGFloat = 16
        static let popoverY: CGFloat = 6
        static let popoverOpacity: Double = 0.14
    }

    // MARK: - Semantic Colors
    enum Color {
        /// Sidebar background — slightly offset from editor
        static var sidebarBg: SwiftUI.Color {
            SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(white: 0.135, alpha: 1)
                    : NSColor(white: 0.952, alpha: 1)
            })
        }

        /// Editor background
        static var editorBg: SwiftUI.Color {
            SwiftUI.Color(nsColor: .textBackgroundColor)
        }

        /// Tab bar / chrome background
        static var chromeBg: SwiftUI.Color {
            SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(white: 0.115, alpha: 1)
                    : NSColor(white: 0.938, alpha: 1)
            })
        }

        /// Status bar background
        static var statusBg: SwiftUI.Color {
            SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(white: 0.10, alpha: 0.92)
                    : NSColor(white: 0.92, alpha: 0.92)
            })
        }

        /// Divider between panels
        static var divider: SwiftUI.Color {
            SwiftUI.Color.primary.opacity(0.08)
        }

        /// File row hover
        static var rowHover: SwiftUI.Color {
            SwiftUI.Color.primary.opacity(0.055)
        }

        /// File row selected fill
        static var rowSelected: SwiftUI.Color {
            SwiftUI.Color.accentColor.opacity(0.13)
        }

        /// Status bar pill background
        static var pillBg: SwiftUI.Color {
            SwiftUI.Color.primary.opacity(0.06)
        }
    }
}

// MARK: - View Modifiers

/// Micro-interaction hover brightness shift
struct HoverBrightness: ViewModifier {
    @State private var hovered = false
    var amount: Double

    func body(content: Content) -> some View {
        content
            .brightness(hovered ? amount : 0)
            .onHover { hovered = $0 }
            .animation(DS.Motion.micro, value: hovered)
    }
}

extension View {
    func hoverBrightness(_ amount: Double = 0.06) -> some View {
        modifier(HoverBrightness(amount: amount))
    }
}

/// Accent selection indicator (left edge line)
struct SelectionAccentLine: View {
    var color: SwiftUI.Color = .accentColor
    var verticalPad: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 2.5)
            .padding(.vertical, verticalPad)
    }
}

/// Status-bar pill capsule
struct StatusPill: View {
    let text: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .medium))
            }
            Text(text)
                .font(DS.Font.mono(10.5))
                .kerning(-0.2)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(
            Capsule()
                .fill(DS.Color.pillBg)
        )
    }
}
