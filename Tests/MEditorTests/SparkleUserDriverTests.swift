import Sparkle
import XCTest
@testable import MEditor

/// SparkleUserDriver 的状态机测试：面板展示/关闭通过 panelPresenter 注入点拦截，
/// 不创建真实 NSWindow（测试进程没有可激活的 NSApp）。
/// 只断言状态装配与回调接线，不测 Sparkle 框架本身的调度。
@MainActor
final class SparkleUserDriverTests: XCTestCase {

    private var driver: SparkleUserDriver!
    private var panelEvents: [Bool]!   // true=展示, false=关闭

    override func setUp() {
        super.setUp()
        panelEvents = []
        driver = SparkleUserDriver()
        driver.panelPresenter = { [weak self] shown in
            self?.panelEvents.append(shown)
        }
    }

    override func tearDown() {
        driver = nil
        panelEvents = nil
        super.tearDown()
    }

    private func assertPanelShown(_ file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(panelEvents.last, true, "应请求展示面板", file: file, line: line)
    }

    private func assertPanelClosed(_ file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(panelEvents.last, false, "应请求关闭面板", file: file, line: line)
    }

    private func assertAllActionsCleared(_ file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(driver.state.primaryAction, file: file, line: line)
        XCTAssertNil(driver.state.secondaryAction, file: file, line: line)
        XCTAssertNil(driver.state.tertiaryAction, file: file, line: line)
        XCTAssertNil(driver.state.cancelAction, file: file, line: line)
        XCTAssertNil(driver.state.dismissAction, file: file, line: line)
    }

    // MARK: - 权限询问

    func testPermission_allow_repliesEnabledAndCloses() {
        var response: SUUpdatePermissionResponse?
        driver.show(SPUUpdatePermissionRequest(systemProfile: [])) { response = $0 }

        XCTAssertEqual(driver.state.phase, .permission)
        assertPanelShown()

        driver.state.primaryAction?()
        XCTAssertEqual(response?.automaticUpdateChecks, true)
        XCTAssertEqual(response?.sendSystemProfile, false, "不应回传系统画像")
        assertPanelClosed()
        assertAllActionsCleared()
    }

    func testPermission_decline_repliesDisabledAndCloses() {
        var response: SUUpdatePermissionResponse?
        driver.show(SPUUpdatePermissionRequest(systemProfile: [])) { response = $0 }

        driver.state.secondaryAction?()
        XCTAssertEqual(response?.automaticUpdateChecks, false)
        assertPanelClosed()
    }

    func testPermission_dismissAction_equalsDecline() {
        // 用户直接关窗 = 「不允许」
        var response: SUUpdatePermissionResponse?
        driver.show(SPUUpdatePermissionRequest(systemProfile: [])) { response = $0 }

        driver.state.dismissAction?()
        XCTAssertEqual(response?.automaticUpdateChecks, false)
        assertPanelClosed()
    }

    // MARK: - 手动检查

    func testUserInitiatedCheck_cancel_invokesCancellationAndCloses() {
        var cancelled = false
        driver.showUserInitiatedUpdateCheck { cancelled = true }

        XCTAssertEqual(driver.state.phase, .checking)
        XCTAssertNotNil(driver.state.cancelAction)
        assertPanelShown()

        driver.state.cancelAction?()
        XCTAssertTrue(cancelled)
        assertPanelClosed()
    }

    // MARK: - 发现新版本

    func testFound_populatesVersionAndNotes() {
        driver.applyFoundUpdate(displayVersion: "2.0", releaseNotesHTML: "<p>notes</p>") { _ in }

        XCTAssertEqual(driver.state.phase, .found)
        XCTAssertEqual(driver.state.newVersion, "2.0")
        XCTAssertEqual(driver.state.releaseNotesHTML, "<p>notes</p>")
        XCTAssertNotNil(driver.state.primaryAction)
        XCTAssertNotNil(driver.state.secondaryAction)
        XCTAssertNotNil(driver.state.tertiaryAction)
        assertPanelShown()
    }

    func testFound_install_repliesInstallAndKeepsPanelOpen() {
        var choice: SPUUserUpdateChoice?
        driver.applyFoundUpdate(displayVersion: "2.0", releaseNotesHTML: nil) { choice = $0 }

        driver.state.primaryAction?()
        XCTAssertEqual(choice, .install)
        XCTAssertNotEqual(panelEvents.last, false, "选择安装后面板保持打开，继续走下载进度")
    }

    func testFound_skip_repliesSkipAndCloses() {
        var choice: SPUUserUpdateChoice?
        driver.applyFoundUpdate(displayVersion: "2.0", releaseNotesHTML: nil) { choice = $0 }

        driver.state.tertiaryAction?()
        XCTAssertEqual(choice, .skip)
        assertPanelClosed()
    }

