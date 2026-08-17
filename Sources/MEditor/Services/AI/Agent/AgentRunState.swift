import Foundation
import Observation

/// 停滞检测中断时的诊断信息：哪个工具卡住、连续失败次数、最后一次错误摘要。
/// 由 AgentRunner 在中断 run 时写入，供 UI 展示与日志排查。
struct AgentStallDiagnostic: Sendable, Equatable {
    var toolName: String
    var repeatCount: Int
    var lastErrorSummary: String
}

/// 单次后端响应 / 单次 run 的 token 用量。
/// 后端不返回 usage 字段时（如 ClaudeCLI 子进程）整体为 nil，不构造零值。
struct AgentUsage: Sendable, Equatable {
    var promptTokens = 0
    var completionTokens = 0

    static func + (lhs: AgentUsage, rhs: AgentUsage) -> AgentUsage {
        AgentUsage(promptTokens: lhs.promptTokens + rhs.promptTokens,
                   completionTokens: lhs.completionTokens + rhs.completionTokens)
    }
}

/// Agent 一次运行的可观测状态。
/// 生命周期独立于 AgentRunner：Runner 完成后 State 仍持有最终步骤历史，
/// 允许外层（AIConversation）在 Runner 被置 nil 后继续展示步骤面板。
@MainActor
@Observable
final class AgentRunState {
    var steps: [AgentRunnerStep] = []
    var isRunning: Bool = false
    var finalText: String = ""
    var error: String? = nil
    /// 最终回复因 max_tokens/length 被截断（UI 提示用，不自动续跑）
    var wasTruncated: Bool = false
    /// 因停滞检测中断时的诊断信息（正常结束为 nil）
    var stall: AgentStallDiagnostic? = nil
    /// 本轮累计 token 用量（各 step 响应 usage 之和；后端不返回 usage 时为 nil，UI 降级不显示）
    var usage: AgentUsage? = nil
    /// 本轮总耗时（run 收尾时写入；进行中为 nil）
    var runDurationSeconds: TimeInterval? = nil
    /// 本次 run 的文件快照（一键回滚用）。run 结束且确有写入时由发起方
    /// （AIChatCoordinator）挂入；仅内存、不落盘——快照随本状态一起丢弃，
    /// 重启后不可回滚（取舍见 AgentRunCheckpoint 头注释）。
    var checkpoint: AgentRunCheckpoint? = nil
}
