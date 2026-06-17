import SwiftUI

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @Environment(AppState.self) private var state
    private let loc = LocalizationManager.shared
    @State private var selectedTab: SettingsTab = .general
    @State private var gitlabTokenInput = ""
    @State private var aiKeyInput = ""
    @State private var aiHasKey = AIKeychain.hasKey
    @State private var aiModels: [String] = []
    @State private var aiLoadingModels = false
    @State private var aiDetecting = false
    
        /// When true, the view is presented as an in-app hero overlay (not a window),
        /// so it must not mutate any NSWindow chrome.
        var embedded: Bool = false

    /// Dismiss handler for the embedded hero presentation (renders a close button).
    var onClose: (() -> Void)? = nil

    // MARK: - Brand palette (shared with the welcome hero card)
    private static let tagline      = "A minimal Markdown editor for macOS"

    enum SettingsTab: String, CaseIterable {
        case general, editor, ai, sharing

        var label: String {
            switch self {
            case .general: return L("settings.tab.general")
            case .editor:  return L("settings.tab.editor")
            case .ai:      return L("settings.tab.ai")
            case .sharing: return L("settings.tab.sharing")
            }
        }

        var icon: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .editor:  return "textformat"
            case .ai:      return "sparkles"
            case .sharing: return "wifi"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Branded hero banner ──
            hero

            // ── Sidebar + content ──
            HStack(spacing: 0) {
                // Left sidebar navigation
                VStack(spacing: DS.Space.xxs) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        SettingsNavItem(
                            icon: tab.icon,
                            label: tab.label,
                            isSelected: selectedTab == tab
                        )
                        .onTapGesture { selectedTab = tab }
                    }
                    Spacer()
                }
                .padding(.top, DS.Space.md)
                .padding(.horizontal, DS.Space.sm)
                .frame(width: 148)
                .frame(maxHeight: .infinity)
                .background(DS.Color.sidebarBg)

                Rectangle()
                    .fill(DS.Color.divider)
                    .frame(width: 1)

                // Right content
                Group {
                    switch selectedTab {
                    case .general: generalContent
                    case .editor:  editorContent
                    case .ai:      aiContent
                    case .sharing: sharingContent
                    }
                }
                .id(selectedTab)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(DS.Color.editorBg)
                .animation(DS.Motion.fast, value: selectedTab)
            }
        }
        .frame(width: 560, height: 462)
        .onAppear { if !embedded { styleSettingsWindow() } }
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack {
            // Static, expensive background (blurred aurora + dot-grid) is isolated
            // into its own rasterized view so it never re-renders on tab switches.
            SettingsHeroBackground()

            // Content
            HStack(spacing: DS.Space.md) {
                iconBadge

                VStack(alignment: .leading, spacing: 3) {
                    Text("MEditor")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(Self.tagline)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.62))
                }

                Spacer()

                HeroSectionPill(icon: selectedTab.icon, label: selectedTab.label)
            }
            .padding(.horizontal, DS.Space.xl)
            .padding(.top, 26)            // leave room for the traffic-light cluster
            .padding(.bottom, DS.Space.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 108)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.18))
                .frame(height: 1)
        }
        .overlay(alignment: .topLeading) {
            if let onClose {
                HeroTrafficLights(onClose: onClose)
                    .padding(.leading, 13)
                    .padding(.top, 13)
            }
        }
    }

    private var iconBadge: some View {
        AppIconBadge(size: 48)
    }

    // MARK: - Window styling

    private func styleSettingsWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let window = NSApp.windows.first(where: {
                $0.title.localizedCaseInsensitiveContains("setting") ||
                $0.title.localizedCaseInsensitiveContains("设置") ||
                ($0.isVisible && $0 !== NSApp.windows.first(where: { $0.title == "MEditor" }))
            }) else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
        }
    }

    // MARK: - General

    private var generalContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                settingsGroup(title: L("theme.title")) {
                    settingsRow(label: L("theme.title")) {
                        Picker("", selection: Binding(
                            get: { state.themeStore.current },
                            set: { state.themeStore.current = $0 }
                        )) {
                            ForEach(PreviewTheme.allCases, id: \.self) { t in
                                Text(t.displayName).tag(t)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                    rowDivider
                    settingsRow(label: L("ai.accentStyle")) {
                        Picker("", selection: Binding(
                            get: { AIAccentStyle.current(settings) },
                            set: { settings.aiAccentStyle = $0.rawValue }
                        )) {
                            ForEach(AIAccentStyle.allCases) { s in
                                Text(L(s.labelKey)).tag(s)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }
                }

                settingsGroup(title: L("settings.section.language")) {
                    settingsRow(label: L("settings.language")) {
                        Picker("", selection: languageBinding) {
                            Text(L("lang.system")).tag(AppLanguage.system)
                            Text("English").tag(AppLanguage.english)
                            Text("中文").tag(AppLanguage.chinese)
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                }

                settingsGroup(title: L("settings.section.preview")) {
                    settingsRow(label: L("settings.fontSize")) {
                        HStack(spacing: DS.Space.sm) {
                            Slider(value: fontSizeBinding, in: 10...28, step: 1)
                                .frame(width: 120)
                            Text("\(settings.previewFontSize) px")
                                .font(DS.Font.mono(12))
                                .foregroundStyle(.secondary)
                                .frame(width: 42, alignment: .trailing)
                        }
                    }
                }

                settingsGroup(title: L("settings.section.save")) {
                    settingsRow(label: L("settings.autoSave")) {
                        Toggle("", isOn: $settings.autoSave).labelsHidden()
                    }
                    if settings.autoSave {
                        rowDivider
                        settingsRow(label: L("settings.interval")) {
                            Picker("", selection: $settings.autoSaveInterval) {
                                Text(L("settings.secondsFormat", 10)).tag(10)
                                Text(L("settings.secondsFormat", 30)).tag(30)
                                Text(L("settings.secondsFormat", 60)).tag(60)
                                Text(L("settings.secondsFormat", 120)).tag(120)
                            }
                            .labelsHidden()
                            .frame(width: 90)
                        }
                    }
                }
            }
            .padding(DS.Space.lg)
        }
    }

    // MARK: - AI

    private var aiContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                settingsGroup(title: L("ai.section.mode")) {
                    settingsRow(label: L("ai.provider")) {
                        Picker("", selection: $settings.aiProvider) {
                            Text(L("ai.provider.disabled")).tag(AIProviderKind.disabled.rawValue)
                            Text(L("ai.mode.local")).tag(AIProviderKind.claudeCLI.rawValue)
                            Text(L("ai.mode.remote")).tag(AIProviderKind.openai.rawValue)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 270)
                    }
                }

                if settings.aiProvider == AIProviderKind.claudeCLI.rawValue {
                    settingsGroup(title: L("ai.section.local")) {
                        settingsRow(label: L("ai.cliPath")) {
                            HStack(spacing: 8) {
                                TextField("/usr/local/bin/claude", text: $settings.aiCLIPath)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 190)
                                Button(action: detectCLI) {
                                    if aiDetecting {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Text(L("ai.detect"))
                                    }
                                }
                                .disabled(aiDetecting)
                            }
                        }
                        rowDivider
                        aiHintRow(L("ai.cliHint"))
                    }
                } else if settings.aiProvider == AIProviderKind.openai.rawValue {
                    settingsGroup(title: L("ai.section.remote")) {
                        settingsRow(label: L("ai.preset")) {
                            Picker("", selection: Binding<String>(
                                get: { AIPresets.match(settings.aiBaseURL)?.id ?? "custom" },
                                set: { id in
                                    guard let p = AIPresets.all.first(where: { $0.id == id }) else { return }
                                    settings.aiBaseURL = p.baseURL
                                    aiModels = p.models
                                    if !p.models.contains(settings.aiModel) {
                                        settings.aiModel = p.models.first ?? settings.aiModel
                                    }
                                }
                            )) {
                                ForEach(AIPresets.all) { Text($0.name).tag($0.id) }
                                Text(L("ai.preset.custom")).tag("custom")
                            }
                            .labelsHidden()
                            .frame(width: 230)
                        }
                        rowDivider
                        settingsRow(label: L("ai.baseURL")) {
                            TextField("https://api.openai.com/v1", text: $settings.aiBaseURL)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 230)
                        }
                        rowDivider
                        settingsRow(label: L("ai.apiKey")) { aiKeyField }
                        rowDivider
                        settingsRow(label: L("ai.model")) { aiModelField }
                    }
                }
            }
            .padding(DS.Space.lg)
        }
    }

    /// Built-in preset models for the current base URL, merged with any fetched
    /// models and the currently-selected one.
    private var candidateModels: [String] {
        var list = aiModels
        if list.isEmpty, let preset = AIPresets.match(settings.aiBaseURL) {
            list = preset.models
        }
        if !settings.aiModel.isEmpty && !list.contains(settings.aiModel) {
            list.insert(settings.aiModel, at: 0)
        }
        return list
    }

    @ViewBuilder
    private var aiKeyField: some View {
        if aiHasKey {
            HStack(spacing: 8) {
                Text("•••••••• " + L("gitlab.tokenConfigured"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button(L("gitlab.clearToken")) {
                    AIKeychain.clear(); aiKeyInput = ""; aiHasKey = false
                }
            }
        } else {
            HStack(spacing: 8) {
                SecureField("sk-…", text: $aiKeyInput)
                    .frame(width: 160)
                Button(L("gitlab.saveConfig")) {
                    AIKeychain.save(aiKeyInput); aiKeyInput = ""; aiHasKey = AIKeychain.hasKey
                }
                .disabled(aiKeyInput.isEmpty)
            }
        }
    }

    @ViewBuilder
    private var aiModelField: some View {
        HStack(spacing: 8) {
            let models = candidateModels
            if models.isEmpty {
                TextField("gpt-4o-mini", text: $settings.aiModel)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 160)
            } else {
                Picker("", selection: $settings.aiModel) {
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 175)
            }
            Button(action: refreshModels) {
                if aiLoadingModels {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(aiLoadingModels)
            .help(L("ai.refreshModels"))
        }
    }

    private func aiHintRow(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.sm)
    }

    private func detectCLI() {
        aiDetecting = true
        Task {
            let path = await AIClient.detectClaudeCLI()
            await MainActor.run {
                if let path { settings.aiCLIPath = path }
                aiDetecting = false
            }
        }
    }

    private func refreshModels() {
        aiLoadingModels = true
        let base = settings.aiBaseURL
        let key = AIKeychain.load() ?? ""
        Task {
            let models = await AIClient.fetchModels(baseURL: base, apiKey: key)
            await MainActor.run {
                aiModels = models
                aiLoadingModels = false
            }
        }
    }

    // MARK: - Editor

    private var editorContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                settingsGroup(title: L("settings.section.launchLayout")) {
                    settingsRow(label: L("settings.showSidebar")) {
                        Toggle("", isOn: $settings.showSidebarOnLaunch).labelsHidden()
                    }
                    rowDivider
                    settingsRow(label: L("settings.showEditor")) {
                        Toggle("", isOn: $settings.showEditorOnLaunch).labelsHidden()
                    }
                    rowDivider
                    settingsRow(label: L("settings.showPreview")) {
                        Toggle("", isOn: $settings.showPreviewOnLaunch).labelsHidden()
                    }
                }
            }
            .padding(DS.Space.lg)
        }
    }

    // MARK: - Sharing

    private var sharingContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                settingsGroup(title: L("settings.section.lanShare")) {
                    settingsRow(label: L("settings.port")) {
                        TextField("", value: $settings.sharePort, format: .number)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 72)
                    }
                    rowDivider
                    HStack {
                        Text(L("settings.portHint"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, DS.Space.lg)
                    .padding(.vertical, DS.Space.sm)
                }

                gitlabSettingsGroup
            }
            .padding(DS.Space.lg)
        }
    }

    @ViewBuilder
    private var gitlabSettingsGroup: some View {
        let mgr = state.gitlabShareManager
        settingsGroup(title: L("gitlab.title")) {
            settingsRow(label: L("gitlab.host")) {
                TextField("gitlab.example.com", text: Binding(
                    get: { mgr.host }, set: { mgr.host = $0 }))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 200)
            }
            rowDivider
            settingsRow(label: L("gitlab.token")) {
                if mgr.hasToken {
                    HStack(spacing: 8) {
                        Text("•••••••• " + L("gitlab.tokenConfigured"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Button(L("gitlab.clearToken")) { mgr.clearToken() }
                    }
                } else {
                    HStack(spacing: 8) {
                        SecureField("glpat-…", text: $gitlabTokenInput)
                            .frame(width: 150)
                        Button(L("gitlab.saveConfig")) {
                            mgr.saveToken(gitlabTokenInput)
                            gitlabTokenInput = ""
                        }
                        .disabled(mgr.host.isEmpty || gitlabTokenInput.isEmpty)
                    }
                }
            }
            rowDivider
            settingsRow(label: L("gitlab.visibility.internal") + " / " + L("gitlab.visibility.private")) {
                Picker("", selection: Binding(
                    get: { mgr.visibility }, set: { mgr.visibility = $0 })) {
                    Text(L("gitlab.visibility.internal")).tag("internal")
                    Text(L("gitlab.visibility.private")).tag("private")
                }
                .labelsHidden()
                .frame(width: 150)
            }
        }
    }

    // MARK: - Reusable layout helpers

    private var rowDivider: some View {
        Rectangle()
            .fill(DS.Color.divider)
            .frame(height: 1)
            .padding(.leading, DS.Space.lg)
    }

    private func settingsGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .kerning(0.4)
                .padding(.horizontal, DS.Space.lg)
                .padding(.bottom, DS.Space.xs + 2)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(DS.Color.sidebarBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.divider, lineWidth: 1)
            )
        }
        .padding(.bottom, DS.Space.xl - 4)
    }

    private func settingsRow<Content: View>(
        label: String,
        @ViewBuilder control: () -> Content
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            control()
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, 9)
    }

    // MARK: - Bindings

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(settings.previewFontSize) },
            set: { settings.previewFontSize = Int($0) }
        )
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { loc.language },
            set: { loc.language = $0 }
        )
    }
}

