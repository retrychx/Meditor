import Foundation
import Observation

/// 移动端 AI 配置：provider / baseURL / model 存 UserDefaults，启动时构造 AIConfig。
/// API Key 存 Keychain（复用 macOS 的共享 Keychain.swift，Security framework）；
/// 旧版明文存 UserDefaults 的 key 在首次启动时迁移进 Keychain 并删除明文。
@MainActor
@Observable
final class MobileAISettings {

    private enum Key {
        static let provider = "meditor.mobile.aiProvider"
        static let baseURL  = "meditor.mobile.aiBaseURL"
        static let model    = "meditor.mobile.aiModel"
        /// 旧版明文存储 key，仅用于一次性迁移（迁移后删除）。
        static let legacyApiKey = "meditor.mobile.aiApiKey"
    }

    private static let keychain = Keychain(service: "com.meditor.mobile.ai", account: "api-key")

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
        didSet { Self.keychain.save(apiKey) }   // 空字符串等同清除
    }

    init() {
        let d = UserDefaults.standard
        provider = AIProviderKind(rawValue: d.string(forKey: Key.provider) ?? "") ?? .disabled
        baseURL  = d.string(forKey: Key.baseURL) ?? "https://api.openai.com/v1"
        model    = d.string(forKey: Key.model) ?? "gpt-4o-mini"
        // 迁移：旧版明文存 UserDefaults 的 API Key 搬进 Keychain 并删除明文。
        if let legacy = d.string(forKey: Key.legacyApiKey) {
            if !legacy.isEmpty { Self.keychain.save(legacy) }
            d.removeObject(forKey: Key.legacyApiKey)
        }
        apiKey = Self.keychain.load() ?? ""
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
