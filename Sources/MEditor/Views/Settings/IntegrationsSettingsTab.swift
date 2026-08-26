import SwiftUI
import AppKit

// MARK: - Integrations tab（外部集成：Claude Code 监听 / MCP 服务器）

extension SettingsView {
    var integrationsContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Claude Code 监听
                claudeMonitorSection

                // MCP 服务器（外部 Agent 接入）
                settingsGroup(title: L("settings.ai.mcp")) {
                    settingsStackedRow(label: L("settings.ai.mcpConfigLabel"), subtitle: L("settings.ai.mcpHint")) {
                        HStack(alignment: .top, spacing: 8) {
                            Text(mcpConfigSnippet)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            Button(L("settings.ai.mcpCopy")) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(mcpConfigSnippet, forType: .string)
                                state.showToast(L("settings.ai.mcpCopied"), icon: "doc.on.doc")
                            }
                        }
                    }
                }
            }
            .padding(DS.Space.lg)
        }
    }

    /// Claude Desktop 的 MCP 配置片段：命令指向当前运行的 app 内二进制，
    /// 工作区默认填当前打开的目录（未打开时留占位提示用户替换）。
    var mcpConfigSnippet: String {
        let binary = Bundle.main.executableURL?.path ?? "/Applications/MEditor.app/Contents/MacOS/MEditor"
        let workspace = state.rootURL?.path ?? "/path/to/your/workspace"
        return """
        {
          "mcpServers": {
            "meditor": {
              "command": "\(binary)",
              "args": ["mcp", "--workspace", "\(workspace)"]
            }
          }
        }
        """
    }

    // MARK: - Claude Code 监听

    var claudeMonitorSection: some View {
        settingsGroup(title: L("settings.ai.claudeIntegration")) {
            settingsRow(label: L("settings.ai.monitorFiles"), subtitle: L("settings.ai.monitorFilesHint")) {
                Toggle("", isOn: bindableSettings.claudeMonitorEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            if settings.claudeMonitorEnabled {
                rowDivider

                settingsStackedRow(
                    label: L("settings.ai.monitorDir"),
                    subtitle: L("settings.ai.monitorDirHint")
                ) {
                    HStack(spacing: 8) {
                        TextField("~/.claude/projects/", text: bindableSettings.claudeMonitorCustomPath)
                            .textFieldStyle(.plain)
                            .settingsField()
                        Button(L("settings.ai.choose")) { selectClaudeMonitorDir() }
                    }
                }

                rowDivider

                settingsStackedRow(
                    label: L("settings.ai.fileTypes"),
                    subtitle: L("settings.ai.fileTypesHint")
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
                    Text(L("settings.ai.monitorDirInfo", settings.claudeMonitorDirectory.path))
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
            if let url = await state.filePickerService.pickFolder(message: L("settings.ai.pickClaudeDir")) {
                settings.claudeMonitorCustomPath = url.path
            }
        }
    }
}
