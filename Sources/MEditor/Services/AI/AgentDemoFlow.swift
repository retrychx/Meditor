import Foundation
import AppKit
import Observation

// MARK: - AgentDemoFlow（一键演示）

/// 首启引导里的「看看 Agent 能做什么」：把内置示例会议记录写入临时目录，
/// 打开为工作区并自动向 Agent 发一条整理指令，让新用户直接看到
/// 流式输出 + 工具调用 + 写确认 + 预览渲染的完整闭环。
///
/// 无 AI 配置时降级为离线预演（runSimulated）：同一份示例文档，
/// 用预录的整理稿以打字机节奏直接改写文档（与真实 Agent 写文档同走
/// updateTabContent → 预览随 contentRevision 实时重渲染），用户同样能看到
/// 「改文档 → 预览更新」的闭环；全程不触网、不需要 key。
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
        case running            // 已交给 AgentRunner / 打字机，界面实时展示
        case failed(String)
    }
    private(set) var phase: Phase = .idle

    /// 演示模式：已配置 → 真实 Agent；未配置 → 离线预演（纯逻辑，便于单测）
    enum Mode: Equatable {
        case live
        case simulated
    }
    static func mode(isConfigured: Bool) -> Mode {
        isConfigured ? .live : .simulated
    }

    /// 离线预演打字机帧间隔（测试注入 .zero 快进）
    var frameDelay: Duration = .milliseconds(22)

    /// 演示工作区固定路径（重跑覆盖，便于退出时一次性清理）
    static var demoDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("meditor-agent-demo", isDirectory: true)
    }
    static let demoFileName = "weekly-sync-meeting.md"

    // MARK: - 示例文案（按界面语言二选一）

    static var currentLanguage: AppLanguage { LocalizationManager.shared.resolved }

    /// 示例会议记录：故意写得零散，方便展示「整理」能力
    static var sampleMarkdown: String { sampleMarkdown(for: currentLanguage) }
    static var demoPrompt: String { demoPrompt(for: currentLanguage) }

    static func sampleMarkdown(for language: AppLanguage) -> String {
        language == .chinese ? sampleMarkdownZH : sampleMarkdownEN
    }

    static func tidyMarkdown(for language: AppLanguage) -> String {
        language == .chinese ? tidyMarkdownZH : tidyMarkdownEN
    }

    static func demoPrompt(for language: AppLanguage) -> String {
        language == .chinese
            ? "帮我整理这篇会议记录：提炼决议和待办事项，重排成结构清晰的会议纪要，直接修改当前文档。"
            : "Tidy up this meeting note: extract decisions and action items, restructure it into a clean meeting summary, and edit the current document directly."
    }

    static let sampleMarkdownZH = """
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

    static let tidyMarkdownZH = """
    # 周会同步纪要（8.18）

    **参会**：我、小李、小王、Amy（设计）

    ## 决议

    - 上线目标维持 9.1 不变
    - 为保进度，砍掉 WebDAV 同步功能
    - 登录模块优先联调（后端接口下周三就绪）

    ## 待办

    | 负责人 | 事项 | 时间 |
    | --- | --- | --- |
    | 小李 | 输出后端接口文档 | 下次会前 |
    | 小李 | 后端接口开发完成 | 下周三 |
    | Amy | 补齐设置页与 Onboarding 设计稿 | 下周内 |
    | 小王 | 跟进 iOS 15 崩溃率（当前 0.8%） | 持续 |

    ## 风险与遗留

    - 9.1 上线时间偏紧，团队普遍反馈有压力
    - 预算议题未讨论完，下次会议继续
    """

    static let sampleMarkdownEN = """
    # Weekly Sync 8/18

    attendees: me, Li, Wang, Amy (design)

    random notes:
    - Li says backend API won't be ready until next Wed, do login integration first
    - boss wants to ship on 9/1, everyone thinks it's tight
    - Amy still owes settings page and onboarding designs
    - Wang mentioned crash rate 0.8%, mostly on iOS 15
    - conclusion: 9/1 stays, cut WebDAV sync
    - Li to write API doc before next meeting
    - budget topic unfinished, continue next time
    """

    static let tidyMarkdownEN = """
    # Weekly Sync Summary (8/18)

    **Attendees**: me, Li, Wang, Amy (design)

    ## Decisions

    - Launch target stays at 9/1
    - Cut WebDAV sync to protect the schedule
    - Prioritize login integration (backend API ready next Wednesday)

    ## Action Items

    | Owner | Item | Due |
    | --- | --- | --- |
    | Li | Publish backend API doc | Before next sync |
    | Li | Finish backend API | Next Wednesday |
    | Amy | Deliver settings page & onboarding designs | Within a week |
    | Wang | Follow up iOS 15 crash rate (currently 0.8%) | Ongoing |

    ## Risks & Open Topics

    - 9/1 launch is tight; the team flagged schedule pressure
    - Budget discussion unfinished — continue next meeting
    """

    @ObservationIgnored private var terminateObserver: Any?

    // MARK: - 文件系统准备（可单测）

    /// 重建临时演示目录并写入示例文档，返回文档 URL。
    /// 纯文件系统操作，不触碰 AppState，便于单测直接验证。
    /// language 传 nil 时跟随当前界面语言。
    @discardableResult
    func prepareWorkspace(language: AppLanguage? = nil) throws -> URL {
        let language = language ?? Self.currentLanguage
        let dir = Self.demoDirectory
        let fm = FileManager.default
        try? fm.removeItem(at: dir)   // 清掉上一场演示的残留
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(Self.demoFileName)
        try Self.sampleMarkdown(for: language).write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// 删除演示目录（测试与退出清理共用）
    func cleanup() {
        try? FileManager.default.removeItem(at: Self.demoDirectory)
    }

    // MARK: - 演示入口

    /// 按配置状态自动选择演示模式（引导与设置页共用的唯一入口）
    func runAuto(appState: AppState, settings: AppSettings) async {
        let configured = AIConfig.current(settings, scene: .agent).isConfigured
        switch Self.mode(isConfigured: configured) {
        case .live:      await run(appState: appState, settings: settings)
        case .simulated: await runSimulated(appState: appState)
        }
    }

    // MARK: - 真实 Agent 演示

    func run(appState: AppState, settings: AppSettings) async {
        guard phase != .preparing else { return }   // 防重入
        phase = .preparing

        // 未配置 AI 时演示跑不起来，直接失败提示（引导 UI 会走 runAuto 的离线预演，正常不会走到这）
        let config = AIConfig.current(settings, scene: .agent)
        guard config.isConfigured else {
            phase = .failed(L("demo.notConfigured"))
            return
        }

        let fileURL: URL
        do {
            fileURL = try prepareWorkspace()
        } catch {
            phase = .failed(L("demo.createFailed", error.localizedDescription))
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

    // MARK: - 离线预演（无 key 降级）

    /// 打字机帧序列（纯函数，可单测）：从空文档起步，逐帧长到整理稿全文。
    /// 每帧都是下一帧的前缀，预览随 contentRevision 逐帧重渲染。
    static func simulatedFrames(to tidy: String, chunk: Int = 4) -> [String] {
        guard !tidy.isEmpty else { return [] }
        var frames: [String] = [""]
        var idx = tidy.startIndex
        while idx < tidy.endIndex {
            idx = tidy.index(idx, offsetBy: chunk, limitedBy: tidy.endIndex) ?? tidy.endIndex
            frames.append(String(tidy[..<idx]))
        }
        return frames
    }

    /// 无 AI 配置时的安全降级：不触网，用预录整理稿以打字机节奏改写示例文档。
    /// 结束后回到 idle，允许反复重看。
    func runSimulated(appState: AppState) async {
        guard phase != .preparing else { return }   // 防重入
        phase = .preparing

        let language = Self.currentLanguage
        let fileURL: URL
        do {
            fileURL = try prepareWorkspace(language: language)
        } catch {
            phase = .failed(L("demo.createFailed", error.localizedDescription))
            return
        }
        registerCleanupOnTerminate()

        if appState.rootURL == nil {
            appState.openFolder(Self.demoDirectory)
        }
        appState.openFile(FileItem(url: fileURL, isDirectory: false))
        appState.showingAIAssistant = true

        // 小文件同步加载，通常立即就绪；保留与 run 一致的轮询兜底（最长 6s）
        for _ in 0..<30 where appState.selectedTab?.url != fileURL || appState.selectedTab?.content.isEmpty != false {
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard let tab = appState.selectedTab, tab.url == fileURL, !tab.content.isEmpty else {
            phase = .failed(L("demo.openFailed"))
            return
        }

        phase = .running
        let tidy = Self.tidyMarkdown(for: language)
        for frame in Self.simulatedFrames(to: tidy) {
            // 与真实 Agent 的写文档路径一致（writeDocument → updateTabContent），
            // 编辑器与预览都随 contentRevision 实时刷新
            appState.updateTabContent(tab.id, content: frame)
            try? await Task.sleep(for: frameDelay)
        }
        appState.scheduleDebounceSave()
        // 改哪亮哪：整篇重排过，闪一遍全部标题块
        appState.flashPreviewChange(sourceRange: tidy.startIndex..<tidy.endIndex, in: tidy)
        appState.showToast(L("demo.simulatedDone"), icon: "checkmark.circle")
        phase = .idle
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
