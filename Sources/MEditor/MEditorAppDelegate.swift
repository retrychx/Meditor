import AppKit
import CoreSpotlight
import Foundation

/// AppKit 层入口适配（Spotlight 点击结果打开等系统回调）。
///
/// SwiftUI App 生命周期本身不暴露 NSApplicationDelegate，这里用
/// `@NSApplicationDelegateAdaptor` 挂接。AppState 由 MEditorApp 在首个窗口
/// onAppear 时注入；冷启动点击 Spotlight 结果时 AppState 可能尚未注入，
/// 先入 pendingOpenURLs，待注入后由 consumePendingOpens() 补开。
@MainActor
final class MEditorAppDelegate: NSObject, NSApplicationDelegate {

    /// Spotlight 结果点击的 NSUserActivity type 字符串值。macOS SDK 未导出
    /// CSSearchableItemActionIdentifier 常量（iOS only），这里用其字面值，
    /// 与 Info.plist 的 NSUserActivityTypes 声明保持一致。
    static let spotlightActivityType = "com.apple.corespotlightitem"

    weak var appState: AppState?
    private var pendingOpenURLs: [URL] = []

    /// Spotlight 结果点击：activityType = com.apple.corespotlightitem，
    /// userInfo[CSSearchableItemActivityIdentifier] 携带索引时的 uniqueIdentifier（文件绝对路径）。
    func application(
        _ application: NSApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
    ) -> Bool {
        guard userActivity.activityType == Self.spotlightActivityType,
              let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              !identifier.isEmpty else { return false }
        let url = URL(fileURLWithPath: identifier)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        openOrEnqueue(url)
        return true
    }

    /// AppState 注入前的 Spotlight 打开请求在此补开（冷启动竞态）。
    /// 必须在 restoreSession 之后调用，避免与恢复的会话互相覆盖。
    func consumePendingOpens() {
        guard appState != nil, !pendingOpenURLs.isEmpty else { return }
        let urls = pendingOpenURLs
        pendingOpenURLs = []
        urls.forEach { openOrEnqueue($0) }
    }

    /// AppIntent（打开文档）与 Spotlight 共用的打开入口。
    func openOrEnqueue(_ url: URL) {
        guard let appState else {
            pendingOpenURLs.append(url)
            return
        }
        if let root = appState.rootURL {
            if appState.fileTreeManager.isSameOrDescendant(url, of: root) {
                appState.openFile(FileItem(url: url, isDirectory: false))
            } else {
                // 属于另一个工作区：不打断当前工作区，按散文件打开
                appState.openLooseFile(url)
            }
        } else {
            // 无工作区：先把父目录作为工作区打开，让侧边栏有上下文（与 handleOpenURL 一致）
            appState.openFolder(url.deletingLastPathComponent())
            appState.openFile(FileItem(url: url, isDirectory: false))
        }
    }
}
