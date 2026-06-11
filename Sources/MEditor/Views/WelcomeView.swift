import SwiftUI

/// Welcome screen with shuffle title + typewriter subtitle.
struct WelcomeView: View {
    let onOpenFolder: () -> Void

    @State private var displayedChars: [Character] = Array("MEditor")
    @State private var locked: [Bool] = Array(repeating: false, count: 7)
    @State private var subtitleText = ""
    @State private var cursorVisible = true
    @State private var showButton = false

    private static let title = Array("MEditor")
    private static let charset = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789#@&%!?")
    private static let subtitle = "A minimal Markdown editor for macOS"

    // 极光蓝
    private static let auroraBlue = Color(red: 0.0, green: 0.75, blue: 0.95) // #00BFF2

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Shuffle title
            HStack(spacing: 2) {
                ForEach(0..<7, id: \.self) { i in
                    Text(String(displayedChars[i]))
                        .font(.system(size: 52, weight: .bold, design: .monospaced))
                        .foregroundStyle(Self.auroraBlue)
                        .opacity(locked[i] ? 1.0 : 0.5)
                }
            }

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

            // Button
            if showButton {
                VStack(spacing: 8) {
                    Button(action: onOpenFolder) {
                        Label(L("menu.openFolder"), systemImage: "folder")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Self.auroraBlue)

                    Text("⌘⇧O")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .transition(.opacity.combined(with: .offset(y: 6)))
            }

            Spacer()

            if showButton {
                Text(L("welcome.dropHint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)
                    .padding(.bottom, 20)
            }
        }
        .onAppear { startAnimations() }
    }

    private func startAnimations() {
        // Reset state (plays every time view appears)
        displayedChars = Self.title.map { _ in Self.charset.randomElement()! }
        locked = Array(repeating: false, count: 7)
        subtitleText = ""
        showButton = false

        // 1. Shuffle title
        let shuffleTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            for i in 0..<7 where !locked[i] {
                displayedChars[i] = Self.charset.randomElement()!
            }
        }

        // Lock chars left-to-right
        for i in 0..<7 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 + Double(i) * 0.08) {
                locked[i] = true
                displayedChars[i] = Self.title[i]
                if i == 6 { shuffleTimer.invalidate(); startTyping() }
            }
        }

        // Cursor blink
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            cursorVisible.toggle()
        }
    }

    private func startTyping() {
        // 2. Typewriter subtitle after title decode
        var charIndex = 0
        Timer.scheduledTimer(withTimeInterval: 0.035, repeats: true) { timer in
            if charIndex < Self.subtitle.count {
                let idx = Self.subtitle.index(Self.subtitle.startIndex, offsetBy: charIndex)
                subtitleText += String(Self.subtitle[idx])
                charIndex += 1
            } else {
                timer.invalidate()
                withAnimation(.easeOut(duration: 0.25)) {
                    showButton = true
                }
            }
        }
    }
}
