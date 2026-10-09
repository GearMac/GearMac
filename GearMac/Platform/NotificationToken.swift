// 文件职责：提供 NotificationCenter 通知监听令牌的 RAII 句柄，在释放时自动移除监听。
// 分层：Service；不依赖 AppKit/SwiftUI。
import Foundation

/// 块式通知监听的 RAII 句柄，使 `removeObserver` 能在 nonisolated 的 deinit 中执行。
final class NotificationToken {
    private let center: NotificationCenter
    private let token: any NSObjectProtocol

    /// 保存 token 与对应的通知中心，直到自身释放时移除监听。
    init(_ token: any NSObjectProtocol, center: NotificationCenter) {
        self.token = token
        self.center = center
    }

    deinit {
        center.removeObserver(token)
    }
}
