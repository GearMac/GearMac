// 文件职责：定义日历访问权限的三种状态。
// 分层：Model；纯值类型，不依赖 AppKit/SwiftUI。
import Foundation

/// 系统允许 GearMac 读取用户日历的程度。
enum CalendarAccess: Sendable {
    case notDetermined
    case granted
    /// 被拒绝或被限制：只有系统设置能撤销，因此两者对我们读起来一样。
    case denied
}
