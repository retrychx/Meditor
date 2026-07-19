import SwiftUI

// MARK: - Command confirm bar

extension AIAssistantPanel {
    /// agent step 流里的「待确认执行命令」确认条。
    @ViewBuilder
    func commandConfirmBar(_ pending: PendingCommand) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
                Text("待确认执行命令")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.craftPrimary)
            }
            Text(pending.command)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.craftPrimary)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.editorBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            if let cwd = pending.cwd {
                Text("目录：\(cwd)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(theme.craftSecondary)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("拒绝") { pending.reject() }
                    .buttonStyle(.bordered)
                Button("执行") { pending.approve() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.appAccent)
            }
            Text("确认后本次会话不再询问")
                .font(.system(size: 10))
                .foregroundStyle(theme.craftSecondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
    }
}
