import SwiftUI

/// 本地 AI 配置页：provider 预设 / baseURL / apiKey / model，存 UserDefaults。
struct SettingsView: View {
    @Environment(MobileAISettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
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
                    sectionHeader("Provider")
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
                    sectionHeader("接口")
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
                    sectionHeader("模型")
                }

                Section {
                    Text("配置仅保存在本机，更改即刻生效。移动端暂不支持本地 Claude CLI。")
                        .font(.footnote)
                        .foregroundStyle(PaperTheme.inkSecondary)
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

    private func sectionHeader(_ title: String) -> some View {
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
