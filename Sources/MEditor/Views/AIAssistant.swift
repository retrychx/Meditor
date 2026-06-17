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

/// Selectable accent treatment for the assistant's prominent controls.
/// `system` uses the app accent (blue); `shadcn` uses a mono near-black / near-white
/// palette (shadcn/ui "primary": light #18181B, dark #FAFAFA).
enum AIAccentStyle: String, CaseIterable, Identifiable {
    case system
    case shadcn

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .system: return "ai.accent.system"
        case .shadcn: return "ai.accent.mono"
        }
    }

    /// Button / bubble fill.
    func fill(_ theme: PreviewTheme) -> Color {
        switch self {
        case .system: return .accentColor
        case .shadcn: return theme.isDark ? Color(hex: "FAFAFA") : Color(hex: "18181B")
        }
    }

    /// Foreground (text/icon) drawn on top of `fill`.
    func onFill(_ theme: PreviewTheme) -> Color {
        switch self {
        case .system: return .white
        case .shadcn: return theme.isDark ? Color(hex: "18181B") : Color(hex: "FAFAFA")
        }
    }

    /// Swatch shown in the header switcher.
    func swatch(_ theme: PreviewTheme) -> Color { fill(theme) }

    @MainActor
    static func current(_ settings: AppSettings) -> AIAccentStyle {
        AIAccentStyle(rawValue: settings.aiAccentStyle) ?? .system
    }
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
                .shadow(color: .black.opacity(0.36), radius: 38, x: 0, y: 16)
                .scaleEffect(shown ? 1 : 0.15, anchor: anchorPoint)
                .opacity(shown ? 1 : 0)
                .padding(.trailing, 16)
                .padding(.bottom, 16)
        }
        .onAppear {
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

// MARK: - Models

private struct AIChatMessage: Identifiable, Codable {
    enum Role: String, Codable { case user, assistant }
    var id = UUID()
    let role: Role
    var text: String
}

private struct AISession: Identifiable, Codable {
    var id = UUID()
    var title: String = ""
    var messages: [AIChatMessage] = []
    var updatedAt: Date = .now
}

/// Persistent, multi-session conversation state. Kept outside the panel `View`
/// so chats survive the panel being recreated, and persisted to disk so they
/// survive app relaunches. "New chat" archives the current session into history;
/// the header list lets the user switch back.
@MainActor
@Observable
final class AIConversation {
    static let shared = AIConversation()

    fileprivate var sessions: [AISession] = []
    fileprivate var activeID: UUID
    var input: String = ""
    var isResponding = false
    var showAllSuggestions = false

    private static let fileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MEditor", isDirectory: true)
        return base.appendingPathComponent("ai-sessions.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode([AISession].self, from: data),
           !saved.isEmpty {
            sessions = saved
            activeID = saved[0].id
        } else {
            let fresh = AISession()
            sessions = [fresh]
            activeID = fresh.id
        }
    }

    // MARK: Active session access

    fileprivate var activeIndex: Int { sessions.firstIndex { $0.id == activeID } ?? 0 }

    fileprivate var messages: [AIChatMessage] {
        get { sessions.indices.contains(activeIndex) ? sessions[activeIndex].messages : [] }
        set {
            guard sessions.indices.contains(activeIndex) else { return }
            sessions[activeIndex].messages = newValue
            sessions[activeIndex].updatedAt = .now
            if sessions[activeIndex].title.isEmpty,
               let firstUser = newValue.first(where: { $0.role == .user }) {
                sessions[activeIndex].title = String(firstUser.text.prefix(40))
            }
        }
    }

    /// History ordered most-recently-updated first.
    fileprivate var history: [AISession] {
        sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: Session lifecycle

    /// Start a fresh session. Reuses the current one if it's already empty.
    func newSession() {
        input = ""
        if sessions.indices.contains(activeIndex), sessions[activeIndex].messages.isEmpty {
            return
        }
        let fresh = AISession()
        sessions.insert(fresh, at: 0)
        activeID = fresh.id
        persist()
    }

    fileprivate func activate(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        activeID = id
        input = ""
    }

    fileprivate func delete(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if sessions.isEmpty {
            let fresh = AISession()
            sessions = [fresh]
            activeID = fresh.id
        } else if !sessions.contains(where: { $0.id == activeID }) {
            activeID = sessions[0].id
        }
        persist()
    }

    func persist() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        let dir = Self.fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}

private struct AISuggestion: Identifiable {
    let id = UUID()
    let icon: String
    let titleKey: String
    let tint: Color
    var promptKey: String? = nil
}

// MARK: - Chat / input panel

/// The assistant page revealed by the hero overlay: a brand greeting, a
/// suggestions / transcript body, and a compose card. No network is performed —
/// replies are a local UI preview placeholder (the app is offline by design).
struct AIAssistantPanel: View {
    @Environment(AppState.self) private var state
    let onClose: () -> Void

    @State private var settings = AppSettings.shared
    @State private var convo = AIConversation.shared
    @State private var showHistory = false
    @FocusState private var inputFocused: Bool

    private var theme: PreviewTheme { state.themeStore.current }
    private var accent: AIAccentStyle { AIAccentStyle.current(settings) }

    private static let primarySuggestions: [AISuggestion] = [
        .init(icon: "sparkles", titleKey: "ai.suggest.whatCanYouDo", tint: Color.appAccent, promptKey: "ai.prompt.whatCanYouDo"),
        .init(icon: "text.alignleft", titleKey: "ai.suggest.summarize", tint: AIBrand.blue, promptKey: "ai.prompt.summarize"),
        .init(icon: "lightbulb.fill", titleKey: "ai.suggest.improveClarity", tint: Color(hex: "F59E0B"), promptKey: "ai.prompt.improveClarity"),
        .init(icon: "checkmark.seal.fill", titleKey: "ai.suggest.fixGrammar", tint: Color(hex: "10B981"), promptKey: "ai.prompt.fixGrammar"),
        .init(icon: "globe", titleKey: "ai.suggest.translate", tint: Color(hex: "06B6D4"), promptKey: "ai.prompt.translate"),
        .init(icon: "paintbrush.fill", titleKey: "ai.suggest.styleDocument", tint: AIBrand.pink, promptKey: "ai.prompt.styleDocument")
    ]

    private static let moreSuggestions: [AISuggestion] = [
        .init(icon: "list.bullet.rectangle.fill", titleKey: "ai.suggest.outline", tint: Color(hex: "3B82F6"), promptKey: "ai.prompt.outline"),
        .init(icon: "arrow.down.right.and.arrow.up.left", titleKey: "ai.suggest.shorten", tint: AIBrand.orange, promptKey: "ai.prompt.shorten"),
        .init(icon: "arrow.up.left.and.arrow.down.right", titleKey: "ai.suggest.expand", tint: Color(hex: "3B82F6"), promptKey: "ai.prompt.expand"),
        .init(icon: "tablecells.fill", titleKey: "ai.suggest.toTable", tint: Color(hex: "14B8A6"), promptKey: "ai.prompt.toTable")
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            composerFooter
        }
        .background(theme.editorBackground)
        .onAppear {
            DispatchQueue.main.async { inputFocused = true }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            AIHeaderButton(icon: "clock.arrow.circlepath", help: L("ai.history"), theme: theme) {
                showHistory.toggle()
            }
            .popover(isPresented: $showHistory, arrowEdge: .bottom) {
                AIHistoryView(convo: convo, theme: theme) { showHistory = false }
            }
            Spacer()
            Button(action: newChat) {
                HStack(spacing: 5) {
                    Image(systemName: "plus.bubble")
                        .font(.system(size: 11, weight: .semibold))
                    Text(L("ai.newChat"))
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(theme.craftPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule(style: .continuous).fill(theme.craftHover))
                .overlay(Capsule().strokeBorder(theme.separator.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(L("ai.newChat"))
            Spacer()
            AIHeaderButton(icon: "xmark", help: L("common.close"), theme: theme, action: onClose)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(
            theme.editorBackground
                .overlay(alignment: .bottom) { theme.separator.opacity(0.4).frame(height: 1) }
        )
    }

    // MARK: Body

    @ViewBuilder
    private var content: some View {
        if convo.messages.isEmpty {
            suggestionsView
        } else {
            transcriptView
        }
    }

    private var suggestionsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                greeting
                    .padding(.top, 18)
                    .padding(.bottom, 20)

                sectionHeader("ai.section.suggestions")

                ForEach(Self.primarySuggestions) { s in
                    AISuggestionRow(suggestion: s, theme: theme) { apply(s) }
                }

                if convo.showAllSuggestions {
                    ForEach(Self.moreSuggestions) { s in
                        AISuggestionRow(suggestion: s, theme: theme) { apply(s) }
                    }
                } else {
                    showMoreRow
                }

                sectionHeader("ai.section.yourPrompts")
                    .padding(.top, 6)
                AISuggestionRow(
                    suggestion: .init(icon: "plus.circle.fill", titleKey: "ai.createCustomPrompt", tint: theme.craftSecondary),
                    theme: theme
                ) {
                    inputFocused = true
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            DotGridBackground(opacity: theme.isDark ? 0.10 : 0.18)
                .allowsHitTesting(false)
        )
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 12) {
            AIAssistantOrb(size: 44, glow: true)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("ai.greeting"))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.craftPrimary)
                Text(L("ai.greetingSub"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.craftSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }

    private var showMoreRow: some View {
        Button {
            withAnimation(DS.Motion.fast) { convo.showAllSuggestions = true }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(theme.craftSecondary)
                Text(L("ai.showMore", Self.moreSuggestions.count))
                    .font(.system(size: 13))
                    .foregroundStyle(theme.craftSecondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var transcriptView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(convo.messages) { message in
                        if !message.text.isEmpty {
                            bubble(message).id(message.id)
                        }
                    }
                    if convo.isResponding && (convo.messages.last?.text.isEmpty ?? true) {
                        HStack(spacing: 8) {
                            AIAssistantOrb(size: 18, glow: true)
                            Text(L("ai.thinking"))
                                .font(.system(size: 12.5))
                                .foregroundStyle(theme.craftSecondary)
                            TypingDots(color: theme.craftSecondary)
                        }
                    }
                    // Bottom anchor — ensures the last line fully clears the
                    // composer and that scroll-to-end reaches the true bottom.
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: convo.messages.count) { _, _ in scrollToEnd(proxy) }
            .onChange(of: convo.messages.last?.text) { _, _ in scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(DS.Motion.standard) { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    private func bubble(_ message: AIChatMessage) -> some View {
        HStack(alignment: .top, spacing: 9) {
            if message.role == .user {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.system(size: 13))
                    .foregroundStyle(accent.onFill(theme))
                    .textSelection(.enabled)
                    .lineSpacing(3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(accent.fill(theme))
                    )
            } else {
                AIAssistantOrb(size: 20, glow: true).padding(.top, 1)
                MarkdownText(
                    markdown: message.text,
                    textColor: theme.craftPrimary,
                    secondaryColor: theme.craftSecondary,
                    codeBackground: theme.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.045),
                    accent: Color.appAccent
                )
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(theme.isDark ? Color.white.opacity(0.03) : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(theme.separator.opacity(theme.isDark ? 0.5 : 0.7), lineWidth: 1)
                )
                .shadow(color: .black.opacity(theme.isDark ? 0.18 : 0.04), radius: 5, x: 0, y: 1)
            }
        }
    }

    // MARK: Composer

    private var composerFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Primary prompt area — clean, sitting directly on the frosted card.
            TextField(L("ai.inputPlaceholder"), text: Binding(
                get: { convo.input }, set: { convo.input = $0 }
            ), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .lineLimit(1...6)
                .focused($inputFocused)
                .onSubmit(send)
                .padding(.horizontal, 2)
                .padding(.top, 2)

            // Toolbar row: context chip + attach on the left, send on the right.
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.craftSecondary)
                    Text(documentName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.craftPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule(style: .continuous).fill(theme.craftHover))
                .overlay(Capsule().strokeBorder(theme.separator.opacity(0.4), lineWidth: 0.5))
                .frame(maxWidth: 180, alignment: .leading)

                AICircleButton(icon: "paperclip", theme: theme) { inputFocused = true }

                Spacer(minLength: 4)

                Button(action: send) {
                    HStack(spacing: 5) {
                        if convo.isResponding {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12, weight: .bold))
                        } else {
                            Text(L("ai.execute"))
                                .font(.system(size: 12.5, weight: .semibold))
                            Image(systemName: "arrow.up")
                                .font(.system(size: 11, weight: .bold))
                        }
                    }
                    .foregroundStyle(canSend ? accent.onFill(theme) : Color.white.opacity(0.9))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(canSend ? AnyShapeStyle(accent.fill(theme))
                                          : AnyShapeStyle(Color.gray.opacity(0.32)))
                    )
                    .shadow(color: accent.fill(theme).opacity(canSend ? 0.28 : 0), radius: 7, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!canSend)
                .animation(DS.Motion.fast, value: canSend)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                // White frosted sheen over the blur → "white glass".
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(theme.isDark ? 0.10 : 0.60))
                )
                // Thin top-lit glass hairline.
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: theme.isDark
                                    ? [Color.white.opacity(0.22), Color.white.opacity(0.05)]
                                    : [Color.white.opacity(0.85), Color.white.opacity(0.30)],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                        .blendMode(.plusLighter)
                )
                // Focus accent ring (thin).
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(accent.fill(theme).opacity(inputFocused ? 0.5 : 0), lineWidth: 1)
                )
                // Tight, soft shadow — no wide grey halo.
                .shadow(color: .black.opacity(theme.isDark ? 0.24 : 0.06), radius: 6, x: 0, y: 2)
        )
        .animation(DS.Motion.fast, value: inputFocused)
        .padding(12)
        .background(composerTray)
    }

    /// Opaque strip the glass card floats on. It MUST be opaque so scrolling
    /// transcript content cannot bleed through behind the input (a translucent
    /// material here made the content look clipped/incomplete). The frosted-glass
    /// look lives on the input card itself, above this strip.
    private var composerTray: some View {
        theme.editorBackground
            .overlay(alignment: .top) {
                theme.separator.opacity(0.4).frame(height: 0.5)
            }
            .overlay(alignment: .top) {
                Color.white.opacity(theme.isDark ? 0.05 : 0.55)
                    .frame(height: 1)
                    .padding(.top, 0.5)
                    .blendMode(.plusLighter)
            }
    }

    // MARK: Logic

    private var documentName: String {
        state.selectedTab?.name ?? L("ai.currentDocument")
    }

    private var canSend: Bool {
        !convo.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !convo.isResponding
    }

    private func apply(_ suggestion: AISuggestion) {
        convo.input = L(suggestion.promptKey ?? suggestion.titleKey)
        inputFocused = true
    }

    private func newChat() {
        withAnimation(DS.Motion.fast) {
            convo.newSession()
            convo.showAllSuggestions = false
        }
        inputFocused = true
    }

    private func send() {
        let trimmed = convo.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !convo.isResponding else { return }

        withAnimation(DS.Motion.standard) {
            convo.messages.append(AIChatMessage(role: .user, text: trimmed))
            convo.input = ""
            convo.isResponding = true
        }
        convo.persist()

        // Build the request: a system message with document context + the
        // running conversation. Then stream the reply into a fresh bubble.
        let config = AIConfig.current(settings)
        var wire: [AIMessage] = [AIMessage(role: .system, content: systemContext())]
        wire += convo.messages.map {
            AIMessage(role: $0.role == .user ? .user : .assistant, content: $0.text)
        }

        let replyIndex = convo.messages.count
        convo.messages.append(AIChatMessage(role: .assistant, text: ""))

        Task {
            do {
                for try await chunk in AIClient(config: config).stream(wire) {
                    if convo.messages.indices.contains(replyIndex) {
                        convo.messages[replyIndex].text += chunk
                    }
                }
            } catch {
                let msg = (error as? AIError)?.errorDescription ?? error.localizedDescription
                if convo.messages.indices.contains(replyIndex) {
                    convo.messages[replyIndex].text = "⚠️ " + msg
                }
            }
            convo.isResponding = false
            convo.persist()
        }
    }

    /// System prompt grounding the assistant in the current document.
    private func systemContext() -> String {
        var ctx = "You are a helpful writing assistant embedded in a Markdown editor. "
            + "Answer concisely in the user's language."
        if let tab = state.selectedTab {
            let body = tab.content.count > 8000 ? String(tab.content.prefix(8000)) + "…" : tab.content
            ctx += "\n\nThe current document is \"\(tab.name)\":\n\n\(body)"
        }
        return ctx
    }

    private func sectionHeader(_ key: String) -> some View {
        Text(L(key).uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(theme.craftSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

// MARK: - Leaf components

private struct AISuggestionRow: View {
    let suggestion: AISuggestion
    let theme: PreviewTheme
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(suggestion.tint.opacity(hovered ? 0.22 : 0.14))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: suggestion.icon)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(suggestion.tint)
                    )
                Text(L(suggestion.titleKey))
                    .font(.system(size: 13))
                    .foregroundStyle(theme.craftPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.craftSecondary.opacity(hovered ? 0.9 : 0))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovered ? theme.craftHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(DS.Motion.micro, value: hovered)
    }
}

