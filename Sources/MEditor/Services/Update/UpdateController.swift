import Foundation
import Sparkle

/// 自动更新（Sparkle 2）。feed 与安装包托管在 Cloudflare：
///   - appcast: https://meditor-app.863129776.workers.dev/update/appcast.xml
///   - 安装包:  https://meditor-app.863129776.workers.dev/update/<file>.zip
/// 发版流水线见 .github/workflows/release.yml（打 tag 自动签名、上传、更新 appcast）。
@MainActor
final class UpdateController {
    static let shared = UpdateController()

    private let controller: SPUStandardUpdaterController

    private init() {
        // startingUpdater: true —— 启动即按 Sparkle 默认周期（24h）自动静默检查；
        // 设置里的「检查更新」按钮走手动 checkForUpdates（有结果会弹窗）
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// 手动检查更新（设置-通用-关于里的按钮）。
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// 「自动检查更新」开关绑定。
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// 当前应用版本号（关于区展示）。
    var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return build == short ? short : "\(short) (\(build))"
    }
}
