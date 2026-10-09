// 文件职责：在扩展基于条目 id 的选中态与 GearMac 调色板的扁平索引之间做双向同步。
// 分层：UI；作为 ViewModifier 监听选中变化并派发给扩展，不直接持有扩展状态。
import Foundation
import SwiftUI

/// 保持扩展基于条目 id 的选中态与 GearMac 扁平调色板索引之间的同步。
struct ExtensionSelectionForwarder: ViewModifier {
    let screen: ExtensionScreen
    let selection: Int
    @Environment(PaletteState.self) private var palette
    @Environment(ExtensionManager.self) private var extensions
    @State private var seededContext: String?

    /// 夹取到有效范围内的当前选中下标。
    private var selectedIndex: Int {
        screen.items.isEmpty ? 0 : min(max(selection, 0), screen.items.count - 1)
    }

    /// 当前运行扩展与根节点的组合标识，用于判断是否跨越扩展切换重新播种。
    private var context: String? {
        guard let running = extensions.running, let root = screen.root else { return nil }
        return "\(running.entryID):\(root.id)"
    }

    /// 监听选中变化，并派发扩展的 onSelectionChange 处理器。
    func body(content: Content) -> some View {
        content.onChange(of: screen.selectionChange(at: selectedIndex), initial: true) { _, change in
            guard let change else { return }
            if seededContext != context {
                seededContext = context
                if let index = screen.selectedItemIndex, selectedIndex != index {
                    palette.selection = index
                    return
                }
            }
            let argument: Any = change.itemID.map { $0 as Any } ?? NSNull()
            extensions.dispatch(handler: change.handler, arguments: [argument])
        }
    }
}
