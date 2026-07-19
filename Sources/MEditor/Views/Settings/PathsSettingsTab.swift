import SwiftUI

// MARK: - Paths tab

extension SettingsView {
    var pathsContent: some View {
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

    func chooseUserDocPath() {
        Task {
            if let url = await state.filePickerService.pickFolder(message: nil) {
                try? AppSettings.shared.setUserDocPath(url)
            }
        }
    }

    func chooseAppDocPath() {
        Task {
            if let url = await state.filePickerService.pickFolder(message: nil) {
                try? AppSettings.shared.setAppDocPath(url)
            }
        }
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
