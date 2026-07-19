import Foundation
import Observation

/// 移动端 AI 配置：直接存 UserDefaults，启动时构造 AIConfig。
/// 不使用 macOS 的 AppSettings / Keychain。
@MainActor
@Observable
final class MobileAISettings {

    private enum Key {
        static let provider = "meditor.mobile.aiProvider"
        static let baseURL  = "meditor.mobile.aiBaseURL"
        static let model    = "meditor.mobile.aiModel"
        static let apiKey   = "meditor.mobile.aiApiKey"
    }

    var provider: AIProviderKind {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: Key.provider) }
    }
    var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: Key.baseURL) }
    }
    var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Key.model) }
    }
    var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: Key.apiKey) }
    }

    init() {
        let d = UserDefaults.standard
        provider = AIProviderKind(rawValue: d.string(forKey: Key.provider) ?? "") ?? .disabled
        baseURL  = d.string(forKey: Key.baseURL) ?? "https://api.openai.com/v1"
        model    = d.string(forKey: Key.model) ?? "gpt-4o-mini"
        apiKey   = d.string(forKey: Key.apiKey) ?? ""
    }

    /// 选中预设：自动填 provider / baseURL，并给出一个默认模型。
    func applyPreset(_ preset: AIProviderPreset) {
        provider = preset.kind
        baseURL  = preset.baseURL
        if let first = preset.models.first { model = first }
    }

    /// 当前选中的预设（baseURL 匹配则视为该预设）。
    var matchedPreset: AIProviderPreset? { AIPresets.match(baseURL) }

    /// 构造共享代码使用的 AIConfig。
    func makeConfig() -> AIConfig {
        AIConfig(
            kind: provider,
            baseURL: baseURL.trimmingCharacters(in: .whitespaces),
            model: model.trimmingCharacters(in: .whitespaces),
            cliPath: "",
            cliModel: "",
            apiKey: apiKey.trimmingCharacters(in: .whitespaces),
            requestTimeoutSeconds: 300
        )
    }
}
