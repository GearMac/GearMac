// 文件职责：定义房间（room）在其落到的显示器上排布窗口的布局种类枚举。
// 分层：Model；保持纯净，仅依赖 Foundation，`allCases` 的顺序即 Tab 切换顺序。
// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import Foundation

/// 房间在其落到的显示器上如何排布窗口。`allCases` 的顺序即 Tab 切换顺序。
enum RoomLayoutKind: String, Codable, CaseIterable, Sendable {
    /// Focus、Columns 或 Grid 中能让每个窗口都足够舒适的那个；都不满足时用 Stack。
    case auto
    case focus
    case stack
    case columns
    case grid
    case custom
    /// 记忆布局时窗口所在的精确位置。
    case saved

    /// 按语言取显示名称。
    func localizedTitle(_ language: AppLanguage) -> String {
        switch self {
        case .auto: L10n.string(WindowKey.roomKindAuto, language: language)
        case .focus: L10n.string(WindowKey.roomKindFocus, language: language)
        case .stack: L10n.string(WindowKey.roomKindStack, language: language)
        case .columns: L10n.string(WindowKey.roomKindColumns, language: language)
        case .grid: L10n.string(WindowKey.roomKindGrid, language: language)
        case .custom: L10n.string(WindowKey.roomKindCustom, language: language)
        case .saved: L10n.string(WindowKey.roomKindSaved, language: language)
        }
    }
}