// MARK: - Settings Nav Item

private struct SettingsNavItem: View {
    let icon: String
    let label: String
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isSelected ? Color.appAccent : Color.secondary)
                .frame(width: 20, alignment: .center)

            Text(label)
                .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)

            Spacer()
        }
        .padding(.horizontal, DS.Space.sm + 2)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm + 1, style: .continuous)
                .fill(
                    isSelected
                        ? Color.appAccent.opacity(0.12)
                        : isHovered ? DS.Color.rowHover : Color.clear
                )
                .animation(.easeOut(duration: 0.1), value: isSelected)
                .animation(.easeOut(duration: 0.07), value: isHovered)
        )
        .overlay(alignment: .leading) {
            if isSelected {
                SelectionAccentLine(verticalPad: 5)
                    .padding(.leading, -2)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}


// MARK: - Hero Traffic Lights

/// Faux macOS window controls for the embedded hero panel. The red light
/// dismisses the panel; amber/green are decorative. Hovering the cluster
/// reveals the glyphs, mirroring native traffic-light behaviour.
private struct HeroTrafficLights: View {
    let onClose: () -> Void
    @State private var hovering = false

    private static let red    = Color(red: 1.00, green: 0.37, blue: 0.34)
    private static let amber  = Color(red: 1.00, green: 0.74, blue: 0.18)
    private static let green  = Color(red: 0.16, green: 0.79, blue: 0.25)

    var body: some View {
        HStack(spacing: 8) {
            light(color: Self.red,   glyph: "xmark",  action: onClose)
            light(color: Self.amber, glyph: "minus",  action: nil)
            light(color: Self.green, glyph: "arrow.up.left.and.arrow.down.right.circle", action: nil)
        }
        .onHover { hovering = $0 }
        .animation(DS.Motion.micro, value: hovering)
    }

    @ViewBuilder
    private func light(color: Color, glyph: String, action: (() -> Void)?) -> some View {
        let dot = Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(Color.black.opacity(0.12), lineWidth: 0.5))
            .overlay(
                Image(systemName: glyph)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.55))
                    .opacity(hovering ? 1 : 0)
            )

        if let action {
            Button(action: action) { dot }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
        } else {
            dot
        }
    }
}


