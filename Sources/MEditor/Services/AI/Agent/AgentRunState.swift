import Foundation
import Observation

/// 一次 run 的结束方式（断点续传入口判定用）。
/// - failed（网络/超时/模型错误/停滞/超步数）：可带着已完成的工具调用结果续跑；
/// - cancelled（用户主动取消）：不提供「继续」入口——用户已明确放弃本次运行。
enum AgentRunTermination: String, Equatable, Sendable {
    case running, completed, cancelled, failed
}

/// 停滞检测中断时的诊断信息：哪个工具卡住、连续失败次数、最后一次错误摘要。
/// 由 AgentRunner 在中断 run 时写入，供 UI 展示与日志排查。
struct AgentStallDiagnostic: Sendable, Equatable {
    var toolName: String
    var repeatCount: Int
    var lastErrorSummary: String
}

/// 单次后端响应 / 单次 run 的 token 用量。
/// 后端不返回 usage 字段时（如 ClaudeCLI 子进程）整体为 nil，不构造零值。
///
/// 口径约定（成本计算依赖此归一）：
///   - promptTokens = 全部输入 token（含缓存命中与缓存写入部分）。
///     OpenAI 的 prompt_tokens 本来就含 cached_tokens；Anthropic 的 input_tokens
///     不含缓存量，解析侧已把 cache_read/cache_creation 加回来，两边口径一致。
///   - cacheReadTokens / cacheWriteTokens 是 promptTokens 的子集，计价时按
///     (promptTokens - cacheRead - cacheWrite) × input 价 + 各自缓存价 计算。
struct AgentUsage: Sendable, Equatable, Codable {
    var promptTokens = 0
    var completionTokens = 0
    /// 缓存命中的输入 token（Anthropic cache_read / OpenAI cached_tokens）
    var cacheReadTokens = 0
    /// 写入缓存的输入 token（仅 Anthropic cache_creation；OpenAI 无此概念，保持 0）
    var cacheWriteTokens = 0

    static func + (lhs: AgentUsage, rhs: AgentUsage) -> AgentUsage {
        AgentUsage(promptTokens: lhs.promptTokens + rhs.promptTokens,
                   completionTokens: lhs.completionTokens + rhs.completionTokens,
                   cacheReadTokens: lhs.cacheReadTokens + rhs.cacheReadTokens,
                   cacheWriteTokens: lhs.cacheWriteTokens + rhs.cacheWriteTokens)
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
    /// 本次 run 使用的模型名（成本估算用；UI 据此查内置价格表，查不到则只显示 token 数）
    var modelName: String? = nil
    /// 本轮总耗时（run 收尾时写入；进行中为 nil）
    var runDurationSeconds: TimeInterval? = nil
    /// 本次 run 的文件快照（一键回滚用）。run 结束且确有写入时由发起方
    /// （AIChatCoordinator）挂入；仅内存、不落盘——快照随本状态一起丢弃，
    /// 重启后不可回滚（取舍见 AgentRunCheckpoint 头注释）。
    var checkpoint: AgentRunCheckpoint? = nil
    /// 结束方式（断点续传判定）：.failed 时 UI 提供「从中断处继续」，
    /// .cancelled（用户主动取消）不提供。由 AgentRunner 在收尾/cancel 时写入。
    var termination: AgentRunTermination = .running
}
