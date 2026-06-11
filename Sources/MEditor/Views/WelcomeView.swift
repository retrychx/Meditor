import SwiftUI

/// Welcome screen with pixel-art styled title and typewriter animation.
struct WelcomeView: View {
    let onOpenFolder: () -> Void

    @State private var titleVisible = false
    @State private var subtitleText = ""
    @State private var cursorVisible = true
    @State private var showButton = false

    private let fullSubtitle = "A minimal Markdown editor for macOS"

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Pixel-style title
            Text("MEditor")
                .font(.system(size: 42, weight: .black, design: .monospaced))
                .tracking(4)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.accentColor, .accentColor.opacity(0.6)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .opacity(titleVisible ? 1 : 0)
                .offset(y: titleVisible ? 0 : 8)

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
        withAnimation(.easeOut(duration: 0.4).delay(0.1)) {
            titleVisible = true
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
