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
    /// 流式累积文本（实时显示用，每个 step 重置）
    var streamText: String = ""
}
