import SwiftUI

/// Reports the source button's bounds so the settings panel can "grow" out of it.
struct SettingsAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// In-app "hero" presentation of the settings panel.
///
/// Instead of opening a separate system window (which cannot be custom-animated),
/// the panel scales and fades out of the gear button's location with a spring,
/// dimming the rest of the window behind it.
@MainActor
struct SettingsHeroOverlay: View {
    @Environment(AppState.self) private var state

    /// Source button rect, in the overlay's coordinate space.
    let originRect: CGRect
    /// Size of the container the overlay fills.
    let containerSize: CGSize

    @State private var shown = false

    private var anchorPoint: UnitPoint {
        guard containerSize.width > 0, containerSize.height > 0 else { return .center }
        return UnitPoint(
            x: max(0, min(1, originRect.midX / containerSize.width)),
            y: max(0, min(1, originRect.midY / containerSize.height))
        )
    }

    var body: some View {
        ZStack {
            // Dim backdrop — click to dismiss
            Rectangle()
                .fill(Color.black.opacity(shown ? 0.28 : 0))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            SettingsView(embedded: true, onClose: { dismiss() })
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.34), radius: 34, x: 0, y: 14)
                .scaleEffect(shown ? 1 : 0.18, anchor: anchorPoint)
                .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.80)) { shown = true }
        }
        .onExitCommand { dismiss() }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            state.showingSettings = false
        }
    }
}