private struct AIHistoryView: View {
    @Bindable var convo: AIConversation
    let theme: PreviewTheme
    let onPick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("ai.history.title"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.craftSecondary)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 6)

            let items = convo.history.filter { !$0.messages.isEmpty }
            if items.isEmpty {
                Text(L("ai.history.empty"))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.craftSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 14)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(items) { session in
                            AIHistoryRow(
                                title: session.title.isEmpty ? L("ai.session.untitled") : session.title,
                                isActive: session.id == convo.activeID,
                                theme: theme,
                                onSelect: { convo.activate(session.id); onPick() },
                                onDelete: { convo.delete(session.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 280)
        .background(theme.editorBackground)
    }
}

private struct AIHistoryRow: View {
    let title: String
    let isActive: Bool
    let theme: PreviewTheme
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left")
                .font(.system(size: 11))
                .foregroundStyle(isActive ? Color.appAccent : theme.craftSecondary)
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.craftPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if hovered {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.craftSecondary)
                }
                .buttonStyle(.plain)
                .help(L("common.delete"))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? Color.appAccent.opacity(0.12) : (hovered ? theme.craftHover : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovered = $0 }
    }
}

private struct TypingDots: View {
    let color: Color
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                    .offset(y: animating ? -3 : 0)
                    .animation(
                        .easeInOut(duration: 0.45)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

private struct AIHeaderButton: View {
    let icon: String
    let help: String
    let theme: PreviewTheme
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.craftSecondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(hovered ? theme.craftHover : Color.clear))
                .overlay(Circle().strokeBorder(theme.separator.opacity(0.6), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
        .animation(DS.Motion.micro, value: hovered)
    }
}

private struct AICircleButton: View {
    let icon: String
    let theme: PreviewTheme
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.craftSecondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(hovered ? theme.craftHover : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(DS.Motion.micro, value: hovered)
    }
}
