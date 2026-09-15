import Foundation
import Security

/// Thin wrapper over the platform Keychain for a single (service, account) generic
/// password. Secrets are never written to disk or logs. Reused by any feature
/// that needs to persist a credential (AI API key, GitLab token, …).
///
/// ACL 策略：
///   不设置自定义 `SecAccess`，使用系统默认 ACL——item 只信任创建它的应用
///   （按 code signature）。此前用 `SecAccessCreate(trustedList: nil)` 构造了
///   「任意应用可读」的 ACL，任何本机进程都能静默读取 API key / 发布 token；
///   安全优先于「开发期替换二进制少弹一次授权框」的便利。
///   可访问性用 `WhenUnlockedThisDeviceOnly`：不同步到 iCloud、不进备份。
///   iOS 无 SecAccess API，Keychain 项天然按 app 隔离。
struct Keychain {
    let service: String
    let account: String

    private var base: [String: Any] {
        [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    /// 存储 `value`，替换已有 item。空字符串等同于清除。
    @discardableResult
    func save(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(base as CFDictionary)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return false }

        var add = base
        add[kSecValueData as String]      = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    func load() -> String? {
        var query = base
        query[kSecReturnData as String]  = true
        query[kSecMatchLimit as String]  = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let str  = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    func clear() {
        SecItemDelete(base as CFDictionary)
    }

    var hasValue: Bool { load() != nil }
}
