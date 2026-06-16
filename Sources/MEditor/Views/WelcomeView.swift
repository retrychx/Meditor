import SwiftUI

/// Welcome screen — pixel-art title card + typewriter subtitle + recent folders.
struct WelcomeView: View {
    let onOpenFolder: () -> Void
    var onOpenRecent: ((URL) -> Void)? = nil

    // MARK: - Animation state
    @State private var displayedChars: [Character] = Array("MEDITOR")
    @State private var locked: [Bool]      = Array(repeating: false, count: 7)
    @State private var subtitleText        = ""
    @State private var cursorVisible       = true
    @State private var showContent         = false
    @State private var firstCycleDone      = false

    // MARK: - Recent folders
    @State private var recentFolders: [URL] = []

    // MARK: - Constants
    private static let title     = Array("MEDITOR")
    private static let charset   = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#@&%!?")
    private static let subtitle  = "A minimal Markdown editor for macOS"
    private static let cardBg    = Color(red: 0.11, green: 0.12, blue: 0.15)
    private static let cardGlow  = Color(red: 0.23, green: 0.51, blue: 0.96).opacity(0.15)
    private static let auroraBlue = Color(red: 0.23, green: 0.51, blue: 0.96)

    // 5×7 pixel bitmaps
    private static let pixelFont: [Character: [[Bool]]] = [
        "M": [[1,0,0,0,1],[1,1,0,1,1],[1,0,1,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1]],
        "E": [[1,1,1,1,1],[1,0,0,0,0],[1,0,0,0,0],[1,1,1,1,0],[1,0,0,0,0],[1,0,0,0,0],[1,1,1,1,1]],
        "D": [[1,1,1,1,0],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,1,1,1,0]],
        "I": [[0,1,1,1,0],[0,0,1,0,0],[0,0,1,0,0],[0,0,1,0,0],[0,0,1,0,0],[0,0,1,0,0],[0,1,1,1,0]],
        "T": [[1,1,1,1,1],[0,0,1,0,0],[0,0,1,0,0],[0,0,1,0,0],[0,0,1,0,0],[0,0,1,0,0],[0,0,1,0,0]],
        "O": [[0,1,1,1,0],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[1,0,0,0,1],[0,1,1,1,0]],
        "R": [[1,1,1,1,0],[1,0,0,0,1],[1,0,0,0,1],[1,1,1,1,0],[1,0,1,0,0],[1,0,0,1,0],[1,0,0,0,1]],
    ].mapValues { $0.map { $0.map { $0 == 1 } } }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Craft-style: clean white/light background with subtle dot grid
            Color(nsColor: .textBackgroundColor)
                .ignoresSafeArea()
            DotGridBackground(opacity: 0.25)
                .ignoresSafeArea()

            HStack(spacing: 0) {
                // ── Left: branding + actions ──
                VStack(spacing: 0) {
                    Spacer()

                    // Pixel card
                    pixelCard
                        .padding(.bottom, DS.Space.xl)

                    // Subtitle typewriter
                    subtitleRow
                        .padding(.bottom, DS.Space.xl)

                    // CTA button
                    if showContent {
                        ctaButton
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    Spacer()

                    // Drop hint
                    if showContent {
                        Text(L("welcome.dropHint"))
                            .font(DS.Font.footnote)
                            .foregroundStyle(.quaternary)
                            .padding(.bottom, DS.Space.xl)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)

                // ── Divider ──
                if showContent && !recentFolders.isEmpty {
                    DS.Color.divider
                        .frame(width: 1, height: 260)
                        .padding(.vertical, DS.Space.xl)
                        .transition(.opacity)
                }

                // ── Right: recent folders ──
                if showContent && !recentFolders.isEmpty {
                    recentPanel
                        .frame(width: 220)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .padding(.horizontal, DS.Space.xxl)
        }
        .onAppear {
            loadRecentFolders()
            startCycle()
        }
    }

    // MARK: - Sub-views

    private var pixelCard: some View {
        HStack(spacing: 10) {
            ForEach(0..<7, id: \.self) { i in
                PixelCharView(
                    char: displayedChars[i],
                    font: Self.pixelFont,
                    color: .white,
                    opacity: locked[i] ? 1.0 : 0.25
                )
                .scaleEffect(locked[i] ? 1.0 : 0.88)
                .animation(DS.Motion.spring, value: locked[i])
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 32)
        .background {
            ZStack {
                // Base card
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .fill(Self.cardBg)

                // Top glass reflection
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.09), Color.clear],
                            startPoint: .top, endPoint: .center
                        )
                    )

                // Subtle glow at bottom
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.clear, Self.cardGlow],
                            startPoint: .top, endPoint: .bottom
                        )
                    )

                // Border
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), Color.white.opacity(0.04)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.28), radius: 20, x: 0, y: 8)
            .shadow(color: Self.auroraBlue.opacity(0.12), radius: 30, x: 0, y: 12)
        }
    }

    private var subtitleRow: some View {
        HStack(spacing: 0) {
            Text(subtitleText)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("|")
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.7))
                .opacity(cursorVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.4), value: cursorVisible)
        }
        .frame(height: 18)
    }

    private var ctaButton: some View {
        VStack(spacing: DS.Space.sm) {
            Button(action: onOpenFolder) {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 13, weight: .medium))
                    Text(L("menu.openFolder"))
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 9)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.accentColor)
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 8, y: 3)
                )
            }
            .buttonStyle(.plain)

            Text("⌘⇧O")
                .font(DS.Font.mono(10))
                .foregroundStyle(.tertiary)
        }
    }

    private var recentPanel: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("最近打开")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.leading, DS.Space.md)
                .padding(.bottom, DS.Space.xs)

            ForEach(recentFolders.prefix(6), id: \.path) { url in
                Button {
                    onOpenRecent?(url) ?? onOpenFolder()
                } label: {
                    HStack(spacing: DS.Space.sm) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange.opacity(0.8))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(url.lastPathComponent)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary.opacity(0.85))
                                .lineLimit(1)
                            Text(url.deletingLastPathComponent().abbreviatingWithTildeInPath)
                                .font(DS.Font.mono(9.5))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, DS.Space.md)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background {
                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .fill(Color.primary.opacity(0))
                }
                .hoverBrightness(0.0)
                .background(HoverRecentBackground())
            }

            Spacer()
        }
        .padding(.vertical, DS.Space.lg)
        .padding(.leading, DS.Space.lg)
    }

    // MARK: - Data

    private func loadRecentFolders() {
        // Read from NSDocumentController's recent documents (folders)
        let recents = NSDocumentController.shared.recentDocumentURLs
        recentFolders = recents.filter { url in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return isDir.boolValue
        }
        // If not enough, also check UserDefaults key "sidebar.recentFolders"
        if recentFolders.count < 3 {
            let extra = (UserDefaults.standard.array(forKey: "welcome.recentFolders") as? [String] ?? [])
                .compactMap { URL(string: $0) }
                .filter { !recentFolders.contains($0) }
            recentFolders.append(contentsOf: extra)
        }
    }

    // MARK: - Animation

    private func startCycle() {
        displayedChars = Self.title.map { _ in Self.charset.randomElement()! }
        locked = Array(repeating: false, count: 7)

        let shuffleTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { _ in
            for i in 0..<7 where !locked[i] {
                displayedChars[i] = Self.charset.randomElement()!
            }
        }

        for i in 0..<7 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18 + Double(i) * 0.085) {
                locked[i] = true
                displayedChars[i] = Self.title[i]
                if i == 6 {
                    shuffleTimer.invalidate()
                    if !firstCycleDone { startTyping() }
                    else               { scheduleNextCycle() }
                }
            }
        }

        if !firstCycleDone {
            Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { _ in
                cursorVisible.toggle()
            }
        }
    }

    private func startTyping() {
        var idx = 0
        Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { timer in
            if idx < Self.subtitle.count {
                subtitleText += String(
                    Self.subtitle[Self.subtitle.index(Self.subtitle.startIndex, offsetBy: idx)]
                )
                idx += 1
            } else {
                timer.invalidate()
                firstCycleDone = true
                withAnimation(DS.Motion.standard) { showContent = true }
                scheduleNextCycle()
            }
        }
    }

    private func scheduleNextCycle() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { startCycle() }
    }
}

