// 文件职责：把已安装 CLI 的环境变量存储实现为 Keychain，并为每种工具绑定固定的账号 UUID。
// 分层：Service；读写均以 JSON 落 Keychain，读取失败抛错、内容损坏则当作空。
import Foundation

/// 基于 Keychain 的环境变量存储实现：一个工具一个条目，值为 JSON。
extension InstalledAIEnvironmentStore {
    /// 每个工具一个 Keychain 条目，内容为 JSON；读取失败会抛错，内容损坏则读作空。
    static let keychain = InstalledAIEnvironmentStore(
        values: { kind in
            guard
                let stored = try KeychainSecretStore.installedAIEnvironment.secret(
                    for: kind.keychainAccount)
            else { return [:] }
            let values = try? JSONDecoder().decode([String: String].self, from: Data(stored.utf8))
            return values ?? [:]
        },
        save: { values, kind in
            guard !values.isEmpty else {
                try KeychainSecretStore.installedAIEnvironment.removeSecret(
                    for: kind.keychainAccount)
                return
            }
            let data = try JSONEncoder().encode(values)
            guard let encoded = String(bytes: data, encoding: .utf8) else {
                throw KeychainSecretStore.StoreError.invalidEncoding
            }
            try KeychainSecretStore.installedAIEnvironment.setSecret(
                encoded, for: kind.keychainAccount)
        })
}

extension InstalledAIKind {
    /// Keychain 以 UUID 命名条目，因此每种工具都有一个永不变化的标识。
    fileprivate var keychainAccount: UUID {
        let value =
            switch self {
            case .codex: "559A2B35-A0EE-45DF-8E97-A87052450350"
            case .claude: "06C43DBE-F304-4E64-BBC5-F4A2AB00264B"
            case .grok: "83C70D38-66BE-4D64-8F1F-BC54FBF83E6B"
            case .openCode: "AF4DC1E6-7D9C-4C65-B278-CDB141C89DD3"
            case .cursor: "76B444D9-4617-45C8-A3E1-71A977C49D8D"
            }
        return UUID(uuidString: value) ?? UUID()
    }
}
