// 文件职责：把密钥保存到登录钥匙串的 generic password 条目中，按调用方命名的 scope 与账号读写。
// 分层：Service；Sendable 值类型，不依赖 AppKit/SwiftUI。
import Foundation
import Security

/// 登录钥匙串中的 generic password，每个账号一条，归在调用方命名的 scope 下。
struct KeychainSecretStore: Sendable {
    /// 钥匙串读写可能抛出的错误。
    enum StoreError: Error {
        case invalidEncoding
        case keychain(OSStatus)
    }

    private let service: String

    /// 应用存储使用的全部 scope，集中在此列出，便于一览整个钥匙串访问面。
    static let aiAPIKeys = KeychainSecretStore(scope: "ai-api-keys")
    static let mcpSecrets = KeychainSecretStore(scope: "mcp-secrets")
    static let installedAIEnvironment = KeychainSecretStore(scope: "installed-ai-environment")

    /// 用 bundle id 与 scope 拼出钥匙串 service 名，保证各渠道互不干扰。
    init(scope: String, bundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        service = "\(bundleIdentifier ?? "com.gearmac.app").\(scope)"
    }

    /// 读取指定账号的密钥，不存在时返回 nil。
    func secret(for account: UUID) throws -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            query(for: account, returningData: true) as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
        guard let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
            throw StoreError.invalidEncoding
        }
        return secret
    }

    /// 只做存在性检查，不带上 `kSecReturn*`，因此不会实体化任何密钥字节。
    func hasSecret(for account: UUID) throws -> Bool {
        let status = SecItemCopyMatching(
            query(for: account, returningData: false) as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
        return true
    }

    /// 写入指定账号的密钥，已存在则更新，否则新增。
    func setSecret(_ secret: String, for account: UUID) throws {
        guard let data = secret.data(using: .utf8) else { throw StoreError.invalidEncoding }
        let lookup = query(for: account, returningData: false)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(lookup as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var addition = lookup
            addition[kSecValueData as String] = data
            let addStatus = SecItemAdd(addition as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw StoreError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw StoreError.keychain(status)
        }
    }

    /// 删除指定账号的密钥，不存在时视为成功。
    func removeSecret(for account: UUID) throws {
        let status = SecItemDelete(query(for: account, returningData: false) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.keychain(status)
        }
    }

    /// 构造钥匙串查询；`returningData` 为 true 时要求返回数据且只匹配一条。
    private func query(for account: UUID, returningData: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.uuidString
        ]
        if returningData {
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        return query
    }
}
