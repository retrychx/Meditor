import Foundation
import Observation

/// Stores the user's current preview theme choice and persists it across launches.
///
/// Wrapped as `@Observable` so SwiftUI views can react automatically to changes.
@Observable
final class PreviewThemeStore: PreviewThemeStoreProtocol {
    private static let userDefaultsKey = "MEditor.previewTheme"
    private let userDefaults: UserDefaults

    /// The theme currently in use. Setter persists the value to UserDefaults.
    var current: PreviewTheme {
        didSet {
            userDefaults.set(current.rawValue, forKey: Self.userDefaultsKey)
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let raw = userDefaults.string(forKey: Self.userDefaultsKey),
           let theme = PreviewTheme(rawValue: raw) {
            self.current = theme
        } else {
            self.current = .github
        }
    }
}