// MARK: - Hover background helper

private struct HoverRecentBackground: View {
    @State private var hovered = false

    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
            .fill(hovered ? DS.Color.rowHover : Color.clear)
            .animation(DS.Motion.micro, value: hovered)
            .onHover { hovered = $0 }
    }
}

// MARK: - Pixel char renderer

private struct PixelCharView: View {
    let char: Character
    let font: [Character: [[Bool]]]
    let color: Color
    let opacity: Double

    private let px: CGFloat    = 7
    private let gap: CGFloat   = 1.5
    private let radius: CGFloat = 1.5

    var body: some View {
        let bitmap = font[char] ?? randomBitmap()
        Canvas { ctx, _ in
            for row in 0..<bitmap.count {
                for col in 0..<bitmap[row].count {
                    guard bitmap[row][col] else { continue }
                    let rect = CGRect(
                        x: CGFloat(col) * (px + gap),
                        y: CGFloat(row) * (px + gap),
                        width: px, height: px
                    )
                    ctx.fill(
                        Path(roundedRect: rect, cornerRadius: radius),
                        with: .color(color.opacity(opacity))
                    )
                }
            }
        }
        .frame(
            width:  5 * (px + gap) - gap,
            height: 7 * (px + gap) - gap
        )
    }

    private func randomBitmap() -> [[Bool]] {
        (0..<7).map { _ in (0..<5).map { _ in Bool.random() } }
    }
}

// MARK: - URL extension

private extension URL {
    var abbreviatingWithTildeInPath: String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
