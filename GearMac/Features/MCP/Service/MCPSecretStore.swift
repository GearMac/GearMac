// 文件职责：把每个 MCP 服务器的敏感凭证（头值、环境变量、OAuth 凭证）编码后存入 Keychain。
// 分层：Service；值类型 + Keychain 存储，不得把明文写入 UserDefaults。
import Foundation

/// 单个服务器的凭证集合：每服务器一个 Keychain 条目，存放 UserDefaults 不能保存的内容。
struct MCPSecretStore: Sendable {
    /// 序列化到 Keychain 的凭证内容。
    struct Secrets: Codable, Equatable, Sendable {
        var headerValue: String
        var environment: [String: String]
        var oauth: MCPOAuth.Credentials?

        init(headerValue: String = "", environment: [String: String] = [:]) {
            self.headerValue = headerValue
            self.environment = environment
        }

        /// 判定凭证是否为空，用于决定是否删除 Keychain 条目。
        var isEmpty: Bool { headerValue.isEmpty && environment.isEmpty && oauth == nil }
    }

    private let keychain: KeychainSecretStore

    init(keychain: KeychainSecretStore = .mcpSecrets) {
        self.keychain = keychain
    }

    /// 读取失败时视为无凭证：缺少 secret 的服务器会在连接时报错，而不是在这里。
    func secrets(for serverID: UUID) -> Secrets {
        guard let stored = try? keychain.secret(for: serverID),
            let secrets = try? JSONDecoder().decode(Secrets.self, from: Data(stored.utf8))
        else { return Secrets() }
        return secrets
    }

    /// 保存凭证；为空时改为删除对应 Keychain 条目。
    func save(_ secrets: Secrets, for serverID: UUID) throws {
        guard !secrets.isEmpty else {
            try keychain.removeSecret(for: serverID)
            return
        }
        let data = try JSONEncoder().encode(secrets)
        guard let encoded = String(bytes: data, encoding: .utf8) else {
            throw KeychainSecretStore.StoreError.invalidEncoding
        }
        try keychain.setSecret(encoded, for: serverID)
    }

    /// 删除指定服务器的 Keychain 凭证。
    func remove(for serverID: UUID) throws {
        try keychain.removeSecret(for: serverID)
    }
}
