import Foundation
import AppKit
import Observation

// MARK: - AgentDemoFlow（一键演示）

/// 首启引导里的「看一个 30 秒演示」：把内置示例会议记录写入临时目录，
/// 打开为工作区并自动向 Agent 发一条整理指令，让新用户直接看到
/// 流式输出 + 工具调用 + 写确认 + 预览渲染的完整闭环。
///
/// 安全约束：
///  - 演示文件只写 `NSTemporaryDirectory()/meditor-agent-demo/`，绝不污染用户工作区
///  - 每次重跑先清空旧演示目录；App 退出时（willTerminate）兜底清理
@MainActor
@Observable
final class AgentDemoFlow {

    /// 演示阶段（UI 据此禁用按钮 / 显示状态）
    enum Phase: Equatable {
        case idle
        case preparing
        case running            // 已交给 AgentRunner，面板实时展示
        case failed(String)
    }
    private(set) var phase: Phase = .idle

    /// 演示工作区固定路径（重跑覆盖，便于退出时一次性清理）
    static var demoDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meditor-agent-demo", isDirectory: true)
    }
    static let demoFileName = "weekly-sync-meeting.md"

    /// 示例会议记录：故意写得零散，方便 Agent 展示「整理」能力
    static let sampleMarkdown = """
    # 周会同步 8.18

    参会：我、小李、小王、设计 Amy

    随便记的：
    - 小李说后端接口下周三才能好，登录那块先联调
    - 上线时间老板想 9.1，大家觉得紧
    - Amy 设计稿还差设置页和 onboarding
    - 小王提了下崩溃率 0.8% 的事，主要是 iOS 15
    - 结论：9.1 目标不变，功能砍 WebDAV 同步
    - 下次会前小李出接口文档
    - 预算的事没聊完，下次继续
    """

    static let demoPrompt = "帮我整理这篇会议记录：提炼决议和待办事项，重排成结构清晰的会议纪要，直接修改当前文档。"

    @ObservationIgnored private var terminateObserver: Any?

    // MARK: - 文件系统准备（可单测）

    /// 重建临时演示目录并写入示例文档，返回文档 URL。
    /// 纯文件系统操作，不触碰 AppState，便于单测直接验证。
    @discardableResult
    func prepareWorkspace() throws -> URL {
        let dir = Self.demoDirectory
        let fm = FileManager.default
        try? fm.removeItem(at: dir)   // 清掉上一场演示的残留
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(Self.demoFileName)
        try Self.sampleMarkdown.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// 删除演示目录（测试与退出清理共用）
    func cleanup() {
        try? FileManager.default.removeItem(at: Self.demoDirectory)
    }

    // MARK: - 演示主流程

    func run(appState: AppState, settings: AppSettings) async {
        guard phase != .preparing else { return }   // 防重入
        phase = .preparing

        // 未配置 AI 时演示跑不起来，直接失败提示（引导 UI 正常不会走到这）
        let config = AIConfig.current(settings, scene: .agent)
        guard config.isConfigured else {
            phase = .failed("尚未配置 AI，请先完成上方配置")
            return
        }

        let fileURL: URL
        do {
            fileURL = try prepareWorkspace()
        } catch {
            phase = .failed("演示文件创建失败：\(error.localizedDescription)")
            return
        }
        registerCleanupOnTerminate()

        // 与 DebugDemoInlineFlow 一致：先开父目录（否则欢迎页不会因 rootURL 为空而退出）
        if appState.rootURL == nil {
            appState.openFolder(Self.demoDirectory)
        }
        appState.openFile(FileItem(url: fileURL, isDirectory: false))
        // 确保 AI 面板可见，用户能直接看到 Agent 运行
        appState.showingAIAssistant = true

        // 文件内容异步加载：轮询等待（最长 6s），与 DebugDemoInlineFlow 同一策略
        for _ in 0..<30 where appState.selectedTab?.url != fileURL || appState.selectedTab?.content.isEmpty != false {
            try? await Task.sleep(for: .milliseconds(200))
        }

        // 发一条真实用户消息，走与手动输入完全相同的 AgentRunner 链路
        // （流式 → 工具调用 → 写确认 → 预览渲染全部真实发生）
        let convo = appState.aiConversation
        convo.messages.append(AIChatMessage(role: .user, text: Self.demoPrompt))
        convo.persist()
        phase = .running
        AIChatCoordinator(settings: settings, conversation: convo, appState: appState).runCompletion()
    }

    /// App 退出时兜底清理演示目录（只注册一次）
    private func registerCleanupOnTerminate() {
        guard terminateObserver == nil else { return }
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { _ in
            try? FileManager.default.removeItem(at: AgentDemoFlow.demoDirectory)
        }
    }
}
