// 文件职责：定义扩展启动失败时对外暴露的错误类型及其本地化描述文案。
// 分层：Model；仅承载错误枚举，不 import AppKit/SwiftUI。
import Foundation

/// 扩展启动过程中可能出现的错误。
enum ExtensionLaunchError: LocalizedError {
    /// 没有已安装的扩展提供指定命令。
    case unknownCommand(String)
    /// 命令类型不被支持，字符串为原因。
    case unsupported(String)
    /// 扩展缺少已构建的 bundle。
    case notBuilt(String)
    /// 命令所需的偏好项尚未设置。
    case missingPreferences([ExtensionPreferenceSchema])

    /// 面向用户的本地化错误描述。
    var errorDescription: String? {
        switch self {
        case .unknownCommand(let id): return "No installed extension provides '\(id)'."
        case .unsupported(let reason): return reason
        case .notBuilt(let name):
            return "\(name) has no built bundle — reinstall the extension."
        case .missingPreferences(let schemas):
            let names = schemas.map(\.displayTitle).joined(separator: ", ")
            return "This command needs its preferences set first: \(names)."
        }
    }
}
