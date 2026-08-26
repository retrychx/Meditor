import SwiftUI
import AppKit

// MARK: - About tab（版本 / 更新 / 链接）

extension SettingsView {
    var aboutContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                settingsGroup(title: L("settings.section.about")) {
                    settingsRow(label: "MEditor", subtitle: L("settings.version")) {
                        Text(UpdateController.shared.appVersion)
                            .font(DS.Font.mono(12))
                            .foregroundStyle(.secondary)
                    }
                    rowDivider
                    settingsRow(label: L("settings.about.website")) {
                        Button("meditorapp.pages.dev") {
                            NSWorkspace.shared.open(URL(string: "https://meditorapp.pages.dev")!)
                        }
                    }
                }

                settingsGroup(title: L("settings.softwareUpdate")) {
                    settingsRow(label: L("settings.autoCheckUpdates"), subtitle: L("settings.desc.autoCheckUpdates")) {
                        Toggle("", isOn: Binding(
                            get: { UpdateController.shared.automaticallyChecksForUpdates },
                            set: { UpdateController.shared.automaticallyChecksForUpdates = $0 }
                        )).labelsHidden()
                    }
                    rowDivider
                    settingsRow(label: L("settings.softwareUpdate"), subtitle: L("settings.desc.checkUpdates")) {
                        Button(L("settings.checkUpdates")) {
                            UpdateController.shared.checkForUpdates()
                        }
                    }
                }
            }
            .padding(DS.Space.lg)
        }
    }
}
