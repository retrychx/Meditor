import SwiftUI

// MARK: - General tab

extension SettingsView {
    var generalContent: some View {
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

                settingsGroup(title: L("settings.section.editor")) {
                    settingsRow(label: L("settings.editorFont"), subtitle: L("settings.desc.editorFont")) {
                        SettingsMenu(
                            selection: bindableSettings.editorFontName,
                            options: EditorFont.allCases.map {
                                ($0.rawValue, $0 == .system ? L("settings.editorFont.system") : $0.displayName)
                            }
                        )
                        .frame(width: 170)
                    }
                    rowDivider
                    settingsStackedRow(label: L("settings.editorFontSize"), subtitle: L("settings.desc.editorFontSize")) {
                        HStack(spacing: DS.Space.md) {
                            Slider(value: editorFontSizeBinding, in: 11...24, step: 1)
                                .frame(maxWidth: .infinity)
                            Text("\(settings.editorFontSize) pt")
                                .font(DS.Font.mono(12))
                                .foregroundStyle(.secondary)
                                .frame(width: 42, alignment: .trailing)
                        }
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

                settingsGroup(title: L("settings.section.about")) {
                    settingsRow(label: "MEditor", subtitle: L("settings.version")) {
                        Text(UpdateController.shared.appVersion)
                            .font(DS.Font.mono(12))
                            .foregroundStyle(.secondary)
                    }
                    rowDivider
                    settingsRow(label: L("settings.autoCheckUpdates"), subtitle: L("settings.desc.autoCheckUpdates")) {
                        Toggle("", isOn: Binding(
                            get: { UpdateController.shared.automaticallyChecksForUpdates },
                            set: { UpdateController.shared.automaticallyChecksForUpdates = $0 }
                        )).labelsHidden()
                    }
                    rowDivider
                    settingsRow(label: L("settings.checkUpdates")) {
                        Button(L("settings.checkUpdates")) {
                            UpdateController.shared.checkForUpdates()
                        }
                    }
                }
            }
            .padding(DS.Space.lg)
        }
    }

    // MARK: - Bindings

    var fontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(settings.previewFontSize) },
            set: { settings.previewFontSize = Int($0) }
        )
    }

    var editorFontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(settings.editorFontSize) },
            set: { settings.editorFontSize = Int($0) }
        )
    }

    var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { loc.language },
            set: { loc.language = $0 }
        )
    }
}
