import SwiftUI

/// Welcome screen with pixel-art title on dark card + shuffle animation.
struct WelcomeView: View {
    let onOpenFolder: () -> Void

    @State private var displayedChars: [Character] = Array("MEDITOR")
    @State private var locked: [Bool] = Array(repeating: false, count: 7)
    @State private var subtitleText = ""
    @State private var cursorVisible = true
    @State private var showButton = false
    @State private var firstCycleDone = false

    private static let title = Array("MEDITOR")
    private static let charset = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#@&%!?")
    private static let subtitle = "A minimal Markdown editor for macOS"
    private static let auroraBlue = Color(red: 0.23, green: 0.51, blue: 0.96)
    private static let cardBg = Color(red: 0.11, green: 0.12, blue: 0.15) // #1C1F26
    private static let pixelColor = Color.white

    // 5x7 pixel bitmaps — ALL CAPS
    private static let pixelFont: [Character: [[Bool]]] = [
        "M": [[1,0,0,0,1],[1,1,0,1,1],[1,0,1,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1]],
        "E": [[1,1,1,1,1],[1,0,0,0,0],[1,0,0,0,0],[1,1,1,1,0],[1,0,0,0,0],[1,0,0,0,0],[1,1,1,1,1]],
        "D": [[1,1,1,1,0],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,1,1,1,0]],
        "I": [[0,1,1,1,0],[0,0,1,0,0],[0,0,1,0,0],[0,0,1,0,0],[0,0,1,0,0],[0,0,1,0,0],[0,1,1,1,0]],
        "T": [[1,1,1,1,1],[0,0,1,0,0],[0,0,1,0,0],[0,0,1,0,0],[0,0,1,0,0],[0,0,1,0,0],[0,0,1,0,0]],
        "O": [[0,1,1,1,0],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[0,1,1,1,0]],
        "R": [[1,1,1,1,0],[1,0,0,0,1],[1,0,0,0,1],[1,1,1,1,0],[1,0,1,0,0],[1,0,0,1,0],[1,0,0,0,1]],
    ].mapValues { $0.map { $0.map { $0 == 1 } } }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            // Dark card with pixel title
            HStack(spacing: 10) {
                ForEach(0..<7, id: \.self) { i in
                    PixelCharView(
                        char: displayedChars[i],
                        font: Self.pixelFont,
                        color: Self.pixelColor,
                        opacity: locked[i] ? 1.0 : 0.3
                    )
                    .scaleEffect(locked[i] ? 1.0 : 0.92)
                    .animation(.spring(response: 0.2, dampingFraction: 0.65), value: locked[i])
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Self.cardBg)
                    .shadow(color: Self.auroraBlue.opacity(0.15), radius: 20, y: 8)
            )

            // Typewriter subtitle
            HStack(spacing: 0) {
                Text(subtitleText)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("|")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .opacity(cursorVisible ? 1 : 0)
            }
            .frame(height: 18)

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
                .transition(.opacity)
            }

            Spacer()

            if showButton {
                Text(L("welcome.dropHint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)
                    .padding(.bottom, 20)
            }
        }
        .onAppear { startCycle() }
    }

    private func startCycle() {
        displayedChars = Self.title.map { _ in Self.charset.randomElement()! }
        locked = Array(repeating: false, count: 7)
        if !firstCycleDone { subtitleText = "" }

        let shuffleTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { _ in
            for i in 0..<7 where !locked[i] {
                displayedChars[i] = Self.charset.randomElement()!
            }
        }

        for i in 0..<7 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2 + Double(i) * 0.09) {
                locked[i] = true
                displayedChars[i] = Self.title[i]
                if i == 6 {
                    shuffleTimer.invalidate()
                    if !firstCycleDone { startTyping() }
                    else { scheduleNextCycle() }
                }
            }
        }

        if !firstCycleDone {
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                cursorVisible.toggle()
            }
        }
    }

    private func startTyping() {
        var idx = 0
        Timer.scheduledTimer(withTimeInterval: 0.035, repeats: true) { timer in
            if idx < Self.subtitle.count {
                subtitleText += String(Self.subtitle[Self.subtitle.index(Self.subtitle.startIndex, offsetBy: idx)])
                idx += 1
            } else {
                timer.invalidate()
                firstCycleDone = true
                withAnimation(.easeOut(duration: 0.2)) { showButton = true }
                scheduleNextCycle()
            }
        }
    }

    private func scheduleNextCycle() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { startCycle() }
    }
}

// MARK: - Pixel renderer

private struct PixelCharView: View {
    let char: Character
    let font: [Character: [[Bool]]]
    let color: Color
    let opacity: Double

    private let px: CGFloat = 7
    private let gap: CGFloat = 2
    private let radius: CGFloat = 1.5

    var body: some View {
        let bitmap = font[char] ?? randomBitmap()
        Canvas { ctx, _ in
            for row in 0..<bitmap.count {
                for col in 0..<bitmap[row].count {
                    if bitmap[row][col] {
                        let rect = CGRect(
                            x: CGFloat(col) * (px + gap),
                            y: CGFloat(row) * (px + gap),
                            width: px, height: px
                        )
                        let path = Path(roundedRect: rect, cornerRadius: radius)
                        ctx.fill(path, with: .color(color.opacity(opacity)))
                    }
                }
            }
        }
        .frame(width: 5 * (px + gap) - gap, height: 7 * (px + gap) - gap)
    }

    private func randomBitmap() -> [[Bool]] {
        (0..<7).map { _ in (0..<5).map { _ in Bool.random() } }
    }
}
