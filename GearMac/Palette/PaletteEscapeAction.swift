// 文件职责：在 Esc 按下时决定该执行哪个动作，按「先关菜单、再退参数字段、再清查询、最后返回/隐藏」的优先级解析。
// 分层：Model；纯枚举与解析函数，无副作用，不 import AppKit/SwiftUI。
import Foundation

/// 按 Esc 时的动作，顺序如同裸退格：只有当搜索框为空时才会离开一个屏幕。
enum PaletteEscapeAction: Equatable {
    case clearMenuQuery
    case closeMenu
    case leaveArgumentField
    case clearQuery
    case exitExtensionScreen
    case goBack
    case hidePalette

    /// 根据当前界面状态解析 Esc 动作；优先级从菜单、参数字段到查询与返回依次递降。
    static func resolve(
        menuOpen: Bool, menuQuery: String, argumentFocused: Bool, query: String, mode: PaletteMode,
        canGoBack: Bool, behavior: EscapeKeyBehavior
    ) -> Self {
        if menuOpen { return menu(query: menuQuery) }
        // 参数字段比查询深一层，因此它先于任何清空操作被离开。
        if argumentFocused { return .leaveArgumentField }
        if !query.isEmpty { return .clearQuery }
        guard behavior == .navigateBackOrClose else { return .hidePalette }
        // 扩展命令会先弹出自己的导航栈，然后才离开命令。
        if mode == .extensionCommand { return .exitExtensionScreen }
        return canGoBack ? .goBack : .hidePalette
    }

    /// 菜单打开时的 Esc 动作：查询为空则关闭菜单，否则先清空菜单查询。
    static func menu(query: String) -> Self {
        query.isEmpty ? .closeMenu : .clearMenuQuery
    }
}
