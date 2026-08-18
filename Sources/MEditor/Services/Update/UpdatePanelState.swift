import SwiftUI

/// 更新面板状态：SparkleUserDriver 写，UpdatePanelView 读。
/// 所有字段只在主线程访问（driver 协议本身是 UI actor 隔离的）。
@MainActor @Observable
final class UpdatePanelState {
    enum Phase {
        case checking       // 手动检查中
        case permission     // 首次启动询问自动检查
        case found          // 发现新版本
        case downloading    // 下载中
        case extracting     // 解压中
        case installing     // 安装中
        case ready          // 就绪，待重启
        case notFound       // 已是最新
        case failed         // 出错
    }

    var phase: Phase = .checking

    // found
    var newVersion: String = ""
    var currentVersion: String = ""
    var releaseNotesHTML: String?

    // downloading
    var receivedBytes: UInt64 = 0
    var expectedBytes: UInt64 = 0

    // extracting
    var extractionProgress: Double = 0

    // failed
    var errorMessage: String = ""

    // 面板按钮回调（由 driver 按 phase 装配；均为一次性，触发后由 driver 置空）
    var primaryAction: (() -> Void)?    // 主按钮：立即更新 / 立即重启 / 允许 / 好
    var secondaryAction: (() -> Void)?  // 次按钮：稍后 / 不允许
    var tertiaryAction: (() -> Void)?   // 第三按钮：跳过此版本
    var cancelAction: (() -> Void)?     // 检查/下载中的取消
    /// 用户直接关窗时的兜底（等价于「稍后」），由 driver 装配
    var dismissAction: (() -> Void)?

    func clearActions() {
        primaryAction = nil
        secondaryAction = nil
        tertiaryAction = nil
        cancelAction = nil
        dismissAction = nil
    }
}
