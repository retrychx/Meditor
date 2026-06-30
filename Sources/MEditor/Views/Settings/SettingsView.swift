import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    private var bindableSettings: Bindable<AppSettings> { Bindable(settings) }
    @Environment(AppState.self) private var state
    private let loc = LocalizationManager.shared
    @State private var selectedTab: SettingsTab = .general
    @State private var githubTokenInput = ""
    @State private var aiKeyInput = ""
    @State private var aiHasKey = AIKeychain.hasKey
    @State private var aiModels: [String] = []
    @State private var aiLoadingModels = false
    @State private var aiDetecting = false
    @State private var skillAddMessage: String? = nil
    
        /// When true, the view is presented as an in-app hero overlay (not a window),
        /// so it must not mutate any NSWindow chrome.
        var embedded: Bool = false

    /// Dismiss handler for the embedded hero presentation (renders a close button).
    var onClose: (() -> Void)? = nil

    // MARK: - Brand palette (shared with the welcome hero card)
    private static let tagline      = "A minimal Markdown editor for macOS"

    enum SettingsTab: String, CaseIterable {
        case general, ai, sharing, plugins, paths

        var label: String {
            switch self {
            case .general: return L("settings.tab.general")
            case .ai:      return L("settings.tab.ai")
            case .sharing: return L("settings.tab.sharing")
            case .plugins: return "插件"
            case .paths:   return "路径"
            }
        }

        var icon: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .ai:      return "sparkles"
            case .sharing: return "wifi"
            case .plugins: return "puzzlepiece.extension"
            case .paths:   return "folder"
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
                    case .ai:      aiContent
                    case .sharing: sharingContent
                    case .plugins: pluginsContent
                    case .paths:   pathsContent
                    }
                }
                .id(selectedTab)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(DS.Color.sidebarBg)
                .animation(DS.Motion.fast, value: selectedTab)
            }
        }
        .frame(width: 680, height: 560)
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
                    settingsRow(label: L("theme.title"), subtitle: L("settings.desc.theme")) {
                        SettingsMenu(
                            selection: Binding(
                                get: { state.themeStore.current },
                                set: { state.themeStore.current = $0 }
                            ),
                            options: PreviewTheme.allCases.map { ($0, $0.displayName) }
                        )
                        .frame(width: 170)
                    }
                    rowDivider
                    settingsRow(label: L("ai.accentStyle"), subtitle: L("settings.desc.accent")) {
                        SettingsMenu(
                            selection: Binding(
                                get: { AIAccentStyle.current(settings) },
                                set: { settings.aiAccentStyle = $0.rawValue }
                            ),
                            options: AIAccentStyle.allCases.map { ($0, L($0.labelKey)) }
                        )
                        .frame(width: 170)
                    }
                }

                settingsGroup(title: L("settings.section.language")) {
                    settingsRow(label: L("settings.language"), subtitle: L("settings.desc.language")) {
                        SettingsMenu(
                            selection: languageBinding,
                            options: [
                                (.system, L("lang.system")),
                                (.english, "English"),
                                (.chinese, "中文")
                            ]
                        )
                        .frame(width: 170)
                    }
                }

                settingsGroup(title: L("settings.section.preview")) {
                    settingsStackedRow(label: L("settings.fontSize"), subtitle: L("settings.desc.fontSize")) {
                        HStack(spacing: DS.Space.md) {
                            Slider(value: fontSizeBinding, in: 10...28, step: 1)
                                .frame(maxWidth: .infinity)
                            Text("\(settings.previewFontSize) px")
                                .font(DS.Font.mono(12))
                                .foregroundStyle(.secondary)
                                .frame(width: 42, alignment: .trailing)
                        }
                    }
                }

                settingsGroup(title: L("settings.section.save")) {
                    settingsRow(label: L("settings.autoSave"), subtitle: L("settings.desc.autoSave")) {
                        Toggle("", isOn: bindableSettings.autoSave).labelsHidden()
                    }
                    if settings.autoSave {
                        rowDivider
                        settingsRow(label: L("settings.interval")) {
                            SettingsMenu(
                                selection: bindableSettings.autoSaveInterval,
                                options: [
                                    (10, L("settings.secondsFormat", 10)),
                                    (30, L("settings.secondsFormat", 30)),
                                    (60, L("settings.secondsFormat", 60)),
                                    (120, L("settings.secondsFormat", 120))
                                ]
                            )
                            .frame(width: 130)
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
                    settingsStackedRow(label: L("ai.provider"), subtitle: L("settings.desc.provider")) {
                        SettingsMenu(
                            selection: bindableSettings.aiProvider,
                            options: [
                                (AIProviderKind.disabled.rawValue, L("ai.provider.disabled")),
                                (AIProviderKind.claudeCLI.rawValue, L("ai.mode.local")),
                                (AIProviderKind.openai.rawValue, L("ai.mode.remote"))
                            ]
                        )
                    }
                }

                if settings.aiProvider == AIProviderKind.claudeCLI.rawValue {
                    settingsGroup(title: L("ai.section.local")) {
                        settingsStackedRow(label: L("ai.cliPath"), subtitle: L("ai.cliHint")) {
                            HStack(spacing: 8) {
                                TextField("/usr/local/bin/claude", text: bindableSettings.aiCLIPath)
                                    .textFieldStyle(.plain)
                                    .settingsField()
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
                        settingsStackedRow(label: "模型", subtitle: "留空则使用 CLI 默认模型") {
                            SettingsMenu(
                                selection: bindableSettings.aiCLIModel,
                                options: [
                                    ("",                  "CLI 默认"),
                                    ("claude-opus-4-5",   "Claude Opus 4.5（最强）"),
                                    ("claude-sonnet-4-5", "Claude Sonnet 4.5（均衡）"),
                                    ("claude-haiku-4-5",  "Claude Haiku 4.5（最快）"),
                                ]
                            )
                        }
                    }
                } else if settings.aiProvider == AIProviderKind.openai.rawValue {
                    settingsGroup(title: L("ai.section.remote")) {
                        settingsStackedRow(label: L("ai.preset")) {
                            SettingsMenu(
                                selection: Binding<String>(
                                    get: { AIPresets.match(settings.aiBaseURL)?.id ?? "custom" },
                                    set: { id in
                                        guard let p = AIPresets.all.first(where: { $0.id == id }) else { return }
                                        settings.aiBaseURL = p.baseURL
                                        aiModels = p.models
                                        if !p.models.contains(settings.aiModel) {
                                            settings.aiModel = p.models.first ?? settings.aiModel
                                        }
                                    }
                                ),
                                options: AIPresets.all.map { ($0.id, $0.name) } + [("custom", L("ai.preset.custom"))]
                            )
                        }
                        rowDivider
                        settingsStackedRow(label: L("ai.baseURL")) {
                            TextField("https://api.openai.com/v1", text: bindableSettings.aiBaseURL)
                                .textFieldStyle(.plain)
                                .settingsField()
                        }
                        rowDivider
                        settingsStackedRow(label: L("ai.apiKey")) { aiKeyField }
                        rowDivider
                        settingsStackedRow(label: L("ai.model")) { aiModelField }
                        rowDivider
                        settingsStackedRow(label: "Agent 模型", subtitle: "工具调用专用，留空则使用上方模型") {
                            TextField("留空则回退到上方模型", text: bindableSettings.aiAgentModel)
                                .textFieldStyle(.plain)
                                .settingsField()
                        }
                        rowDivider
                        settingsStackedRow(label: "Agent 最大步数", subtitle: "每次对话最多工具调用轮次（5~100，默认 30）") {
                            TextField("30", value: bindableSettings.aiAgentMaxSteps, format: .number)
                                .textFieldStyle(.plain)
                                .settingsField()
                                .frame(width: 60)
                        }
                        rowDivider
                        settingsStackedRow(label: "内联编辑模型", subtitle: "改写/扩写/精简/翻译，留空则使用上方模型") {
                            TextField("留空则回退到上方模型", text: bindableSettings.aiInlineModel)
                                .textFieldStyle(.plain)
                                .settingsField()
                        }
                    }
                }

                // MARK: InternalCalendar 集成
                internal_calendarSection

                // MARK: Claude Code 集成
                claudeMonitorSection
            }
            .padding(DS.Space.lg)
        }
    }

    // MARK: - InternalCalendar 集成

    private var internal_calendarSection: some View {
        settingsGroup(title: "InternalCalendar 日程集成") {
            settingsRow(label: "启用 InternalCalendar 日程", subtitle: "在日历视图中合并显示 InternalCalendar 日程") {
                Toggle("", isOn: bindableSettings.internal_calendarEnabled)
                    .labelsHidden()
            }
            if settings.internal_calendarEnabled {
                settingsRow(label: "本地代理地址", subtitle: "InternalCalendar MCP proxy 地址") {
                    TextField("本地代理地址", text: bindableSettings.internal_calendarProxyURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                        .font(.system(size: 12, design: .monospaced))
                }
                settingsRow(label: "查询日程路径", subtitle: "mcp-proxy-path header 值") {
                    TextField("查询接口路径", text: bindableSettings.internal_calendarCalendarPath)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                        .font(.system(size: 12, design: .monospaced))
                }
                settingsRow(label: "创建日程路径", subtitle: "mcp-proxy-path header 值") {
                    TextField("创建接口路径", text: bindableSettings.internal_calendarCreatePath)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                        .font(.system(size: 12, design: .monospaced))
                }
            }
        }
    }

    // MARK: - Claude Code 监听

    private var claudeMonitorSection: some View {
        settingsGroup(title: "Claude Code 集成") {
            settingsRow(label: "监听会话文件", subtitle: "Claude Code 生成文件时自动提示开启") {
                Toggle("", isOn: bindableSettings.claudeMonitorEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            if settings.claudeMonitorEnabled {
                rowDivider

                settingsStackedRow(
                    label: "监听目录",
                    subtitle: "空则使用默认的 ~/.claude/projects/"
                ) {
                    HStack(spacing: 8) {
                        TextField("~/.claude/projects/", text: bindableSettings.claudeMonitorCustomPath)
                            .textFieldStyle(.plain)
                            .settingsField()
                        Button("选择…") { selectClaudeMonitorDir() }
                    }
                }

                rowDivider

                settingsStackedRow(
                    label: "文件类型",
                    subtitle: "逗号分隔，如 md,txt"
                ) {
                    TextField("md,txt", text: bindableSettings.claudeMonitorFileExts)
                        .textFieldStyle(.plain)
                        .settingsField()
                }

                rowDivider

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("监听目录：\"\(settings.claudeMonitorDirectory.path)\"")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
    }

    private func selectClaudeMonitorDir() {
        Task {
            if let url = await state.filePickerService.pickFolder(message: "选择 Claude Code 输出文件目录") {
                settings.claudeMonitorCustomPath = url.path
            }
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
                    .settingsField()
                Button(L("gitlab.clearToken")) {
                    AIKeychain.clear(); aiKeyInput = ""; aiHasKey = false
                }
            }
        } else {
            HStack(spacing: 8) {
                SecureField("sk-…", text: $aiKeyInput)
                    .textFieldStyle(.plain)
                    .settingsField()
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
                TextField("gpt-4o-mini", text: bindableSettings.aiModel)
                    .textFieldStyle(.plain)
                    .settingsField()
            } else {
                SettingsMenu(
                    selection: bindableSettings.aiModel,
                    options: models.map { ($0, $0) }
                )
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

    // MARK: - Plugins

    private var pluginsContent: some View {
        let plugins  = state.pluginManager
        let builtins = plugins.skills.filter { $0.source == .builtin }
        let manuals  = plugins.skills.filter { $0.source == .manual }

        return ScrollView {
            VStack(spacing: 0) {
                // ── 内置技能 ──
                settingsGroup(title: "内置技能 (\(builtins.filter(\.isEnabled).count)/\(builtins.count) 已启用)") {
                    ForEach(builtins) { skill in
                        builtinSkillRow(skill)
                        if skill.id != builtins.last?.id { rowDivider }
                    }
                }

                // ── 我的技能 ──
                settingsGroup(title: "我的技能 (\(manuals.filter(\.isEnabled).count) 个已启用)") {
                    if manuals.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "puzzlepiece.extension")
                                .font(.system(size: 24, weight: .light))
                                .foregroundStyle(.tertiary)
                            Text("还没有自定义技能")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                            Text("点击下方按钮添加 SKILL.md 文件")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(manuals) { skill in
                            skillRow(skill)
                            if skill.id != manuals.last?.id { rowDivider }
                        }
                    }
                }

                HStack {
                    Button {
                        openSkillFilePicker()
                    } label: {
                        Label("添加技能", systemImage: "plus")
                            .font(.system(size: 13))
                    }
                    Spacer()
                }
                .padding(.top, 4)

                if let msg = skillAddMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(msg)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.top, 6)
                }
            }
            .padding(DS.Space.lg)
        }
    }

    /// Row for a built-in skill: toggle + name/desc + "内置" badge (no delete, no path).
    private func builtinSkillRow(_ skill: PluginSkill) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { skill.isEnabled },
                set: { state.pluginManager.setEnabled(skill.id, enabled: $0) }
            ))
            .labelsHidden()
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                if !skill.description.isEmpty {
                    Text(skill.description)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text("内置")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.07)))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// Row for a manual (user-added) skill: toggle + name/desc/path + delete button.
    private func skillRow(_ skill: PluginSkill) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { skill.isEnabled },
                set: { state.pluginManager.setEnabled(skill.id, enabled: $0) }
            ))
            .labelsHidden()
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                if !skill.description.isEmpty {
                    Text(skill.description)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(skill.skillPath.deletingLastPathComponent().path
                        .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                state.pluginManager.remove(id: skill.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("移除此 Skill")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func openSkillFilePicker() {
        Task {
            if let url = await state.filePickerService.pickFileOrFolder(title: "选择 SKILL.md / 技能目录 / 插件目录", allowedExtensions: ["md", "txt"]) {
                let count = state.pluginManager.addSkills(from: url)
                if count > 0 {
                    await state.pluginManager.reloadAll()
                    skillAddMessage = count > 1 ? "已添加 \(count) 个技能" : nil
                } else {
                    skillAddMessage = "未找到 SKILL.md：可选 SKILL.md 文件、含 SKILL.md 的技能目录，或包含 skills/*/SKILL.md 的插件目录"
                }
            }
        }
    }

    // MARK: - Paths

    private var pathsContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                settingsGroup(title: "文档路径") {
                    PathRow(
                        icon: "folder.fill",
                        title: "用户文档",
                        subtitle: "侧边栏显示此目录下的文件",
                        iconColor: .blue,
                        currentPath: AppSettings.shared.userDocPath,
                        onChoose: { chooseUserDocPath() },
                        onClear:  { try? AppSettings.shared.setUserDocPath(nil) }
                    )

                    rowDivider

                    PathRow(
                        icon: "shippingbox.fill",
                        title: "App 文档（输出目录）",
                        subtitle: "HTML 美化等功能的默认保存位置",
                        iconColor: .orange,
                        currentPath: AppSettings.shared.appDocPath,
                        onChoose: { chooseAppDocPath() },
                        onClear:  { try? AppSettings.shared.setAppDocPath(nil) }
                    )
                }
            }
            .padding(DS.Space.lg)
        }
    }

    private func chooseUserDocPath() {
        Task {
            if let url = await state.filePickerService.pickFolder(message: nil) {
                try? AppSettings.shared.setUserDocPath(url)
            }
        }
    }

    private func chooseAppDocPath() {
        Task {
            if let url = await state.filePickerService.pickFolder(message: nil) {
                try? AppSettings.shared.setAppDocPath(url)
            }
        }
    }

    // MARK: - Sharing

    private var sharingContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                settingsGroup(title: L("settings.section.lanShare")) {
                    settingsStackedRow(label: L("settings.port"), subtitle: L("settings.portHint")) {
                        TextField("", value: bindableSettings.sharePort, format: .number)
                            .textFieldStyle(.plain)
                            .settingsField()
                            .frame(width: 120)
                    }
                }

                githubGistSettingsGroup
            }
            .padding(DS.Space.lg)
        }
        .onAppear { state.githubGistManager.refreshTokenStatus() }
    }

    @ViewBuilder
    private var githubGistSettingsGroup: some View {
        let mgr = state.githubGistManager
        settingsGroup(title: L("github.gist.title")) {
            settingsStackedRow(label: L("github.gist.token")) {
                if mgr.hasToken {
                    HStack(spacing: 8) {
                        Text("•••••••• " + L("github.gist.tokenConfigured"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .settingsField()
                        Button(L("github.gist.clearToken")) { mgr.clearToken() }
                    }
                } else {
                    HStack(spacing: 8) {
                        SecureField("ghp_…", text: $githubTokenInput)
                            .textFieldStyle(.plain)
                            .settingsField()
                        Button(L("github.gist.saveToken")) {
                            mgr.saveToken(githubTokenInput)
                            githubTokenInput = ""
                        }
                        .disabled(githubTokenInput.isEmpty)
                    }
                }
            }
            rowDivider
            settingsStackedRow(label: L("github.gist.visibility")) {
                SettingsMenu(
                    selection: Binding(
                        get: { mgr.isPublic ? "public" : "secret" },
                        set: { mgr.isPublic = ($0 == "public") }
                    ),
                    options: [
                        ("secret", L("github.gist.secret")),
                        ("public", L("github.gist.public"))
                    ]
                )
            }
        }
    }

    // MARK: - Reusable layout helpers (Craft-style grouped cards)

    /// Card background — white in light mode, gently elevated in dark mode.
    private var cardFill: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0.16, alpha: 1)
                : NSColor.white
        })
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 1)
            .padding(.leading, 16)
    }

    private func settingsGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.leading, 3)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 1)
        }
        .padding(.bottom, 22)
    }

    private func settingsRow<Content: View>(
        label: String,
        subtitle: String? = nil,
        @ViewBuilder control: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    /// Craft-style stacked row: title + subtitle on top, control filling the
    /// width below. Used for wide/compound controls (segmented pickers, text
    /// fields, control+button combos) so they align cleanly.
    private func settingsStackedRow<Content: View>(
        label: String,
        subtitle: String? = nil,
        @ViewBuilder control: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            control()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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

// MARK: - Unified settings controls

/// One visual language for every value control (text fields + dropdowns):
/// a rounded, hairline-bordered, fixed-height field.
private struct SettingsFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
    }
}

private extension View {
    func settingsField() -> some View { modifier(SettingsFieldStyle()) }
}

/// Dropdown styled identically to the text fields (replaces native popup pickers
/// so the whole settings form reads as one consistent control set).
private struct SettingsMenu<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]

    private var currentLabel: String {
        options.first { $0.value == selection }?.label ?? ""
    }

    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { i in
                let opt = options[i]
                Button { selection = opt.value } label: {
                    if opt.value == selection {
                        Label(opt.label, systemImage: "checkmark")
                    } else {
                        Text(opt.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(currentLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .settingsField()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
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

// MARK: - Path Row

private struct PathRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let iconColor: Color
    let currentPath: URL?
    let onChoose: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(iconColor)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                if let url = currentPath {
                    Text(url.path.replacingOccurrences(of:
                        FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button("选择文件夹", action: onChoose)
                    .controlSize(.small)
                if currentPath != nil {
                    Button(currentPath == nil ? "" : "清除", action: onClear)
                        .controlSize(.small)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
