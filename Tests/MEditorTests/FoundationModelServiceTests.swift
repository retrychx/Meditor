import XCTest
@testable import MEditor

/// 端侧智能（FoundationModelService）测试。
/// 业务层只依赖 OnDeviceModelProviding 协议与 OnDeviceModelAvailability 抽象，
/// 全部用 mock provider 覆盖，不触达真机模型。
@MainActor
final class FoundationModelServiceTests: XCTestCase {

    // MARK: - Mock

    private final class MockProvider: OnDeviceModelProviding, @unchecked Sendable {
        var availability: OnDeviceModelAvailability = .available
        var result: Result<String, Error> = .success("")
        var delayNanos: UInt64 = 0
        private(set) var callCount = 0
        private(set) var lastInstructions: String?
        private(set) var lastPrompt: String?

        struct MockError: Error {}

        func generate(instructions: String, prompt: String) async throws -> String {
            callCount += 1
            lastInstructions = instructions
            lastPrompt = prompt
            if delayNanos > 0 {
                try await Task.sleep(nanoseconds: delayNanos)
            }
            return try result.get()
        }
    }

    private func makeService(_ provider: MockProvider, timeout: TimeInterval = 3) -> FoundationModelService {
        FoundationModelService(provider: provider, generateTimeout: timeout)
    }

    // MARK: - availability 抽象的状态映射

    func testAvailability_available_passesThrough() {
        let mock = MockProvider()
        mock.availability = .available
        XCTAssertTrue(makeService(mock).availability.isAvailable)
        XCTAssertEqual(makeService(mock).availability, .available)
    }

    func testAvailability_unavailableReasons_passThrough() {
        let mock = MockProvider()
        let reasons: [OnDeviceModelAvailability.UnavailabilityReason] = [
            .unsupportedOS, .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady, .unknown
        ]
        for reason in reasons {
            mock.availability = .unavailable(reason)
            let service = makeService(mock)
            XCTAssertFalse(service.availability.isAvailable, "\(reason) should be unavailable")
            XCTAssertEqual(service.availability, .unavailable(reason))
        }
    }

    func testAvailability_noProvider_reportsUnsupportedOS() {
        let service = FoundationModelService(provider: nil)
        XCTAssertEqual(service.availability, .unavailable(.unsupportedOS))
    }

    func testStatusLabelKeys_areRegisteredInLocalizationTable() {
        // 每个状态（含各不可用原因）都必须有对应本地化 key，否则设置页显示原始 key
        let states: [OnDeviceModelAvailability] = [
            .available,
            .unavailable(.unsupportedOS),
            .unavailable(.deviceNotEligible),
            .unavailable(.appleIntelligenceNotEnabled),
            .unavailable(.modelNotReady),
            .unavailable(.unknown)
        ]
        for state in states {
            let key = state.statusLabelKey
            XCTAssertNotNil(LocalizationManager.table[key], "missing localization key: \(key)")
        }
    }

    func testGenerate_unavailable_throwsWithoutCallingProvider() async {
        let mock = MockProvider()
        mock.availability = .unavailable(.appleIntelligenceNotEnabled)
        do {
            _ = try await makeService(mock).generate(instructions: "i", prompt: "p")
            XCTFail("expected unavailable error")
        } catch {
            XCTAssertEqual(mock.callCount, 0, "unavailable 时不得触达底层模型")
        }
    }

    // MARK: - 粘贴清理：成功路径

    func testCleanup_modelReturnsCleaned_usesCleaned() async {
        let mock = MockProvider()
        mock.result = .success("# Clean\n\nBody without ads")
        let raw = "# Dirty\n\nBody\n\nClick to follow us!"
        let result = await makeService(mock).cleanPastedMarkdown(raw, enabled: true)
        XCTAssertEqual(result, "# Clean\n\nBody without ads")
        XCTAssertEqual(mock.callCount, 1)
    }

