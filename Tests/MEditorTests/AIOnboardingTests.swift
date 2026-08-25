import XCTest
@testable import MEditor

// MARK: - AIOnboardingTests
//
// Phase 1 首启引导：无 key 时展示、配置后消失、跳过后不再打扰；
// 一键演示的工作区准备/清理与未配置防护。

final class AIOnboardingTests: XCTestCase {

    // MARK: - 引导显隐逻辑

    func test_shouldShow_unconfiguredNotDismissed() {
        XCTAssertTrue(AIOnboardingLogic.shouldShow(isConfigured: false, dismissed: false),
                      "从未配置且未跳过 → 显示引导")
    }

    func test_shouldHide_afterConfigured() {
        XCTAssertFalse(AIOnboardingLogic.shouldShow(isConfigured: true, dismissed: false),
                       "配置完成后引导自动消失（无需额外标记）")
    }

    func test_shouldHide_afterDismissed() {
        XCTAssertFalse(AIOnboardingLogic.shouldShow(isConfigured: false, dismissed: true),
                       "用户跳过（或就绪后点开始对话）后不再打扰")
    }

    func test_shouldHide_configuredAndDismissed() {
        XCTAssertFalse(AIOnboardingLogic.shouldShow(isConfigured: true, dismissed: true))
    }
}

// MARK: - AgentDemoFlowTests

@MainActor
final class AgentDemoFlowTests: XCTestCase {

    override func tearDown() {
        // 兜底：测试若在 prepare 后失败，不能留演示目录在临时目录里
        AgentDemoFlow().cleanup()
        super.tearDown()
    }

    // MARK: - 工作区准备：写入示例会议记录到临时目录

    func test_prepareWorkspace_writesSampleFileInTempDir() throws {
        let flow = AgentDemoFlow()
        let fileURL = try flow.prepareWorkspace()

        XCTAssertTrue(fileURL.path.hasPrefix(NSTemporaryDirectory()),
                      "演示文件必须落在临时目录，不能污染用户工作区")
        XCTAssertEqual(fileURL.lastPathComponent, AgentDemoFlow.demoFileName)

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(content, AgentDemoFlow.sampleMarkdown)
        XCTAssertFalse(content.isEmpty, "示例内容必须非空")
        XCTAssertNotEqual(content, AgentDemoFlow.tidyMarkdown(for: LocalizationManager.shared.resolved),
                          "示例（凌乱版）必须与整理稿不同")
    }

    // MARK: - 重跑：先清旧目录再写（幂等）

    func test_prepareWorkspace_rerunIsIdempotent() throws {
        let flow = AgentDemoFlow()
        let first = try flow.prepareWorkspace()
        // 模拟上一场演示被 Agent 改过
        try "modified".write(to: first, atomically: true, encoding: .utf8)
        let second = try flow.prepareWorkspace()
        XCTAssertEqual(first, second)
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), AgentDemoFlow.sampleMarkdown,
                       "重跑必须恢复为原始示例内容")
    }

    // MARK: - 清理

    func test_cleanup_removesDemoDirectory() throws {
        let flow = AgentDemoFlow()
        let fileURL = try flow.prepareWorkspace()
        flow.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: AgentDemoFlow.demoDirectory.path))
    }

    // MARK: - 状态流转：未配置 AI → failed，不写任何文件

    func test_run_withoutConfiguration_failsFast() async {
        let settings = AppSettings.shared
        let originalProvider = settings.aiProvider
        let originalCLIPath = settings.aiCLIPath
        defer {
            settings.aiProvider = originalProvider
            settings.aiCLIPath = originalCLIPath
        }
        settings.aiProvider = AIProviderKind.disabled.rawValue
        settings.aiCLIPath = ""

        let flow = AgentDemoFlow()
        await flow.run(appState: AppState(), settings: settings)

        guard case .failed(let message) = flow.phase else {
            return XCTFail("未配置 AI 时演示必须进入 failed，实际 \(flow.phase)")
        }
        XCTAssertEqual(message, L("demo.notConfigured"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: AgentDemoFlow.demoDirectory.path),
                       "失败快路径不得写演示文件")
    }

    // MARK: - 演示模式选择：有配置 → 真实 Agent；无配置 → 离线预演

    func test_mode_liveWhenConfigured_simulatedOtherwise() {
        XCTAssertEqual(AgentDemoFlow.mode(isConfigured: true), .live)
        XCTAssertEqual(AgentDemoFlow.mode(isConfigured: false), .simulated)
    }

    // MARK: - 示例文案按界面语言二选一（CI 英文 locale，不写死中文）

    func test_sampleContent_localizedPerLanguage() {
        let zh = AgentDemoFlow.sampleMarkdown(for: .chinese)
        let en = AgentDemoFlow.sampleMarkdown(for: .english)
        XCTAssertFalse(zh.isEmpty)
        XCTAssertFalse(en.isEmpty)
        XCTAssertNotEqual(zh, en, "中英示例必须是两份不同文案")
        // 整理稿与原始记录必须不同且非空（演示的「整理」效果才有对比）
        XCTAssertNotEqual(zh, AgentDemoFlow.tidyMarkdown(for: .chinese))
        XCTAssertNotEqual(en, AgentDemoFlow.tidyMarkdown(for: .english))
        XCTAssertFalse(AgentDemoFlow.demoPrompt(for: .chinese).isEmpty)
        XCTAssertFalse(AgentDemoFlow.demoPrompt(for: .english).isEmpty)
    }

    func test_prepareWorkspace_writesLocalizedSample() throws {
        let flow = AgentDemoFlow()
        let zhFile = try flow.prepareWorkspace(language: .chinese)
        XCTAssertEqual(try String(contentsOf: zhFile, encoding: .utf8),
                       AgentDemoFlow.sampleMarkdown(for: .chinese))
        let enFile = try flow.prepareWorkspace(language: .english)
        XCTAssertEqual(try String(contentsOf: enFile, encoding: .utf8),
                       AgentDemoFlow.sampleMarkdown(for: .english))
    }

    // MARK: - 离线预演打字机帧序列

    func test_simulatedFrames_buildsUpToFullTidyText() {
        let tidy = AgentDemoFlow.tidyMarkdown(for: LocalizationManager.shared.resolved)
        let frames = AgentDemoFlow.simulatedFrames(to: tidy)
        XCTAssertEqual(frames.last, tidy, "最后一帧必须是整理稿全文")
        XCTAssertTrue(frames.first?.isEmpty == true, "从空文档起步")
        for (a, b) in zip(frames, frames.dropFirst()) {
            XCTAssertTrue(b.hasPrefix(a), "每帧必须是下一帧的前缀")
            XCTAssertGreaterThan(b.count, a.count, "帧序列必须单调增长")
        }
        XCTAssertEqual(AgentDemoFlow.simulatedFrames(to: ""), [])
    }

    // MARK: - 离线预演端到端：无 key 也能把示例文档改写成整理稿

    func test_runSimulated_rewritesDemoDocumentOffline() async {
        let flow = AgentDemoFlow()
        flow.frameDelay = .zero
        let appState = AppState()
        await flow.runSimulated(appState: appState)

        XCTAssertEqual(flow.phase, .idle, "离线预演结束后回到 idle，允许反复重看")
        let tab = appState.selectedTab
        XCTAssertEqual(tab?.url.lastPathComponent, AgentDemoFlow.demoFileName)
        XCTAssertEqual(tab?.content, AgentDemoFlow.tidyMarkdown(for: LocalizationManager.shared.resolved),
                       "演示结束时文档应被改写为整理稿")
    }
}
