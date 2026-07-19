import SwiftUI

/// Agent 工具步骤条：聊天回复上方的过程可视化（读/改/搜一目了然）。
/// 运行中由 ChatModel.runner.steps 驱动（spinner），结束后用消息里的快照回放（勾/叉）。
/// 工具名 → 文案/图标走共享层 AgentToolDisplay（与桌面端 AgentStepView 同源）。
struct AgentStepsView: View {
    let steps: [AgentRunnerStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(steps) { step in
                row(step)
            }
        }
    }

    @ViewBuilder
    private func row(_ step: AgentRunnerStep) -> some View {
        switch step {
        case .thinking(let label, _):
            HStack(spacing: 7) {
                ProgressView().controlSize(.mini)
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(PaperTheme.inkSecondary)
            }
        case .toolCall(_, let name, let args):
            let info = AgentToolDisplay.info(name: name, args: args)
            HStack(spacing: 7) {
                ProgressView().controlSize(.mini)
                    .frame(width: 12, height: 12)
                Label(info.text, systemImage: info.icon)
                    .font(.footnote)
                    .foregroundStyle(PaperTheme.inkSecondary)
            }
        case .toolCallDone(_, let name, let args, _, let isError):
            let info = AgentToolDisplay.info(name: name, args: args)
            HStack(spacing: 7) {
                Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(isError ? .red : .green)
                Label(info.text, systemImage: info.icon)
                    .font(.footnote)
                    .foregroundStyle(isError ? .red : PaperTheme.inkSecondary)
            }
        }
    }
}