// MARK: - Hero Background (static, rasterized once)

/// Premium hero background: a deep matte base with a single soft brand-blue
/// glow anchored top-left and a fine film grain. Restraint over flashy
/// gradients. No inputs + `.drawingGroup()` keep it cached and cheap.
private struct SettingsHeroBackground: View {
    private static let base = Color(red: 0.075, green: 0.085, blue: 0.125)
    private static let glow = Color(red: 0.42,  green: 0.55,  blue: 1.00)   // icon accent

    var body: some View {
        ZStack {
            Self.base

            // Single soft corner glow (top-left), restrained.
            GeometryReader { geo in
                RadialGradient(
                    gradient: Gradient(colors: [Self.glow.opacity(0.30), Self.glow.opacity(0)]),
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: max(geo.size.width * 0.46, geo.size.height * 1.9)
                )
            }

            // Fine film grain for matte texture.
            Canvas { ctx, size in
                var rng = SystemRandomNumberGenerator()
                let n = Int(size.width * size.height / 90)
                for _ in 0..<max(0, n) {
                    let x = Double.random(in: 0..<max(size.width, 1), using: &rng)
                    let y = Double.random(in: 0..<max(size.height, 1), using: &rng)
                    let a = Double.random(in: 0...0.05, using: &rng)
                    let c: Color = Bool.random(using: &rng) ? .white : .black
                    ctx.fill(Path(CGRect(x: x, y: y, width: 1.2, height: 1.2)),
                             with: .color(c.opacity(a)))
                }
            }
            .allowsHitTesting(false)

            // Whisper-thin top highlight for crispness.
            LinearGradient(
                colors: [Color.white.opacity(0.05), Color.clear],
                startPoint: .top, endPoint: .center
            )
        }
        .drawingGroup()   // flatten to one cached layer
    }
}