    func testCleanup_outputIsTrimmed() async {
        let mock = MockProvider()
        mock.result = .success("\n\n  # Clean  \n\n")
        let result = await makeService(mock).cleanPastedMarkdown("raw", enabled: true)
        XCTAssertEqual(result, "# Clean")
    }

    // MARK: - 粘贴清理：回退路径

    func testCleanup_settingDisabled_skipsModelAndReturnsOriginal() async {
        let mock = MockProvider()
        mock.result = .success("cleaned")
        let result = await makeService(mock).cleanPastedMarkdown("raw", enabled: false)
        XCTAssertEqual(result, "raw")
        XCTAssertEqual(mock.callCount, 0, "设置关闭时不得触达模型")
    }

    func testCleanup_unavailable_skipsModelAndReturnsOriginal() async {
        let mock = MockProvider()
        mock.availability = .unavailable(.deviceNotEligible)
        mock.result = .success("cleaned")
        let result = await makeService(mock).cleanPastedMarkdown("raw", enabled: true)
        XCTAssertEqual(result, "raw")
        XCTAssertEqual(mock.callCount, 0)
    }

    func testCleanup_modelThrows_fallsBackToOriginal() async {
        let mock = MockProvider()
        mock.result = .failure(MockProvider.MockError())
        let result = await makeService(mock).cleanPastedMarkdown("raw", enabled: true)
        XCTAssertEqual(result, "raw")
    }

    func testCleanup_modelTimesOut_fallsBackToOriginal() async {
        let mock = MockProvider()
        mock.result = .success("cleaned")
        mock.delayNanos = 300_000_000   // 300ms，超过注入的 50ms 超时
        let result = await makeService(mock, timeout: 0.05).cleanPastedMarkdown("raw", enabled: true)
        XCTAssertEqual(result, "raw", "超时应静默回退原文")
    }

    func testCleanup_modelReturnsEmpty_fallsBackToOriginal() async {
        let mock = MockProvider()
        mock.result = .success("")
        let result = await makeService(mock).cleanPastedMarkdown("raw", enabled: true)
        XCTAssertEqual(result, "raw", "空输出应静默回退原文")
    }

    func testCleanup_modelReturnsWhitespaceOnly_fallsBackToOriginal() async {
        let mock = MockProvider()
        mock.result = .success("  \n\n  ")
        let result = await makeService(mock).cleanPastedMarkdown("raw", enabled: true)
        XCTAssertEqual(result, "raw", "纯空白输出应静默回退原文")
    }

    // MARK: - 提示词组装

    func testCleanupInstructions_containNoSummarizeNoRewriteConstraints() {
        let instructions = FoundationModelService.cleanupInstructions
        XCTAssertTrue(instructions.contains("Do not summarize"),
                      "instructions must forbid summarizing")
        XCTAssertTrue(instructions.contains("Do not rewrite"),
                      "instructions must forbid rewriting")
        XCTAssertTrue(instructions.contains("Markdown"),
                      "instructions must require keeping Markdown structure")
        XCTAssertTrue(instructions.contains("Output only the cleaned Markdown"),
                      "instructions must demand bare output without commentary")
    }

    func testCleanupPrompt_wrapsContentInDelimiters() {
        let prompt = FoundationModelService.cleanupPrompt(for: "hello **world**")
        XCTAssertTrue(prompt.contains("<content>\nhello **world**\n</content>"),
                      "prompt must wrap the pasted content in delimiters")
        XCTAssertFalse(prompt.contains("总结"), "prompt should not depend on Chinese wording")
    }

    func testCleanup_promptAndInstructions_reachTheModel() async {
        let mock = MockProvider()
        mock.result = .success("cleaned")
        _ = await makeService(mock).cleanPastedMarkdown("some pasted body", enabled: true)
        XCTAssertEqual(mock.lastInstructions, FoundationModelService.cleanupInstructions)
        XCTAssertEqual(mock.lastPrompt, FoundationModelService.cleanupPrompt(for: "some pasted body"))
    }
}
