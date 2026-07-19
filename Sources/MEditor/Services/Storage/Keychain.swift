import Foundation
import Security

/// Thin wrapper over the platform Keychain for a single (service, account) generic
/// password. Secrets are never written to disk or logs. Reused by any feature
/// that needs to persist a credential (AI API key, GitLab token, …).
///
/// ACL 策略（仅 macOS）：
///   存储时使用 SecAccessCreate(trustedList: nil)，即"允许任意应用读取"。
///   对非沙盒 macOS app 这是标准做法——避免每次替换二进制（开发部署/更新）
///   时因 code signature 变化导致 Keychain 弹出授权窗口。
///   iOS 无 SecAccess API：Keychain 项天然按 app 隔离，直接用普通
///   SecItemAdd / SecItemCopyMatching / SecItemUpdate / SecItemDelete 即可。
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

    #if os(macOS)
    /// 构造一个"允许所有应用访问"的 SecAccess 对象。
    /// trustedList = nil → 任意程序无需授权即可访问该 item。
    /// 这样 code signature 变化（开发期替换二进制）不会触发权限弹窗。
    private func makeUnrestrictedAccess() -> SecAccess? {
        var access: SecAccess?
        let desc = "\(service)/\(account)" as CFString
        let status = SecAccessCreate(desc, nil, &access)
        guard status == errSecSuccess else { return nil }
        return access
    }
    #endif

    /// 存储 `value`，替换已有 item。空字符串等同于清除。
    @discardableResult
    func save(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(base as CFDictionary)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return false }

        var add = base
        add[kSecValueData as String]      = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        #if os(macOS)
        // 绑定宽松 ACL：任意 app 可读，不依赖 code signature
        if let access = makeUnrestrictedAccess() {
            add[kSecAttrAccess as String] = access
        }
        #endif
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
