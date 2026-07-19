import Foundation

// MARK: - AppSettings 替身
//
// 共享代码 AIService.swift 的 `AIConfig.current(_:)` 与 AIModels.swift 的
// `AIAccentStyle.current(_:)` 以 AppSettings 为参数类型。macOS 端的
// Services/Core/AppSettings.swift 使用 macOS-only 的 security-scoped bookmark，
// 无法编进 iOS target；移动端设置直接走 MobileAISettings（UserDefaults），
// 这里只提供让共享代码通过类型检查的最小替身（运行时不使用）。
//
// ⚠️ 隐患：本替身的所有属性都是**假默认值**。共享代码里任何新读 AppSettings
// 的路径，在 iOS 上会静默拿到这些假值（provider=disabled、model="" 等），
// 不会报错、不会崩溃，只会表现为"AI 功能莫名不工作"。
//
// 当前 iOS 编译路径上命中本替身的清单（2026-07 盘点，改动共享代码后请复核）：
//   - Services/AI/AIService.swift   `AIConfig.current(_:)` —— 仅函数签名引用类型；
//     iOS 实际调用方是 Mobile/Sources/Agent/MobileAISettings.swift 的 makeConfig()，
//     不会调用 AIConfig.current。
//   - Models/AIModels.swift         `AIAccentStyle.current(_:)` —— 仅函数签名引用类型；
//     iOS 端无调用方（主题色走 MobileTheme / PlatformShims）。
// 其余 AppSettings.shared 使用点（AppState、SettingsView、PreviewPanel 等）
// 均位于 macOS-only 文件，不在 iOS target。
//
// 新增共享代码时的注意事项：
//   1. 共享文件（pbxproj Shared 组里的那批）里**不要**直接读 AppSettings.shared；
//      需要配置时，把值作为参数传进来，由两端各自的平台壳注入
//      （macOS: AppSettings.shared，iOS: MobileAISettings）。
//   2. 若确实新增了对 AppSettings 的引用，先检查该文件是否在 iOS 编译列表，
//      在的话必须同步评估：iOS 路径拿到的将是本替身的假默认值。
//   3. 新增引用后，把命中点追加到上面的清单里。

#if os(iOS)
// 断言性说明（非代码）：在 iOS 上，`AppSettings.shared` 解析到本替身。
// 如果你在 iOS 运行时真的用到了它读配置——那几乎一定是 bug：
// 请改用 MobileAISettings，或把配置做成参数从平台壳注入。
#endif

@MainActor
final class AppSettings {
    static let shared = AppSettings()

    var aiProvider: String = "disabled"
    var aiBaseURL: String = ""
    var aiModel: String = ""
    var aiCLIPath: String = ""
    var aiCLIModel: String = ""
    var aiAgentModel: String = ""
    var aiInlineModel: String = ""
    var aiRequestTimeout: TimeInterval = 300
    var aiAccentStyle: String = "system"

    private init() {}
}
