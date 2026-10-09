// 文件职责：定义菜单树的节点模型，承载标题、可用性与子节点。
// 分层：Model；纯值类型，不 import AppKit/SwiftUI，不承担副作用。
import Foundation

/// 菜单树中的一个节点：标题、可用/隐藏/分隔线/可按下标志、快捷键与子节点。
struct MenuTreeNode: Hashable, Sendable {
    let title: String
    let isEnabled: Bool
    let isHidden: Bool
    let isSeparator: Bool
    let canPress: Bool
    let hasSubmenu: Bool
    let shortcut: MenuSearchShortcut?
    let children: [MenuTreeNode]

    /// 构造一个菜单节点，各项 AX 标志均有默认值。
    init(
        title: String, isEnabled: Bool = true, isHidden: Bool = false, isSeparator: Bool = false,
        canPress: Bool = true, hasSubmenu: Bool = false, shortcut: MenuSearchShortcut? = nil,
        children: [MenuTreeNode] = []
    ) {
        self.title = title
        self.isEnabled = isEnabled
        self.isHidden = isHidden
        self.isSeparator = isSeparator
        self.canPress = canPress
        self.hasSubmenu = hasSubmenu
        self.shortcut = shortcut
        self.children = children
    }
}