    func testFound_later_repliesDismissAndCloses() {
        var choice: SPUUserUpdateChoice?
        driver.applyFoundUpdate(displayVersion: "2.0", releaseNotesHTML: nil) { choice = $0 }

        driver.state.secondaryAction?()
        XCTAssertEqual(choice, .dismiss)
        assertPanelClosed()
    }

    // MARK: - 已是最新 / 出错

    func testNotFound_acknowledgeCloses() {
        var acked = false
        driver.showUpdateNotFoundWithError(NSError(domain: "test", code: 1)) { acked = true }

        XCTAssertEqual(driver.state.phase, .notFound)
        assertPanelShown()

        driver.state.primaryAction?()
        XCTAssertTrue(acked)
        assertPanelClosed()
    }

    func testUpdaterError_showsMessageAndAckCloses() {
        struct Boom: Error, LocalizedError { var errorDescription: String? { "boom-detail" } }
        var acked = false
        driver.showUpdaterError(Boom()) { acked = true }

        XCTAssertEqual(driver.state.phase, .failed)
        XCTAssertEqual(driver.state.errorMessage, "boom-detail")
        assertPanelShown()

        driver.state.primaryAction?()
        XCTAssertTrue(acked)
        assertPanelClosed()
    }

    // MARK: - 下载 / 解压

    func testDownload_progressAccumulates() {
        var cancelled = false
        driver.showDownloadInitiated { cancelled = true }

        XCTAssertEqual(driver.state.phase, .downloading)
        XCTAssertEqual(driver.state.receivedBytes, 0)
        XCTAssertEqual(driver.state.expectedBytes, 0)
        XCTAssertNotNil(driver.state.cancelAction, "下载中应可取消")

        driver.showDownloadDidReceiveExpectedContentLength(100)
        driver.showDownloadDidReceiveData(ofLength: 30)
        driver.showDownloadDidReceiveData(ofLength: 20)
        XCTAssertEqual(driver.state.expectedBytes, 100)
        XCTAssertEqual(driver.state.receivedBytes, 50, "收到的字节应累计")

        driver.state.cancelAction?()
        XCTAssertTrue(cancelled)
        assertPanelClosed()
    }

    func testExtracting_clearsCancelAndDismiss() {
        driver.showDownloadInitiated {}
        XCTAssertNotNil(driver.state.cancelAction)

        driver.showDownloadDidStartExtractingUpdate()
        XCTAssertEqual(driver.state.phase, .extracting)
        XCTAssertEqual(driver.state.extractionProgress, 0)
        XCTAssertNil(driver.state.cancelAction, "解压不可取消")
        XCTAssertNil(driver.state.dismissAction, "解压阶段关窗不应触发回调")

        driver.showExtractionReceivedProgress(0.75)
        XCTAssertEqual(driver.state.extractionProgress, 0.75, accuracy: 0.0001)
    }

    // MARK: - 就绪 / 安装

    func testReady_installKeepsPanelOpen_dismissCloses() {
        var choice: SPUUserUpdateChoice?
        driver.showReady { choice = $0 }

        XCTAssertEqual(driver.state.phase, .ready)
        assertPanelShown()

        driver.state.primaryAction?()
        XCTAssertEqual(choice, .install)
        XCTAssertNotEqual(panelEvents.last, false, "立即重启后面板保持打开进入安装阶段")

        driver.showReady { choice = $0 }
        driver.state.secondaryAction?()
        XCTAssertEqual(choice, .dismiss)
        assertPanelClosed()
    }

    func testInstalling_clearsAllActions() {
        driver.showUserInitiatedUpdateCheck {}
        XCTAssertNotNil(driver.state.cancelAction)

        driver.showInstallingUpdate(withApplicationTerminated: true) {}
        XCTAssertEqual(driver.state.phase, .installing)
        assertAllActionsCleared()
    }

    func testInstalledAndRelaunched_acknowledgesAndCloses() {
        var acked = false
        driver.showUpdateInstalledAndRelaunched(true) { acked = true }
        XCTAssertTrue(acked)
        assertPanelClosed()
        assertAllActionsCleared()
    }

    func testDismissUpdateInstallation_clearsActionsAndCloses() {
        driver.showUserInitiatedUpdateCheck {}
        driver.dismissUpdateInstallation()
        assertPanelClosed()
        assertAllActionsCleared()
    }

    // MARK: - 完整状态机迁移

    func testHappyPath_phaseSequence() {
        var phases: [UpdatePanelState.Phase] = []
        let record = { phases.append(self.driver.state.phase) }

        driver.showUserInitiatedUpdateCheck {}; record()
        driver.applyFoundUpdate(displayVersion: "2.0", releaseNotesHTML: nil) { _ in }; record()
        driver.showDownloadInitiated {}; record()
        driver.showDownloadDidStartExtractingUpdate(); record()
        driver.showReady { _ in }; record()
        driver.showInstallingUpdate(withApplicationTerminated: true) {}; record()

        XCTAssertEqual(phases, [.checking, .found, .downloading, .extracting, .ready, .installing])
    }
}
