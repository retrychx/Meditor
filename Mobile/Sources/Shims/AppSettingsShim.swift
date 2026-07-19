import Foundation

// MARK: - AppSettings 替身
//
// 共享代码 AIService.swift 的 `AIConfig.current(_:)` 与 AIModels.swift 的
// `AIAccentStyle.current(_:)` 以 AppSettings 为参数类型。macOS 端的
// Services/Core/AppSettings.swift 使用 macOS-only 的 security-scoped bookmark，
// 无法编进 iOS target；移动端设置直接走 MobileAISettings（UserDefaults），
// 这里只提供让共享代码通过类型检查的最小替身（运行时不使用）。

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
