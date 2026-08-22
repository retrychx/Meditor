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
        XCTAssertTrue(content.contains("周会"), "示例内容应是一篇会议记录")
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
}
