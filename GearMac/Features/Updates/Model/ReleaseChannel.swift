// 文件职责：区分稳定版、Beta 与本地开发构建三种发布通道。
// 分层：Model（Sendable 枚举）；由 bundle ID 推导通道，不产生任何副作用。
import Foundation

/// 各通道的应用可并存且各有自己的 bundle ID，因此一个构建只会在自己的通道内更新。
enum ReleaseChannel: Sendable {
    case stable
    case beta
    /// 本地构建。它没有发布流，且从不自我更新。
    case development

    /// 依据 bundle ID 判断所属通道；无法识别时视为本地开发构建。
    init(bundleID: String?) {
        switch bundleID {
        case "com.gearmac.app": self = .stable
        case "com.gearmac.app.beta": self = .beta
        default: self = .development
        }
    }

    /// 该通道是否支持自我更新。
    var updatesItself: Bool { self != .development }

    /// Beta 以 GitHub 预发布形式发布而稳定版不是，两者互不可见对方的版本。
    func accepts(prerelease: Bool) -> Bool {
        switch self {
        case .stable: return !prerelease
        case .beta: return prerelease
        case .development: return false
        }
    }
}
