// 文件职责：建模扩展放在搜索栏中的 `List.Dropdown`/`Grid.Dropdown`，并处理其选项、受控/存储选中值与初始值。
// 分层：Model；仅数据建模与节点解析，不 import AppKit/SwiftUI。
import Foundation

/// 扩展放在搜索栏中的 `List.Dropdown`/`Grid.Dropdown`。运行时保持该组件无 hook，
/// 因此由 Swift 持有选中值，并通过 `onChange` 上报每次变化。
struct ExtensionSearchAccessory: Equatable {
    /// 渲染节点的 id，会话以此作为所持选中值的键。
    let nodeID: Int
    let items: [ExtensionPickerItem]
    let onChange: String?
    /// `value` 属性：只要扩展提供它，选中值就由扩展而非用户掌控。
    let controlledValue: String?
    let defaultValue: String?
    /// `storeValue` 保存选中项的位置；下拉菜单未要求持久化时为 nil。
    let storageKey: String?
    let placeholder: String?
    let tooltip: String?

    /// 从渲染节点解析搜索栏附件；节点缺失或类型不匹配时返回 nil。
    init?(node: RenderNode?) {
        guard let node, node.type == "List.Dropdown" || node.type == "Grid.Dropdown" else {
            return nil
        }
        nodeID = node.id
        items = ExtensionPickerItem.items(in: node)
        onChange = node.handler("onChange")
        controlledValue = node.string("value")
        defaultValue = node.string("defaultValue")
        // Raycast 以下拉菜单自身的 id 作为存储键；每命令仅一个时可省略 id。
        storageKey =
            node.bool("storeValue") == true ? (node.string("id") ?? "searchBarAccessory") : nil
        placeholder = node.string("placeholder")
        tooltip = node.string("tooltip")
    }

    /// Raycast 的取値顺序：已存且仍能对应到某个选项的选中值，否则 `defaultValue`，否则
    /// 首个选项——下拉菜单总会显示一个选项。
    func initialValue(stored: String?) -> String? {
        if let stored, items.contains(where: { $0.value == stored }) { return stored }
        return defaultValue ?? items.first?.value
    }

    /// 关闭状态下控件显示的文本；无任何选项对应的值也仍然显示为该值。
    func title(for value: String?) -> String? {
        guard let value else { return placeholder ?? tooltip }
        return item(for: value)?.title ?? value
    }

    /// 按值查找对应选项；未找到时返回 nil。
    func item(for value: String?) -> ExtensionPickerItem? {
        guard let value else { return nil }
        return items.first { $0.value == value }
    }

    /// 列表打开时停留的行，使其持有的选项正好是已高亮的那一个。
    func index(of value: String?) -> Int {
        items.firstIndex { $0.value == value } ?? 0
    }
}
