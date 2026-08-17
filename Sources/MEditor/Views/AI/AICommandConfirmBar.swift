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
                Text(L("ai.command.pendingTitle"))
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
                Text(L("ai.command.cwd", cwd))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(theme.craftSecondary)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                Spacer()
                Button(L("ai.command.reject")) { pending.reject() }
                    .buttonStyle(.bordered)
                Button(L("ai.execute")) { pending.approve() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.appAccent)
            }
            Text(L("ai.command.rememberHint"))
                .font(.system(size: 10))
                .foregroundStyle(theme.craftSecondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - File write confirm bar

extension AIAssistantPanel {
    /// agent step 流里的「待确认文件写入」确认条（与 commandConfirmBar 同一范式）。
    /// 多一个「本次运行全部允许」：置位 run 级开关，之后本 run 的写工具直接放行。
    @ViewBuilder
    func writeConfirmBar(_ pending: PendingWrite) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "doc.badge.gearshape")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(L("ai.write.pendingTitle"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.craftPrimary)
            }
            Text(pending.path)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.craftPrimary)
                .textSelection(.enabled)
                .lineLimit(2)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.editorBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            Text(pending.summary)
                .font(.system(size: 10.5))
                .foregroundStyle(theme.craftSecondary)
                .lineLimit(2)
            HStack(spacing: 8) {
                Spacer()
                Button(L("ai.command.reject")) { pending.reject() }
                    .buttonStyle(.bordered)
                Button(L("ai.write.allowAll")) { pending.approveAll() }
                    .buttonStyle(.bordered)
                Button(L("ai.write.allow")) { pending.approve() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.appAccent)
            }
            Text(L("ai.write.allowAllHint"))
                .font(.system(size: 10))
                .foregroundStyle(theme.craftSecondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
    }
}
