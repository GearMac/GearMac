// 文件职责：定义菜单搜索条目模型，封装菜单项的标题、父级路径与快捷键。
// 分层：Model；纯值类型，不 import AppKit/SwiftUI，不承担副作用。
import Foundation

/// 一条可搜索的菜单项，id 由标题与父级路径拼接而成。
struct MenuSearchItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let parentComponents: [String]
    let shortcut: MenuSearchShortcut?

    init(title: String, parentComponents: [String], shortcut: MenuSearchShortcut? = nil) {
        self.title = title
        self.parentComponents = parentComponents
        self.shortcut = shortcut
        id = Self.joined(title: title, parents: parentComponents, separator: "\u{1F}")
    }

    /// 供列表展示的完整路径，如「File → Open」。
    var displayPath: String {
        Self.joined(title: title, parents: parentComponents, separator: Self.separator)
    }

    /// 顶层菜单名（父级路径的第一段）。
    var menu: String { parentComponents.first ?? "" }

    /// 完整父级路径。
    var menuPath: String { parentComponents.joined(separator: Self.separator) }

    /// 去掉顶层菜单后的子菜单路径。
    var submenuPath: String { parentComponents.dropFirst().joined(separator: Self.separator) }

    private static let separator = " → "

    /// 用指定分隔符把父级路径与标题拼成完整字符串。
    private static func joined(title: String, parents: [String], separator: String) -> String {
        (parents + [title]).joined(separator: separator)
    }

    /// 判定一个菜单项是否值得收录：需可用、可见、非分隔线、可按下且标题非空。
    static func isEligible(
        title: String, isEnabled: Bool, isHidden: Bool, isSeparator: Bool, canPress: Bool
    ) -> Bool {
        guard isEnabled, !isHidden, !isSeparator, canPress else { return false }
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // 路径作为 owner 字段参与匹配，而非翻译字段：共享的层级字符串必须保持字面量。
    /// 提供搜索字段：标题作为名称别名，完整路径作为 owner 字段。
    func searchFields() -> SearchFields {
        [SearchAlias.name(title), SearchAlias(displayPath, .owner)]
    }
}
