// 文件职责：表示可调度的扩展命令当前的后台刷新状态（开启、关闭或失败）。
// 分层：Model；纯枚举，不 import AppKit/SwiftUI。
import Foundation

/// 可调度的扩展命令是在后台刷新，还是尝试刷新时失败了。
enum ExtensionRefreshState: Sendable, Hashable {
    /// 已开启后台刷新。
    case active
    /// 已调度但已关闭——`active` 的暗色版本，也是开启入口的提示。
    case idle
    /// 刷新失败，附错误信息。
    case failed(String)
}
