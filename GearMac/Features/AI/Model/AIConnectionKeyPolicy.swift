// 文件职责：保存 AI 连接时如何处置其 Keychain 中 API Key 的判定策略。
// 分层：Model；纯函数决策，不直接读写 Keychain，不得 import AppKit/SwiftUI。
import Foundation

/// 保存连接时对其 Keychain 密钥做什么：密钥绝不会跟随被改写的端点迁移。
enum AIConnectionKeyPolicy {
    /// 对已存密钥的处置结果：写入新值、删除已存值、保持原样，或拒绝保存并给出原因。
    enum Outcome: Equatable {
        case store(String)
        case removeStored
        case keep
        case reject(String)
    }

    /// 依据用户输入的密钥、待保存连接、已保存连接以及是否存在已存密钥，决定密钥的最终处置。
    static func resolve(
        enteredKey: String, connection: AIConnection, saved: AIConnection?, hasStoredKey: Bool
    ) -> Outcome {
        let key = enteredKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty { return .store(key) }
        let isLoopback = AIEndpointPolicy.isLoopback(connection.baseURL)
        let retargeted =
            hasStoredKey && saved.map { !AIEndpointPolicy.sameDestination(connection, $0) } == true
        if retargeted {
            return isLoopback
                ? .removeStored
                : .reject("Enter an API key for this endpoint — the saved key stays with the old one.")
        }
        guard isLoopback || hasStoredKey else {
            return .reject("Enter an API key for this remote provider.")
        }
        return .keep
    }
}
