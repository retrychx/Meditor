import SwiftUI

struct SettingsView: View {
    @State private var settings = AppSettings.shared
    private let loc = LocalizationManager.shared
    @State private var selectedTab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text(L("settings.tab.general")).tag(0)
                Text(L("settings.tab.editor")).tag(1)
                Text(L("settings.tab.sharing")).tag(2)
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            .padding(.leading, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)

            Group {
                switch selectedTab {
                case 0: generalTab
                case 1: editorTab
                case 2: sharingTab
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 420, height: 300)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section {
                Picker(L("settings.language"), selection: languageBinding) {
                    Text(L("lang.system")).tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.english)
                    Text("中文").tag(AppLanguage.chinese)
                }
            } header: {
                Text(L("settings.section.language"))
            }

            Section {
                LabeledContent(L("settings.fontSize")) {
                    HStack(spacing: 6) {
                        Slider(value: fontSizeBinding, in: 10...28, step: 1)
                            .frame(width: 140)
                        Text("\(settings.previewFontSize) px")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            } header: {
                Text(L("settings.section.preview"))
            }

            Section {
                Toggle(L("settings.autoSave"), isOn: $settings.autoSave)
                if settings.autoSave {
                    LabeledContent(L("settings.interval")) {
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
            } header: {
                Text(L("settings.section.save"))
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Editor

    private var editorTab: some View {
        Form {
            Section {
                Toggle(L("settings.showSidebar"), isOn: $settings.showSidebarOnLaunch)
                Toggle(L("settings.showEditor"), isOn: $settings.showEditorOnLaunch)
                Toggle(L("settings.showPreview"), isOn: $settings.showPreviewOnLaunch)
            } header: {
                Text(L("settings.section.launchLayout"))
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Sharing

    private var sharingTab: some View {
        Form {
            Section {
                LabeledContent(L("settings.port")) {
                    TextField("", value: $settings.sharePort, format: .number)
                        .frame(width: 70)
                        .multilineTextAlignment(.trailing)
                }
                Text(L("settings.portHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L("settings.section.lanShare"))
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Helpers

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
