// 文件职责：建模选择器列表中的单个选项（来自 `Form.Dropdown`/`Form.TagPicker` 或搜索栏附件），并从渲染节点展开选项。
// 分层：Model；仅数据结构与节点遍历，不 import AppKit/SwiftUI。
import Foundation

/// 选择器列表提供的一个选项，来自 `Form.Dropdown`/`Form.TagPicker`，或扩展通过
/// `searchBarAccessory` 交给界面的搜索栏下拉菜单。
struct ExtensionPickerItem: Identifiable, Equatable {
    /// 选项的值，同时也作为其标识。
    let value: String
    /// 选项展示的标题。
    let title: String
    /// 可选的补充说明。
    var detail: String?
    /// 可选的图标值。
    var iconValue: RenderValue?
    /// 该选项声明时所属的分组，绘制在其首个选项上方。
    var section: String?

    var id: String { value }

    /// 选择器的选项：直接子节点，或按带标题的分组分包。
    static func items(in node: RenderNode) -> [ExtensionPickerItem] {
        var items: [ExtensionPickerItem] = []
        func walk(_ node: RenderNode, section: String?) {
            for child in node.children {
                if child.type.hasSuffix(".Item") {
                    let value = child.string("value") ?? ""
                    items.append(
                        ExtensionPickerItem(
                            value: value, title: child.string("title") ?? value,
                            iconValue: child.props["icon"], section: section))
                } else if child.type.hasSuffix(".Section") {
                    walk(child, section: child.string("title"))
                }
            }
        }
        walk(node, section: nil)
        return items
    }
}
