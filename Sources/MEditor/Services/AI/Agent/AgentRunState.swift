import Foundation
import Observation

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
}
