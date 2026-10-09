// 文件职责：定义外观模式枚举（跟随系统/浅色/深色），并把它映射为 AppKit 的 NSAppearance。
// 分层：Settings（Model）；纯值类型，不承担副作用，只负责把用户偏好翻译为外观对象。
import AppKit

/// GearMac 渲染时所使用的外观模式；键未设置时按 `.system` 处理。
enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// 设置界面中展示的名称。
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// 返回 `nil` 表示把选择权交回 AppKit，从而自动且实时地跟随 macOS。
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
