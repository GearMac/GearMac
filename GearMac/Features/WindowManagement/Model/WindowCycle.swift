// 文件职责：定义重复按下半屏快捷键时的循环行为（关闭 / 尺寸循环 / 跨显示器循环）。
// 分层：Model；保持纯净，仅依赖 Foundation，供 `WindowPlacementEngine` 读取循环步进语义。
import Foundation

/// 重复按下某个半屏快捷键时发生什么。见 docs/features/window-management.md#cycling-and-restore
enum WindowCycle: String, CaseIterable, Identifiable, Sendable {
    /// 重新应用同一个半屏——快捷键幂等。
    case off
    /// 让半屏在 ⅓ 与 ⅔ 之间步进，再回到 ½。
    case sizes
    /// 让半屏沿着每块显示器贡献出的半屏槽位带挪动一格。
    case displays

    var id: String { rawValue }

    /// 按语言取选项标题。
    func localizedTitle(_ language: AppLanguage) -> String {
        switch self {
        case .off: L10n.string(WindowKey.cycleNone, language: language)
        case .sizes: L10n.string(WindowKey.cycleSizes, language: language)
        case .displays: L10n.string(WindowKey.cycleDisplays, language: language)
        }
    }

    /// 按语言取选项说明。
    func localizedDetail(_ language: AppLanguage) -> String {
        switch self {
        case .off: L10n.string(WindowKey.cycleNoneDetail, language: language)
        case .sizes: L10n.string(WindowKey.cycleSizesDetail, language: language)
        case .displays: L10n.string(WindowKey.cycleDisplaysDetail, language: language)
        }
    }
}
