import SwiftUI

/// 外观模式：跟随系统 / 浅色（纸）/ 深色（墨夜）。
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "浅色"
        case .dark:   return "深色"
        }
    }

    /// nil = 不覆盖，跟随系统。
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// 全局外观设置：UserDefaults 持久化，App 层注入 environment，
/// MEditorMobileApp 据此设置 .preferredColorScheme。
@Observable
final class AppAppearance {
    private static let defaultsKey = "appearanceMode"

    var mode: AppearanceMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.defaultsKey) }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? ""
        mode = AppearanceMode(rawValue: raw) ?? .system
    }
}
