// 文件职责：定义菜单快照的采集策略，把菜单树按深度与数量上限展平为可搜索条目。
// 分层：Model；纯采集逻辑，不 import AppKit/SwiftUI，不承担副作用。
import Foundation

/// 菜单树快照的采集策略：深度、总量与单子菜单上限。
enum MenuSnapshotPolicy {
    /// 菜单树递归的最大深度。
    static let maxDepth = 20
    // 依据真实菜单规模设定：Safari 约有 2,800 个叶子项，因此该上限可容纳巨型菜单栏。
    static let itemLimit = 4_000
    // 单个类似 History 的子菜单不得占满快照：每个子菜单最多贡献这么多项。
    static let perSubmenuLimit = 200

    // Apple 菜单总是菜单栏的第一项，比匹配会随本地化变化的标题更可靠。
    /// 去除菜单栏的第一项（Apple 菜单）。
    static func excludingAppleMenu(_ roots: [MenuTreeNode]) -> [MenuTreeNode] {
        Array(roots.dropFirst())
    }

    /// 将菜单树展平为去重的可搜索条目列表。
    static func collect(
        _ roots: [MenuTreeNode], isCancelled: () -> Bool = { false }
    ) -> [MenuSearchItem] {
        var items: [MenuSearchItem] = []
        var seen: Set<String> = []
        collect(
            nodes: roots, trail: [], depth: 0, isCancelled: isCancelled, into: &items,
            seen: &seen)
        return items
    }

    /// 递归采集的实体：按路径拼接 id 去重，并受深度、总量与单子菜单上限约束。
    private static func collect(
        nodes: [MenuTreeNode], trail: [String], depth: Int,
        isCancelled: () -> Bool, into items: inout [MenuSearchItem], seen: inout Set<String>
    ) {
        guard depth < maxDepth else { return }
        var directLeaves = 0
        for node in nodes {
            guard !isCancelled(), items.count < itemLimit else { return }
            guard !node.children.isEmpty else {
                // 仅限制直接叶子项，不限制递归；菜单栏本身不算子菜单。
                guard depth == 0 || directLeaves < perSubmenuLimit else { continue }
                // 折叠的子菜单不暴露子节点，因此没有可见叶子项可输出。
                if !node.hasSubmenu,
                    MenuSearchItem.isEligible(
                        title: node.title, isEnabled: node.isEnabled, isHidden: node.isHidden,
                        isSeparator: node.isSeparator, canPress: node.canPress)
                {
                    let item = MenuSearchItem(
                        title: node.title, parentComponents: trail,
                        shortcut: node.shortcut)
                    // 真实菜单会出现完全相同的路径；命令面板需要每个 id 只保留一行。
                    if seen.insert(item.id).inserted {
                        items.append(item)
                        directLeaves += 1
                    }
                }
                continue
            }
            // 父项只用于展开子菜单，本身从不计入可激活的叶子项。
            var subtrail = trail
            if !node.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                subtrail.append(node.title)
            }
            collect(
                nodes: node.children, trail: subtrail, depth: depth + 1,
                isCancelled: isCancelled, into: &items, seen: &seen)
        }
    }
}
