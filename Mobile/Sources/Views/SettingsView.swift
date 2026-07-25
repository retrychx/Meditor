import SwiftUI

/// 设置根列表：AI 服务 / AI 技能 / 关于 三个子页。
/// 行尾带当前状态摘要（系统设置范式），页面不再一屏滚到底。
struct SettingsView: View {
    @Environment(MobileAISettings.self) private var settings
    @Environment(AppAppearance.self) private var appearance

    var body: some View {
        @Bindable var appearance = appearance
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        AIServiceSettingsView()
                    } label: {
                        HStack {
                            Label("AI 服务", systemImage: "sparkles")
                            Spacer()
                            Text(serviceSummary)
                                .font(.subheadline)
                                .foregroundStyle(PaperTheme.inkSecondary)
                                .lineLimit(1)
                        }
                    }
                    NavigationLink {
                        AISkillsSettingsView()
                    } label: {
                        HStack {
                            Label("AI 技能", systemImage: "square.grid.2x2")
                            Spacer()
                            Text(skillSummary)
                                .font(.subheadline)
                                .foregroundStyle(PaperTheme.inkSecondary)
                        }
                    }
                } header: {
                    sectionHeader("AI")
                }

                Section {
                    Picker(selection: $appearance.mode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    } label: {
                        Label("外观", systemImage: "circle.lefthalf.filled")
                    }
                }

                Section {
                    Text("配置仅保存在本机，更改即刻生效。移动端暂不支持本地 Claude CLI。")
                        .font(.footnote)
                        .foregroundStyle(PaperTheme.inkSecondary)
                } header: {
                    sectionHeader("关于")
                }
            }
            .scrollContentBackground(.hidden)
            .background(PaperTheme.paper)
            .listRowBackground(PaperTheme.card)
            .foregroundStyle(PaperTheme.ink)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// AI 服务摘要：关闭 / 预设名 / 自定义 baseURL 的模型。
    private var serviceSummary: String {
        if settings.provider == .disabled { return "关闭" }
        if let preset = settings.matchedPreset { return preset.name }
        return settings.model.isEmpty ? "自定义" : settings.model
    }

    private var skillSummary: String {
        "\(MobileSkillStore.shared.enabledSkills.count)/\(MobileSkills.all.count) 启用"
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(PaperTheme.inkSecondary)
    }
}

// MARK: - AI 服务（提供商 / 接口 / 模型）

/// 本地 AI 配置页：provider 预设 / baseURL / apiKey / model，存 UserDefaults。
private struct AIServiceSettingsView: View {
    @Environment(MobileAISettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("预设", selection: presetBinding) {
                    ForEach(AIPresets.all) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                    Text("自定义").tag("custom")
                }
                Picker("类型", selection: $settings.provider) {
                    Text("关闭（预览）").tag(AIProviderKind.disabled)
                    Text("OpenAI 兼容").tag(AIProviderKind.openai)
                    Text("Anthropic").tag(AIProviderKind.anthropic)
                }
            } header: {
                header("Provider")
            }

            Section {
                TextField("Base URL", text: $settings.baseURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("API Key", text: $settings.apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                header("接口")
            }

            Section {
                TextField("Model", text: $settings.model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let preset = settings.matchedPreset, !preset.models.isEmpty {
                    Picker("常用模型", selection: $settings.model) {
                        ForEach(preset.models, id: \.self) { Text($0).tag($0) }
                    }
                }
            } header: {
                header("模型")
            }
        }
        .scrollContentBackground(.hidden)
        .background(PaperTheme.paper)
        .listRowBackground(PaperTheme.card)
        .foregroundStyle(PaperTheme.ink)
        .navigationTitle("AI 服务")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(PaperTheme.inkSecondary)
    }

    /// 预设选择：匹配当前 baseURL 的预设，否则 "custom"。
    private var presetBinding: Binding<String> {
        Binding(
            get: { settings.matchedPreset?.id ?? "custom" },
            set: { id in
                if let preset = AIPresets.all.first(where: { $0.id == id }) {
                    settings.applyPreset(preset)
                }
            }
        )
    }
}

// MARK: - AI 技能

/// 技能开关页：启用的技能注入 AI 对话，并在输入栏上方提供快捷指令。
private struct AISkillsSettingsView: View {
    var body: some View {
        Form {
            Section {
                ForEach(MobileSkills.all) { skill in
                    Toggle(isOn: skillBinding(skill.id)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(skill.name, systemImage: skill.icon)
                            Text(skill.description)
                                .font(.footnote)
                                .foregroundStyle(PaperTheme.inkSecondary)
                        }
                    }
                }
            } footer: {
                Text("启用的技能会注入 AI 对话，并在输入栏上方提供快捷指令。")
                    .font(.footnote)
                    .foregroundStyle(PaperTheme.inkSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(PaperTheme.paper)
        .listRowBackground(PaperTheme.card)
        .foregroundStyle(PaperTheme.ink)
        .navigationTitle("AI 技能")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 技能开关绑定：读写 MobileSkillStore 单例。
    private func skillBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { MobileSkillStore.shared.isEnabled(id) },
            set: { MobileSkillStore.shared.setEnabled(id, $0) }
        )
    }
}
