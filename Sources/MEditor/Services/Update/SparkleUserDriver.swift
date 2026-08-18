import AppKit
import Sparkle
import SwiftUI

/// 自定义 Sparkle 用户界面驱动：替换框架默认的英文原生弹窗，
/// 用与 app 一致的 SwiftUI 面板（中文、DS 样式）承载整个更新流程。
///
/// 覆盖的阶段：权限询问 → 检查中 → 发现新版本（含更新日志）→ 下载（进度+取消）
/// → 解压 → 安装 → 待重启；以及已最新 / 出错两个终态。
@MainActor
final class SparkleUserDriver: NSObject, SPUUserDriver {

    let state = UpdatePanelState()
    private var window: NSWindow?

    // MARK: - 面板生命周期

    private func showPanel() {
        if window == nil {
            let rootView = UpdatePanelView(state: state)
            let hosting = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
        }
        relayout()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// 内容随阶段变化高度不同：按 SwiftUI 理想尺寸重排窗口（宽度固定 460）。
    private func relayout() {
        guard let window,
              let hosting = window.contentViewController as? NSHostingController<UpdatePanelView> else { return }
        let fitting = hosting.sizeThatFits(in: CGSize(width: 460, height: CGFloat.greatestFiniteMagnitude))
        let height = min(max(fitting.height, 120), 560)
        var frame = window.frame
        let delta = height - frame.height
        frame.size = NSSize(width: 460, height: height)
        frame.origin.y -= delta  // 保持顶边不动，向下长
        window.setFrame(frame, display: true, animate: true)
    }

    private func closePanel() {
        state.clearActions()
        window?.close()
        window = nil
    }

    // MARK: - SPUUserDriver

    /// 首次启动询问是否允许自动检查更新。
    func show(_ request: SPUUpdatePermissionRequest,
              reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        state.clearActions()
        state.phase = .permission
        state.primaryAction = { [weak self] in
            reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
            self?.closePanel()
        }
        state.secondaryAction = { [weak self] in
            reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
            self?.closePanel()
        }
        state.dismissAction = state.secondaryAction
        showPanel()
    }

    /// 手动「检查更新」开始。
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        state.clearActions()
        state.phase = .checking
        state.cancelAction = { [weak self] in
            cancellation()
            self?.closePanel()
        }
        state.dismissAction = state.cancelAction
        showPanel()
    }

    /// 发现新版本（手动或后台检查都会到这里）。
    func showUpdateFound(with appcastItem: SUAppcastItem,
                         state userState: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        state.clearActions()
        state.newVersion = appcastItem.displayVersionString
        state.currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        state.releaseNotesHTML = appcastItem.itemDescription
        state.phase = .found
        state.primaryAction = { reply(.install) }  // 面板继续走下载进度，不关
        state.tertiaryAction = { [weak self] in
            reply(.skip)
            self?.closePanel()
        }
        state.secondaryAction = { [weak self] in
            reply(.dismiss)
            self?.closePanel()
        }
        state.dismissAction = state.secondaryAction
        showPanel()
    }

    /// appcast 里只给了 releaseNotesURL 时，框架单独下载后从这里交付。
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        if let html = String(data: downloadData.data, encoding: .utf8) {
            state.releaseNotesHTML = html
            relayout()
        }
    }

    /// 更新日志下载失败无碍主流程，面板已有版本号信息。
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    /// 已是最新（仅手动检查会触发）。
    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        state.clearActions()
        state.phase = .notFound
        state.primaryAction = { [weak self] in
            acknowledgement()
            self?.closePanel()
        }
        state.dismissAction = state.primaryAction
        showPanel()
    }

    /// 更新流程出错。
    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        state.clearActions()
        state.errorMessage = error.localizedDescription
        state.phase = .failed
        state.primaryAction = { [weak self] in
            acknowledgement()
            self?.closePanel()
        }
        state.dismissAction = state.primaryAction
        showPanel()
    }

    /// 下载开始。
    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        state.receivedBytes = 0
        state.expectedBytes = 0
        state.phase = .downloading
        state.cancelAction = { [weak self] in
            cancellation()
            self?.closePanel()
        }
        state.dismissAction = state.cancelAction
        showPanel()
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        state.expectedBytes = expectedContentLength
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        state.receivedBytes += length
    }

    /// 下载完成，开始解压。
    func showDownloadDidStartExtractingUpdate() {
        state.phase = .extracting
        state.extractionProgress = 0
        state.cancelAction = nil
        state.dismissAction = nil
        relayout()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        state.extractionProgress = progress
    }

    /// 解压完成，随时可以安装重启。
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        state.clearActions()
        state.phase = .ready
        state.primaryAction = { reply(.install) }  // 进入安装阶段，不关
        state.secondaryAction = { [weak self] in
            reply(.dismiss)
            self?.closePanel()
        }
        state.dismissAction = state.secondaryAction
        showPanel()
    }

    /// 正在安装（应用即将或已经退出）。
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication retryTerminating: @escaping () -> Void) {
        state.clearActions()
        state.phase = .installing
        showPanel()
    }

    /// 安装完成并已重启（新版本的首启）。
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        closePanel()
        acknowledgement()
    }

    /// 框架要求收起界面（取消、后台静默完成等）。
    func dismissUpdateInstallation() {
        closePanel()
    }

    /// 要求把更新界面提到最前（如下载完成需要用户决策）。
    func showUpdateInFocus() {
        showPanel()
    }
}

// MARK: - NSWindowDelegate

extension SparkleUserDriver: NSWindowDelegate {
    /// 用户点关闭按钮：等价于「稍后/取消」，回复 Sparkle 挂起的回调后再关。
    func windowWillClose(_ notification: Notification) {
        state.dismissAction?()
        state.clearActions()
        window = nil
    }
}
