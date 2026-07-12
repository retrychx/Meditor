import SwiftUI

// MARK: - Anchor

/// Reports the floating assistant button's bounds so the panel can "grow" out of it
/// (mirrors `SettingsAnchorKey` used by the in-app settings hero overlay).
struct AIAssistantAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

// MARK: - Brand palette

enum AIBrand {
    static let blue   = Color(hex: "4F7BF5")
    static let violet = Color(hex: "8B5CF6")
    static let pink   = Color(hex: "EC4899")
    static let orange = Color(hex: "FB923C")

    /// Linear blue → violet, used for the run button and gradient text.
    static let sweep = LinearGradient(
        colors: [blue, violet],
        startPoint: .leading, endPoint: .trailing
    )

    /// Full-spectrum angular ring used by the orb.
    static let ring = AngularGradient(
        gradient: Gradient(colors: [blue, violet, pink, orange, blue]),
        center: .center
    )
}

// MARK: - Brand orb

/// Multi-color ring mark used as the assistant's identity (Craft-style).
struct AIAssistantOrb: View {
    var size: CGFloat = 16
    var glow: Bool = false

    var body: some View {
        ZStack {
            if glow {
                Circle()
                    .fill(AIBrand.ring)
                    .frame(width: size, height: size)
                    .blur(radius: size * 0.45)
                    .opacity(0.55)
            }
            Circle()
                .strokeBorder(AIBrand.ring, lineWidth: max(2, size * 0.17))
            Circle()
                .fill(AIBrand.ring)
                .frame(width: size * 0.22, height: size * 0.22)
                .offset(y: -size * 0.33)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Floating button

/// Pill-shaped assistant launcher pinned to the bottom-trailing corner of the
/// document area. Reports its bounds via `AIAssistantAnchorKey` so the hero
/// overlay can expand from this exact location.
@MainActor
struct AIAssistantButton: View {
    @Environment(AppState.self) private var state
    @State private var hovered = false

    var body: some View {
        let theme = state.themeStore.current
        Button {
            state.showingAIAssistant = true
        } label: {
            HStack(spacing: 7) {
                AIAssistantOrb(size: 16, glow: true)
                Text(L("ai.assistant"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.craftPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            // Frosted "white glass" capsule — emulates iOS Liquid Glass
            // (the native .glassEffect API needs macOS 26; this works on 14+).
            .background(
                ZStack {
                    Capsule(style: .continuous).fill(.ultraThinMaterial)
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(theme.isDark ? 0.10 : 0.55))
                }
            )
            // Glassy top-lit rim highlight.
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.95), Color.white.opacity(0.22)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .blendMode(.plusLighter)
            )
            // Soft floating drop shadow + tight contact shadow.
            .shadow(color: .black.opacity(theme.isDark ? 0.40 : 0.18), radius: 14, x: 0, y: 6)
            .shadow(color: .black.opacity(theme.isDark ? 0.20 : 0.08), radius: 2, x: 0, y: 1)
            .scaleEffect(hovered ? 1.05 : 1)
            .brightness(hovered ? 0.04 : 0)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(L("ai.openAssistant"))
        .animation(DS.Motion.springFast, value: hovered)
        .anchorPreference(key: AIAssistantAnchorKey.self, value: .bounds) { $0 }
    }
}

// MARK: - Hero overlay

/// In-app "hero" presentation of the assistant panel. The panel scales + fades
/// out of the launcher's location with a spring and dims the rest of the window
/// behind it (matches `SettingsHeroOverlay`).
@MainActor
struct AIAssistantHeroOverlay: View {
    @Environment(AppState.self) private var state

    let originRect: CGRect
    let containerSize: CGSize

    @State private var shown = false

    private var panelWidth: CGFloat { min(420, max(320, containerSize.width - 32)) }
    private var panelHeight: CGFloat { min(620, max(380, containerSize.height - 88)) }

    private var anchorPoint: UnitPoint {
        guard containerSize.width > 0, containerSize.height > 0 else { return .bottomTrailing }
        return UnitPoint(
            x: max(0, min(1, originRect.midX / containerSize.width)),
            y: max(0, min(1, originRect.midY / containerSize.height))
        )
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Rectangle()
                .fill(Color.black.opacity(shown ? 0.30 : 0))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            AIAssistantPanel(onClose: { dismiss() })
                .frame(width: panelWidth, height: panelHeight)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.25), Color.white.opacity(0.06)],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .compositingGroup()
                .shadow(color: .black.opacity(0.32), radius: 24, x: 0, y: 12)
                .scaleEffect(shown ? 1 : 0.16, anchor: anchorPoint)
                .opacity(shown ? 1 : 0)
                .padding(.trailing, 16)
                .padding(.bottom, 16)
        }
        .task {
            // Commit the collapsed state for one frame, then spring open — so the
            // animation isn't coalesced into the initial insert (which skips it).
            try? await Task.sleep(nanoseconds: 16_000_000)
            withAnimation(.spring(response: 0.42, dampingFraction: 0.80)) { shown = true }
        }
        .onExitCommand { dismiss() }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            state.showingAIAssistant = false
        }
    }
}
