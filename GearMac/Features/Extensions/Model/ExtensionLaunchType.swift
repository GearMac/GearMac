// 文件职责：定义扩展命令的启动方式枚举（用户主动触发 / 后台启动），与上游 API 的取值保持一致。
// 分层：Model；纯枚举，不 import AppKit/SwiftUI。
import Foundation

/// 对应 `@raycast/api` 的 `LaunchType`；其 raw 値必须与
/// `Scripts/raycast-runtime/src/api/enums.generated.js` 中的 `LaunchType` 一致，因为 JS 端会与之比较。
enum ExtensionLaunchType: String, Sendable {
    /// 由用户主动触发启动。
    case userInitiated
    /// 后台启动，不抢占前台焦点。
    case background
}
