import Foundation
import OSLog
import Sparkle

/// 自动更新（Sparkle 2）。feed 与安装包托管在 Cloudflare：
///   - appcast: https://meditor-app.863129776.workers.dev/update/appcast.xml
///   - 安装包:  https://meditor-app.863129776.workers.dev/update/<file>.zip
/// 发版流水线见 .github/workflows/release.yml（打 tag 自动签名、上传、更新 appcast）。
///
/// UI 走自定义的 SparkleUserDriver（中文 SwiftUI 面板），
/// 不用 SPUStandardUpdaterController 的默认英文弹窗。
@MainActor
final class UpdateController {
    static let shared = UpdateController()

    private let log = Logger(subsystem: "com.meditor.app", category: "update")
    private let userDriver: SparkleUserDriver
    private let updater: SPUUpdater

    private init() {
        userDriver = SparkleUserDriver()
        updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: userDriver,
            delegate: nil
        )
        // 启动即按 Sparkle 默认周期（24h）自动静默检查；
        // 设置里的「检查更新」按钮走手动 checkForUpdates（有结果会弹面板）
        do {
            try updater.start()
        } catch {
            // 常见原因：未签名/开发环境。不影响手动检查之外的任何功能。
            log.error("Sparkle updater 启动失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 手动检查更新（设置-通用-关于里的按钮）。
    func checkForUpdates() {
        updater.checkForUpdates()
    }

    /// 「自动检查更新」开关绑定。
    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    /// 当前应用版本号（关于区展示）。
    var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return build == short ? short : "\(short) (\(build))"
    }
}
