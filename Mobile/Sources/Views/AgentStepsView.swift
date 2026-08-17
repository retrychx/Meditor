import SwiftUI

/// Agent 工具步骤条：聊天回复上方的过程可视化（读/改/搜一目了然）。
/// 运行中（live）逐步展示（spinner）；结束后默认折叠成一行安静摘要，
/// 点按才展开回放明细——历史消息不再被成排的勾叉刷屏。
/// 工具名 → 文案/图标走共享层 AgentToolDisplay（与桌面端 AgentStepView 同源）。
struct AgentStepsView: View {
    let steps: [AgentRunnerStep]
    /// true = 运行中实时展示；false = 历史快照，默认折叠。
    var live: Bool = false

    @State private var expanded = false

    var body: some View {
        if live {
            rows
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(PaperTheme.Motion.quick) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                        Text("已完成 \(steps.count) 个步骤")
                            .font(.footnote)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(PaperTheme.inkSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if expanded {
                    rows
                }
            }
        }
    }

    private var rows: some View {
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
        case .toolCallDone(_, let name, let args, _, let isError, _):
            let info = AgentToolDisplay.info(name: name, args: args)
            HStack(spacing: 7) {
                Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(isError ? .red : .green)
                    .contentTransition(.symbolEffect(.replace))
                Label(info.text, systemImage: info.icon)
                    .font(.footnote)
                    .foregroundStyle(isError ? .red : PaperTheme.inkSecondary)
            }
        }
    }
}
