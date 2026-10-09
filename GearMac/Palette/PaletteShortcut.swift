// 文件职责：定义作用于选中行的快捷键组合，并按键位解析映射到具体快捷键（键盘布局保持位置一致）。
// 分层：Model；纯枚举与解析函数，无副作用。
import Foundation

/// 指向选中行的组合键。由调色板识别，具体行为由屏幕决定。
enum PaletteShortcut: Equatable {
    /// ⌘⌫ 或 ⌘⌦。
    case commandDelete
    /// ⌃X。
    case delete
    /// ⌃⇧X。
    case deleteAll
    /// ⇧⌘C。
    case copyFile
    /// ⌥⌘C。
    case copyName
    /// ⌃⌘C。
    case copyPath
    /// ⇧⌘T。
    case copyText
    /// ⇧⌘↵，由 Return 处理器匹配而非 `resolve`。
    case copyCalculation
    /// ⇧⌘V。
    case pasteFile
    /// ⌘Y。
    case quickLook
    /// ⌘O，把该行交给拥有它的应用。
    case openInApp
    /// ⌘I。
    case showDetails
    /// ⇧⌘F。
    case toggleFavorite
    /// ⇧⌘H。
    case hideFromSearch
    /// ⌃⇧Q。
    case quit
    /// ⌃⌥⇧Q。
    case forceQuit
    /// ⌘R。
    case restart
    /// ⌘N，新建一个当前屏幕所属类型的新项。
    case newItem
    /// ⌥⌘,，屏幕自己的设置；单独的 ⌘, 仍属于整个应用。
    case settings
    /// ⌘J，Quick AI 将对话交给 AI Chat 窗口继续。
    case continueInChat
    /// ⌘.，AppKit 将它绑定到 `cancelOperation:`，因此以 token 而非按键形式到达。
    case pin
    /// ⌘1…⌘0，在面板中按 key code 匹配，并以槽位号交出。
    case favoriteSlot(Int)

    /// `matches` 通过当前键盘布局比较按下的键，因此字母保持物理位置。
    static func resolve(
        command: Bool, shift: Bool, option: Bool, control: Bool, isDeleteKey: Bool,
        matches: (Character) -> Bool
    ) -> Self? {
        if isDeleteKey { return command ? .commandDelete : nil }
        if command, matches("c") {
            if shift { return .copyFile }
            if option { return .copyName }
            return control ? .copyPath : nil
        }
        if command, shift, matches("v") { return .pasteFile }
        if command, shift, matches("t") { return .copyText }
        if command, matches("y") { return .quickLook }
        if command, !shift, matches("o") { return .openInApp }
        if command, !shift, matches("i") { return .showDetails }
        if control, matches("x") { return shift ? .deleteAll : .delete }
        if command, shift, matches("f") { return .toggleFavorite }
        if command, shift, matches("h") { return .hideFromSearch }
        if control, shift, matches("q") { return option ? .forceQuit : .quit }
        if command, matches("r") { return .restart }
        if command, !shift, matches("n") { return .newItem }
        if command, option, matches(",") { return .settings }
        if command, matches("j") { return .continueInChat }
        return nil
    }

    /// 紧凑栏不显示选中项，因此指向高亮行的组合键要等列表展开后才生效。
    var requiresExpanded: Bool {
        switch self {
        case .copyFile, .copyName, .copyPath, .copyText, .pasteFile, .quickLook, .openInApp,
            .showDetails, .toggleFavorite, .hideFromSearch, .quit, .forceQuit, .restart:
            true
        case .commandDelete, .delete, .deleteAll, .pin, .favoriteSlot, .continueInChat, .newItem,
            .settings, .copyCalculation:
            false
        }
    }

    /// 执行后是否关闭菜单。
    var closesMenu: Bool {
        switch self {
        case .delete, .deleteAll, .copyFile, .copyName, .copyPath, .copyText, .copyCalculation,
            .quickLook, .openInApp, .showDetails, .toggleFavorite, .hideFromSearch, .newItem, .settings:
            true
        case .commandDelete, .pasteFile, .quit, .forceQuit, .restart, .pin, .favoriteSlot,
            .continueInChat:
            false
        }
    }
}