// MARK: - Hero Section Pill


private struct HeroSectionPill: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }
}


// MARK: - App Icon Badge

/// In-app rendition of the MEditor app icon (blockquote mark on ink).
/// Drawn with the same geometry as `Resources/AppIcon.icns` for consistency.
struct AppIconBadge: View {
    var size: CGFloat = 48

    private static let ink    = Color(red: 0.09, green: 0.09, blue: 0.11)
    private static let accent = Color(red: 0.42, green: 0.55, blue: 1.00)
    private static let line   = Color(white: 0.97)

    var body: some View {
        let radius = size * 0.2237
        Canvas { ctx, sz in
            let rect = CGRect(origin: .zero, size: sz)
            ctx.fill(
                Path(roundedRect: rect, cornerRadius: radius, style: .continuous),
                with: .color(Self.ink)
            )

            let w   = sz.width * 0.50
            let bw  = sz.width * 0.075
            let gap = sz.width * 0.07
            let bh  = sz.width * 0.36
            let t   = sz.width * 0.072
            let x0  = rect.midX - w / 2
            let midY = rect.midY

            // Blockquote bar (accent)
            ctx.fill(
                Path(roundedRect: CGRect(x: x0, y: midY - bh/2, width: bw, height: bh), cornerRadius: bw/2),
                with: .color(Self.accent)
            )
            // Two quoted lines (white): top full-width, bottom shorter
            let lx = x0 + bw + gap
            let lw = w - bw - gap
            ctx.fill(
                Path(roundedRect: CGRect(x: lx, y: midY - bh/2, width: lw, height: t), cornerRadius: t/2),
                with: .color(Self.line)
            )
            ctx.fill(
                Path(roundedRect: CGRect(x: lx, y: midY + bh/2 - t, width: lw * 0.66, height: t), cornerRadius: t/2),
                with: .color(Self.line)
            )
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: max(1, size / 48))
        )
        .shadow(color: Color.black.opacity(0.35), radius: size * 0.18, y: size * 0.08)
    }
}
