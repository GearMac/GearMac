// 文件职责：依据服务器的一贯信任设置与本轮对话已授予的权限，裁决某次调用是否可运行。
// 分层：Model；不得 import AppKit/SwiftUI，纯函数无副作用。
import Foundation

/// 某次调用是否可运行：依据服务器的一贯信任设置与本轮对话已授予的权限。
enum MCPTrustPolicy {
    /// 裁决结果：允许、询问或拒绝。
    enum Verdict: Equatable, Sendable {
        case allow
        case ask
        case refuse
    }

    /// 依信任设置与是否已为本轮对话授权得出裁决。
    static func decide(trust: MCPTrust, isGrantedForChat: Bool) -> Verdict {
        switch trust {
        case .never: return .refuse
        case .always: return .allow
        case .ask: return isGrantedForChat ? .allow : .ask
        }
    }
}

/// 用户在对话框中的选择。只有设置页才能永久禁用某个服务器。
enum MCPTrustChoice: Equatable, Sendable {
    case always
    case thisChat
    case refuse
}
