import Foundation

/// 发给后端的 agent 历史的上下文预算裁剪。
///
/// 背景：工具读回的大结果（read_file / read_document 单条可达 64K 字符）会永久留在
/// agentHistory 里逐轮重发，长 run 后期每轮都在为无用的旧结果付费。持久化历史保持完整，
/// 本模块只在 AgentRunner 每次请求后端前对「线上副本」做预算裁剪（存储层不改）。
///
/// 两级策略（优先保配对、保最近上下文）：
/// 1. system + 最近 N 条消息完整保留；更早历史里的长 tool 结果替换为占位符
///    （只改 content，消息条数与角色序列不变，tool_call / tool_result 配对天然保持）。
/// 2. 仍超预算才从最老一端整轮裁掉，边界不落在 tool 消息上（同 truncateIfOverLimit 的对齐规则）。
enum AgentHistoryBudget {

    /// 默认预算（token 估算值）。主流模型上下文窗口已在 100K~128K 级，取约一半的保守值：
    /// 为 system prompt（可达数千 token）与输出预留空间，同时让早期大工具结果及时淘汰。
    /// 先做常量而非设置项：预算取决于模型窗口而 App 并不感知用户配的模型，暴露 UI 反而易配错；
    /// 确有需求时再开放（类比 AIConversation 的 128K 阈值同样是写死的常量）。
    static let defaultBudgetTokens = 60_000

    /// 完整保留的最近消息条数：模型对最近上下文最敏感，尾部不参与任何裁剪。
    static let defaultKeepRecentMessages = 8

    /// 短于该长度的 tool 结果不值得替换（占位符本身也占 token）。
    static let minToolResultChars = 400

    /// 长 tool 结果的占位文案：同时是给模型的指引——仍需内容时重新调用工具读取。
    static let toolResultPlaceholder = "[早前读取的内容已省略，如仍需请用工具重新读取]"

    /// 裁剪结果摘要（也用于 UI 提示）。
    struct TrimResult: Sendable {
        var messages: [AgentMessage]
        /// 被占位符替换的早期 tool 结果条数（仅计仍保留在结果里的）
        var evictedToolResults: Int
        /// 第二级整轮裁掉的消息条数
        var droppedMessages: Int
        var didTrim: Bool { evictedToolResults > 0 || droppedMessages > 0 }
    }

    /// 对要发给后端的消息列表做预算裁剪，返回裁剪副本；输入不被修改。
    /// token 估算复用 AIConversation.estimateTokens 的混合语言启发式，与截断/banner 口径一致。
    static func trim(
        _ messages: [AgentMessage],
        budgetTokens: Int = defaultBudgetTokens,
        keepRecentMessages: Int = defaultKeepRecentMessages
    ) -> TrimResult {
        var result = messages
        var estimates = messages.map { AIConversation.estimateTokens($0.content) }
        var total = estimates.reduce(0, +)
        guard total > budgetTokens else {
            return TrimResult(messages: result, evictedToolResults: 0, droppedMessages: 0)
        }

        // system 固定在头部；尾部最近 N 条完整保留
        let headStart = messages.first?.role == .system ? 1 : 0
        var protectedFrom = max(headStart, messages.count - keepRecentMessages)
        // 保护边界不能劈开 tool_call/tool_result 配对：边界处若是 tool 结果，
        // 其 assistant(toolCalls) 落在非保护区，第二级裁掉它会留下孤儿 result
        // （API 直接报错）。把边界前移，让整对进入保护尾部。
        while protectedFrom > headStart, protectedFrom < result.count,
              result[protectedFrom].role == .tool {
            protectedFrom -= 1
        }

        // 第一级：更早历史里的长 tool 结果替换为占位符（只改 content，配对天然保持）
        var evicted = 0
        if protectedFrom > headStart {
            let placeholderEstimate = AIConversation.estimateTokens(toolResultPlaceholder)
            for i in headStart..<protectedFrom
            where result[i].role == .tool && result[i].content.count >= minToolResultChars {
                total += placeholderEstimate - estimates[i]
                estimates[i] = placeholderEstimate
                result[i].content = toolResultPlaceholder
                evicted += 1
            }
        }
        guard total > budgetTokens else {
            return TrimResult(messages: result, evictedToolResults: evicted, droppedMessages: 0)
        }

        // 第二级：仍超预算，从最老一端整轮裁掉（不裁进保护尾部；
        // 边界不能落在 tool 消息上——它连同前面的 assistant(toolCalls) 一起整轮丢弃）。
        // 保护尾部即使超预算也不再牺牲：那是本轮对话的进行时上下文。
        var start = headStart
        while total > budgetTokens, start < protectedFrom {
            total -= estimates[start]
            start += 1
            while start < protectedFrom, result[start].role == .tool {
                total -= estimates[start]
                start += 1
            }
        }
        let finalMessages = Array(result[0..<headStart]) + Array(result[start...])
        // 被淘汰后又遭整轮裁掉的占位不再计入提示数（避免对用户虚报）
        let remainingEvicted = finalMessages.reduce(0) {
            $0 + ($1.role == .tool && $1.content == toolResultPlaceholder ? 1 : 0)
        }
        return TrimResult(
            messages: finalMessages,
            evictedToolResults: remainingEvicted,
            droppedMessages: start - headStart
        )
    }
}
