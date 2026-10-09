// 文件职责：解析 ⌘P 应打开哪个头部菜单（按当前模式与是否有运行中命令决定）。
// 分层：Model；纯枚举与解析函数，无副作用。
import Foundation

/// ⌘P 打开哪个头部菜单；运行中命令自己的下拉菜单总是优先响应。
enum PaletteFilterAction: Equatable {
    /// 运行中命令的 `searchBarAccessory` 下拉菜单。
    case extensionAccessory
    case clipboardFilter
    case fileSearchFilter
    case emojiCategory
    case aiModel
    /// 头部没有可打开的过滤器，因此该键留给搜索框。
    case ignored

    /// 按折叠状态、模式与命令是否有附件按钮解析实际应打开的过滤器。
    static func resolve(
        collapsed: Bool, mode: PaletteMode, commandHasAccessory: Bool
    ) -> Self {
        // 紧凑栏不绘制任何头部控件，因此两个过滤器都没有按钮可挂。
        guard !collapsed else { return .ignored }
        switch mode {
        case .extensionCommand: return commandHasAccessory ? .extensionAccessory : .ignored
        case .clipboard: return .clipboardFilter
        case .fileSearch: return .fileSearchFilter
        case .emoji: return .emojiCategory
        case .ai: return .aiModel
        default: return .ignored
        }
    }
}
