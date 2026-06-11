import SwiftUI

/// Welcome screen with pixel-art styled title and typewriter animation.
struct WelcomeView: View {
    let onOpenFolder: () -> Void

    @State private var titleVisible = false
    @State private var subtitleText = ""
    @State private var cursorVisible = true
    @State private var showButton = false
    @State private var shimmerStart = UnitPoint(x: -1, y: 0.5)
    @State private var shimmerEnd = UnitPoint(x: -0.5, y: 0.5)

    private let fullSubtitle = "A minimal Markdown editor for macOS"

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Pixel-style title with shimmer sweep
            Text("MEditor")
                .font(.system(size: 56, weight: .black, design: .monospaced))
                .tracking(6)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.accentColor.opacity(0.7), .accentColor, .white, .accentColor, .accentColor.opacity(0.7)],
                        startPoint: shimmerStart,
                        endPoint: shimmerEnd
                    )
                )
                .opacity(titleVisible ? 1 : 0)
                .offset(y: titleVisible ? 0 : 10)
                .shadow(color: .accentColor.opacity(0.3), radius: titleVisible ? 12 : 0, y: 4)

            // Typewriter subtitle
            HStack(spacing: 0) {
                Text(subtitleText)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("|")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .opacity(cursorVisible ? 1 : 0)
            }
            .frame(height: 20)

            // Shortcut hints
            if showButton {
                VStack(spacing: 8) {
                    Button(action: onOpenFolder) {
                        Label(L("menu.openFolder"), systemImage: "folder")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)

                    Text("⌘⇧O")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer()

            // Bottom hint
            if showButton {
                Text(L("welcome.dropHint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)
                    .padding(.bottom, 20)
                    .transition(.opacity)
            }
        }
        .onAppear {
            startAnimations()
        }
    }

    private func startAnimations() {
        // 1. Title fades in
        withAnimation(.easeOut(duration: 0.5).delay(0.1)) {
            titleVisible = true
        }

        // 2. Shimmer sweep (repeating)
        withAnimation(.easeInOut(duration: 2.0).delay(0.6).repeatForever(autoreverses: false)) {
            shimmerStart = UnitPoint(x: 1.5, y: 0.5)
            shimmerEnd = UnitPoint(x: 2.0, y: 0.5)
        }

        // 2. Typewriter effect
        var charIndex = 0
        Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { timer in
            if charIndex < fullSubtitle.count {
                let idx = fullSubtitle.index(fullSubtitle.startIndex, offsetBy: charIndex)
                subtitleText += String(fullSubtitle[idx])
                charIndex += 1
            } else {
                timer.invalidate()
                // 3. Show button after typing finishes
                withAnimation(.easeOut(duration: 0.3)) {
                    showButton = true
                }
            }
        }

        // 3. Cursor blink
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            cursorVisible.toggle()
        }
    }
}
