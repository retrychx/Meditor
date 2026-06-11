import SwiftUI

/// Welcome screen with shuffle/decode text animation on title.
struct WelcomeView: View {
    let onOpenFolder: () -> Void

    @State private var displayedChars: [Character] = Array("MEditor")
    @State private var locked: [Bool] = Array(repeating: false, count: 7)
    @State private var animationDone = false
    @State private var showContent = false

    private static let title = Array("MEditor")
    private static let charset = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789#@&%")
    private static let titleColor = Color(red: 0.29, green: 0.62, blue: 0.96) // #4A9EF5

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Shuffle title
            HStack(spacing: 2) {
                ForEach(0..<7, id: \.self) { i in
                    Text(String(displayedChars[i]))
                        .font(.system(size: 52, weight: .bold, design: .monospaced))
                        .foregroundStyle(Self.titleColor)
                        .opacity(locked[i] ? 1.0 : 0.6)
                }
            }

            // Subtitle + button (appear after decode)
            if showContent {
                VStack(spacing: 16) {
                    Text(L("welcome.subtitle"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    Button(action: onOpenFolder) {
                        Label(L("menu.openFolder"), systemImage: "folder")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Self.titleColor)

                    Text("⌘⇧O")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .transition(.opacity.combined(with: .offset(y: 6)))
            }

            Spacer()

            if showContent {
                Text(L("welcome.dropHint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)
                    .padding(.bottom, 20)
            }
        }
        .onAppear { startShuffle() }
    }

    private func startShuffle() {
        guard !animationDone else {
            // Already played once this session — show static
            displayedChars = Self.title
            locked = Array(repeating: true, count: 7)
            showContent = true
            return
        }

        // Shuffle phase: randomize all chars every 30ms
        let shuffleTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            for i in 0..<7 where !locked[i] {
                displayedChars[i] = Self.charset.randomElement()!
            }
        }

        // Lock phase: lock one char every 80ms from left to right
        for i in 0..<7 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + Double(i) * 0.08) {
                locked[i] = true
                displayedChars[i] = Self.title[i]

                // All locked → stop and show content
                if i == 6 {
                    shuffleTimer.invalidate()
                    animationDone = true
                    withAnimation(.easeOut(duration: 0.25)) {
                        showContent = true
                    }
                }
            }
        }
    }
}
