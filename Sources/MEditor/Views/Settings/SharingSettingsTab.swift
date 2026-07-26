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

                shareLinkSettingsGroup
            }
            .padding(DS.Space.lg)
        }
        .onAppear {
            state.githubGistManager.refreshTokenStatus()
            state.shareLinkPublisher.refreshTokenStatus()
        }
    }

    @ViewBuilder
    var shareLinkSettingsGroup: some View {
        let pub = state.shareLinkPublisher
        settingsGroup(title: L("sharelink.title")) {
            settingsStackedRow(label: L("sharelink.baseURL"), subtitle: L("sharelink.baseURLHint")) {
                TextField("https://…workers.dev", text: bindableSettings.shareBaseURL)
                    .textFieldStyle(.plain)
                    .settingsField()
            }
            rowDivider
            settingsStackedRow(label: L("sharelink.token"), subtitle: L("sharelink.tokenHint")) {
                if pub.hasToken {
                    HStack(spacing: 8) {
                        Text("•••••••• " + L("sharelink.tokenConfigured"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .settingsField()
                        Button(L("sharelink.clearToken")) { pub.clearToken() }
                    }
                } else {
                    HStack(spacing: 8) {
                        SecureField("token…", text: $shareLinkTokenInput)
                            .textFieldStyle(.plain)
                            .settingsField()
                        Button(L("sharelink.saveToken")) {
                            pub.saveToken(shareLinkTokenInput)
                            shareLinkTokenInput = ""
                        }
                        .disabled(shareLinkTokenInput.isEmpty)
                    }
                }
            }
        }
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
