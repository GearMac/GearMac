// 文件职责：为扩展的 OAuth token 提供安全存储，按「扩展名:providerId」组成账号键读写 macOS Keychain。
// 分层：Service；仅依赖 Foundation/Security，不引入 AppKit/SwiftUI；token 以通用密码项（generic password）形式存放。
import Foundation
import Security

/// OAuth token 存储抽象：通过注入，测试脚手架可以在不接触真实 Keychain 的情况下持有 token。
protocol ExtensionOAuthTokenStore: Sendable {
    /// 按账号键读取 token，不存在时返回 nil。
    func get(account: String) -> String?
    /// 按账号键写入（或更新）token，返回是否成功。
    func set(_ value: String, account: String) -> Bool
    /// 删除指定账号键的 token，返回是否成功（本就不存在也算成功）。
    func remove(account: String) -> Bool
    /// 删除所有账号键等于 exactMatch 或以 prefix 开头的 token。
    func removeAll(prefix: String, exactMatch: String)
}

/// 基于 Keychain 的实现：所有 token 统一放在 service 为 `com.gearmac.extensions.oauth` 的通用密码项中。
struct KeychainOAuthTokenStore: ExtensionOAuthTokenStore {
    private let serviceName = "com.gearmac.extensions.oauth"

    func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// 先尝试更新已有条目；若条目不存在则新增，避免先删后写导致的数据丢失窗口。
    func set(_ value: String, account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var newQuery = query
            newQuery[kSecValueData as String] = data
            newQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            return SecItemAdd(newQuery as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    func remove(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// 枚举本 service 下全部条目，逐个比对账号键后删除匹配项（精确匹配或前缀匹配）。
    func removeAll(prefix: String, exactMatch: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let items = item as? [[String: Any]] else { return }

        for attributes in items {
            guard let account = attributes[kSecAttrAccount as String] as? String else { continue }
            if account == exactMatch || account.hasPrefix(prefix) {
                let deleteQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: serviceName,
                    kSecAttrAccount as String: account
                ]
                SecItemDelete(deleteQuery as CFDictionary)
            }
        }
    }
}

/// 扩展 OAuth token 的安全存储入口，按扩展名与 provider 组成账号键。
enum ExtensionOAuthKeychain {
    nonisolated(unsafe) static var store: ExtensionOAuthTokenStore = KeychainOAuthTokenStore()

    /// 生成账号键：有 providerId 时为 `扩展名:providerId`，否则退化为扩展名本身。
    static func accountKey(extensionName: String, providerId: String?) -> String {
        if let providerId, !providerId.isEmpty {
            return "\(extensionName):\(providerId)"
        }
        return extensionName
    }

    /// 读取指定扩展（及可选 provider）的 token JSON 字符串。
    static func getTokens(extensionName: String, providerId: String?) -> String? {
        let account = accountKey(extensionName: extensionName, providerId: providerId)
        return store.get(account: account)
    }

    /// 写入指定扩展（及可选 provider）的 token JSON 字符串。
    @discardableResult
    static func setTokens(_ jsonString: String, extensionName: String, providerId: String?) -> Bool {
        let account = accountKey(extensionName: extensionName, providerId: providerId)
        return store.set(jsonString, account: account)
    }

    /// 删除指定扩展（及可选 provider）的 token。
    @discardableResult
    static func removeTokens(extensionName: String, providerId: String?) -> Bool {
        let account = accountKey(extensionName: extensionName, providerId: providerId)
        return store.remove(account: account)
    }

    /// 删除该扩展下的全部 token：精确匹配扩展名（无 provider）以及所有 `扩展名:` 前缀项。
    static func removeAllTokens(extensionName: String) {
        store.removeAll(prefix: "\(extensionName):", exactMatch: extensionName)
    }
}
