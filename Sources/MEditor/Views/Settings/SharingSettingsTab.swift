import SwiftUI

// MARK: - Sharing tab

extension SettingsView {
    var sharingContent: some View {
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
    var githubGistSettingsGroup: some View {
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
}
