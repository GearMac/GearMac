// 文件职责：定义界面语言偏好（跟随系统 / English / 简体中文）及其解析、Locale 与选择器显示名。
// 分层：Model（本地化）；仅 Foundation，不依赖 AppKit/SwiftUI，保证可被 harness 编译。
import Foundation

/// 界面语言偏好。`.system` 按系统首选语言解析，其余强制指定一种。
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case chinese

    var id: String { rawValue }

    /// 解析为具体生效的语言：`.system` 只看系统首选语言，其余返回自身。
    func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        switch self {
        case .english, .chinese:
            return self
        case .system:
            let code = preferredLanguages.first.map {
                Locale(identifier: $0).language.languageCode?.identifier ?? $0
            } ?? "en"
            return code.hasPrefix("zh") ? .chinese : .english
        }
    }

    /// 供 `Locale`、日期与数字格式化使用的标识符。
    var localeIdentifier: String {
        switch self {
        case .system: return Locale.current.identifier
        case .english: return "en"
        case .chinese: return "zh-Hans"
        }
    }
}
