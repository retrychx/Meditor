import SwiftUI

// MARK: - AI tab

extension SettingsView {
    var aiContent: some View {
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
                        rowDivider
                        settingsStackedRow(label: "连接测试", subtitle: "真实发送一条消息，验证 CLI 与登录态可用") {
                            HStack(spacing: 10) {
                                Button {
                                    Task { await runCLITest() }
                                } label: {
                                    if connectionTesting {
                                        HStack(spacing: 6) {
                                            ProgressView().controlSize(.small)
                                            Text("测试中…")
                                        }
                                    } else {
                                        Text("测试连接")
                                    }
                                }
                                .disabled(connectionTesting || settings.aiCLIPath.isEmpty)
                                if let result = connectionTestResult {
                                    Text(result)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(connectionTestOK ? Color.green : Color.red)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
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
                        settingsStackedRow(label: L("ai.apiKey"), subtitle: L("ai.apiKey.localOnly")) { aiKeyField }
                        rowDivider
                        settingsStackedRow(label: "连接测试") {
                            HStack(spacing: 10) {
                                Button {
                                    Task { await runConnectionTest() }
                                } label: {
                                    if connectionTesting {
                                        HStack(spacing: 6) {
                                            ProgressView().controlSize(.small)
                                            Text("测试中…")
                                        }
                                    } else {
                                        Text("测试连接")
                                    }
                                }
                                .disabled(connectionTesting)
                                if let result = connectionTestResult {
                                    Text(result)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(connectionTestOK ? Color.green : Color.red)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                        rowDivider
                        settingsStackedRow(label: L("ai.model")) { aiModelField }
                        rowDivider
                        settingsStackedRow(label: "Agent 模型", subtitle: "工具调用专用，留空则使用上方模型") {
                            modelPickerField(binding: bindableSettings.aiAgentModel, placeholder: "留空则回退到上方模型")
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
                            modelPickerField(binding: bindableSettings.aiInlineModel, placeholder: "留空则回退到上方模型")
                        }
                    }
                }

                // MARK: 个性化（对所有 provider 生效）
                settingsGroup(title: "个性化") {
                    settingsRow(
                        label: L("ai.autoAttach.toggle"),
                        subtitle: L("ai.autoAttach.toggleHint")
                    ) {
                        Toggle("", isOn: bindableSettings.aiAutoAttachContext)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }

                    rowDivider

                    settingsStackedRow(
                        label: "自定义系统提示词",
                        subtitle: "追加到每次对话的系统提示词末尾。例如：「回答一律用中文，风格简洁直接」"
                    ) {
                        TextEditor(text: bindableSettings.aiCustomSystemPrompt)
                            .font(.system(size: 12))
                            .frame(minHeight: 64, maxHeight: 96)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }

                // MARK: Claude Code 集成
                claudeMonitorSection
            }
            .padding(DS.Space.lg)
        }
    }

    // MARK: - Claude Code 监听

    var claudeMonitorSection: some View {
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

    func selectClaudeMonitorDir() {
        Task {
            if let url = await state.filePickerService.pickFolder(message: "选择 Claude Code 输出文件目录") {
                settings.claudeMonitorCustomPath = url.path
            }
        }
    }

    /// Built-in preset models for the current base URL, merged with any fetched
    /// models and the currently-selected one.
    var candidateModels: [String] {
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
    var aiKeyField: some View {
        if aiHasKey {
            HStack(spacing: 8) {
                Text("•••••••• " + L("gitlab.tokenConfigured"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .settingsField()
                Button(L("gitlab.clearToken")) {
                    AIAPIKeyStore.clear(); aiKeyInput = ""; aiHasKey = false
                }
            }
        } else {
            HStack(spacing: 8) {
                SecureField("sk-…", text: $aiKeyInput)
                    .textFieldStyle(.plain)
                    .settingsField()
                Button(L("gitlab.saveConfig")) {
                    AIAPIKeyStore.save(aiKeyInput); aiKeyInput = ""; aiHasKey = AIAPIKeyStore.hasKey
                }
                .disabled(aiKeyInput.isEmpty)
            }
        }
    }

    @ViewBuilder
    var aiModelField: some View {
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

    func aiHintRow(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.sm)
    }

    func detectCLI() {
        aiDetecting = true
        Task {
            let path = await AIClient.detectClaudeCLI()
            await MainActor.run {
                if let path { settings.aiCLIPath = path }
                aiDetecting = false
            }
        }
    }

    // MARK: - Preset model picker for agent/inline fields

    /// Returns preset model list based on current provider/baseURL.
    var presetModelsForCurrentProvider: [String] {
        // If a known preset matches, use its models
        if let preset = AIPresets.match(settings.aiBaseURL) {
            return preset.models
        }
        // Fall back by base URL heuristics
        let base = settings.aiBaseURL.lowercased()
        if base.contains("anthropic") {
            return ["claude-opus-4-5", "claude-sonnet-4-5", "claude-haiku-3-5"]
        } else if base.contains("openai") {
            return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "o3", "o4-mini"]
        } else if base.contains("localhost:11434") || base.contains("ollama") {
            return ["llama3.2", "qwen2.5", "deepseek-r1"]
        }
        // Generic fallback
        return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "o3", "o4-mini",
                "claude-opus-4-5", "claude-sonnet-4-5", "claude-haiku-3-5",
                "llama3.2", "qwen2.5", "deepseek-r1"]
    }

    @ViewBuilder
    func modelPickerField(binding: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: binding)
                .textFieldStyle(.plain)
                .settingsField()
            Menu {
                Button("（清空/自定义）") { binding.wrappedValue = "" }
                Divider()
                ForEach(presetModelsForCurrentProvider, id: \.self) { model in
                    Button(model) { binding.wrappedValue = model }
                }
            } label: {
                Image(systemName: "chevron.down.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("选择预设模型")
        }
    }
}
