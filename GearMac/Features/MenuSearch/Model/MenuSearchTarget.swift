// 文件职责：将前台应用分类为菜单搜索的目标类型，决定是否可搜索及其原因。
// 分层：Model；纯枚举与纯函数，不 import AppKit/SwiftUI。
import Foundation

/// 菜单搜索目标的分类结果：可搜索、已排除、自身、无菜单栏或无前台应用。
enum MenuSearchTarget: Hashable, Sendable {
    case searchable(name: String)
    case excluded(name: String)
    case selfTarget
    case menuLess(name: String)
    case noApplication

    /// 根据应用名与各判定条件分类菜单搜索目标。
    static func classify(
        appName: String?, isSelf: Bool, hasMenuBar: Bool, isExcluded: Bool
    ) -> Self {
        guard let appName else { return .noApplication }
        // GearMac 自身以 accessory 模式运行，因此「自身」优先于下方的菜单栏判定。
        if isSelf { return .selfTarget }
        // 放在菜单栏判定之前，使被排除的 accessory 应用显示为已排除，而不是无菜单栏。
        if isExcluded { return .excluded(name: appName) }
        guard hasMenuBar else { return .menuLess(name: appName) }
        return .searchable(name: appName)
    }
}
