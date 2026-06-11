import SwiftUI

/// Welcome screen with pixel-art title + shuffle animation.
struct WelcomeView: View {
    let onOpenFolder: () -> Void

    @State private var displayedChars: [Character] = Array("MEditor")
    @State private var locked: [Bool] = Array(repeating: false, count: 7)
    @State private var subtitleText = ""
    @State private var cursorVisible = true
    @State private var showButton = false
    @State private var firstCycleDone = false

    private static let title = Array("MEditor")
    private static let charset = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789#@&%")
    private static let subtitle = "A minimal Markdown editor for macOS"
    private static let auroraBlue = Color(red: 0.23, green: 0.51, blue: 0.96)

    // 5x7 pixel font bitmaps for "MEditor"
    private static let pixelFont: [Character: [[Bool]]] = [
        "M": [
            [true,false,false,false,true],
            [true,true,false,true,true],
            [true,false,true,false,true],
            [true,false,false,false,true],
            [true,false,false,false,true],
            [true,false,false,false,true],
            [true,false,false,false,true],
        ],
        "E": [
            [true,true,true,true,true],
            [true,false,false,false,false],
            [true,false,false,false,false],
            [true,true,true,true,false],
            [true,false,false,false,false],
            [true,false,false,false,false],
            [true,true,true,true,true],
        ],
        "d": [
            [false,false,false,false,true],
            [false,false,false,false,true],
            [false,true,true,false,true],
            [true,false,false,true,true],
            [true,false,false,false,true],
            [true,false,false,true,true],
            [false,true,true,false,true],
        ],
        "i": [
            [false,false,true,false,false],
            [false,false,false,false,false],
            [false,true,true,false,false],
            [false,false,true,false,false],
            [false,false,true,false,false],
            [false,false,true,false,false],
            [false,true,true,true,false],
        ],
        "t": [
            [false,false,true,false,false],
            [false,false,true,false,false],
            [false,true,true,true,false],
            [false,false,true,false,false],
            [false,false,true,false,false],
            [false,false,true,false,false],
            [false,false,false,true,true],
        ],
        "o": [
            [false,false,false,false,false],
            [false,false,false,false,false],
            [false,true,true,true,false],
            [true,false,false,false,true],
            [true,false,false,false,true],
            [true,false,false,false,true],
            [false,true,true,true,false],
        ],
        "r": [
            [false,false,false,false,false],
            [false,false,false,false,false],
            [true,false,true,true,false],
            [true,true,false,false,true],
            [true,false,false,false,false],
            [true,false,false,false,false],
            [true,false,false,false,false],
        ],
    ]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Pixel title
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    PixelCharView(
                        char: displayedChars[i],
                        font: Self.pixelFont,
                        color: Self.auroraBlue,
                        opacity: locked[i] ? 1.0 : 0.4
                    )
                }
            }

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

            // Button (stays after first cycle)
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

        // Shuffle
        let shuffleTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { timer in
            for i in 0..<7 where !locked[i] {
                displayedChars[i] = Self.charset.randomElement()!
            }
        }

        // Lock left-to-right
        for i in 0..<7 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + Double(i) * 0.08) {
                locked[i] = true
                displayedChars[i] = Self.title[i]
                if i == 6 {
                    shuffleTimer.invalidate()
                    if !firstCycleDone { startTyping() }
                    else { scheduleNextCycle() }
                }
            }
        }

        // Cursor blink (only start once)
        if !firstCycleDone {
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                cursorVisible.toggle()
            }
        }
    }

    private func startTyping() {
        var charIndex = 0
        Timer.scheduledTimer(withTimeInterval: 0.035, repeats: true) { timer in
            if charIndex < Self.subtitle.count {
                let idx = Self.subtitle.index(Self.subtitle.startIndex, offsetBy: charIndex)
                subtitleText += String(Self.subtitle[idx])
                charIndex += 1
            } else {
                timer.invalidate()
                firstCycleDone = true
                withAnimation(.easeOut(duration: 0.2)) { showButton = true }
                scheduleNextCycle()
            }
        }
    }

    private func scheduleNextCycle() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            startCycle()
        }
    }
}

// MARK: - Pixel character renderer

private struct PixelCharView: View {
    let char: Character
    let font: [Character: [[Bool]]]
    let color: Color
    let opacity: Double

    private let pixelSize: CGFloat = 5
    private let gap: CGFloat = 1

    var body: some View {
        let bitmap = font[char] ?? fallbackBitmap
        Canvas { context, size in
            for row in 0..<bitmap.count {
                for col in 0..<bitmap[row].count {
                    if bitmap[row][col] {
                        let rect = CGRect(
                            x: CGFloat(col) * (pixelSize + gap),
                            y: CGFloat(row) * (pixelSize + gap),
                            width: pixelSize,
                            height: pixelSize
                        )
                        context.fill(Path(rect), with: .color(color.opacity(opacity)))
                    }
                }
            }
        }
        .frame(width: CGFloat(5) * (pixelSize + gap) - gap,
               height: CGFloat(7) * (pixelSize + gap) - gap)
    }

    // Random block pattern for shuffle characters
    private var fallbackBitmap: [[Bool]] {
        (0..<7).map { _ in (0..<5).map { _ in Bool.random() } }
    }
}
