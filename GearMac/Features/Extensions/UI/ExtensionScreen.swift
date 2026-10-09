// 文件职责：把扩展的渲染树解析成调色板可直接使用的界面模型（行、可选条目、表单字段、操作项等）。
// 分层：Model；仅依赖 Foundation 与 SwiftUI 的轻量类型，不产生副作用，行顺序是唯一真相来源。
import Foundation
import SwiftUI

/// 行顺序的唯一来源，使调色板的扁平 `selection` 与可见行一一对应。
struct ExtensionScreen: Equatable {
    /// 一次选中变更的回调信息：处理函数名与目标条目标识。
    struct SelectionChange: Equatable {
        let handler: String
        let itemID: String?
    }

    /// 屏幕类型：列表、网格、详情、表单，或调色板不支持的类型。
    enum Kind: Equatable {
        case list
        case grid(ExtensionGridLayout)
        case detail
        case form
        /// 调色板不渲染的根组件，或尚未渲染出任何内容。
        case unsupported(String)
    }

    /// `id` 是滚动定位的目标：行内的 `.id()` 只有在该行被实体化之后才存在。
    struct Item: Equatable, Identifiable {
        let node: RenderNode
        let index: Int

        var id: String { "item:\(node.id)" }
    }

    /// 屏幕上的一行：分组标题或可选条目。
    enum Row: Equatable, Identifiable {
        case header(title: String, subtitle: String?, id: String)
        case item(Item)

        var id: String {
            switch self {
            case .header(_, _, let id): return "header:" + id
            case .item(let item): return item.id
            }
        }
    }

    let kind: Kind
    let root: RenderNode?
    let rows: [Row]
    /// 按可见顺序排列的可选行 —— 即 `selection` 索引的对象。
    let items: [Item]
    /// Form 的字段，按顺序排列。
    let fields: [RenderNode]
    let isLoading: Bool
    let navigationTitle: String?
    let searchPlaceholder: String?
    /// 为 true 时由调色板自行过滤行；为 false 时搜索文本归扩展所有。
    let filtersLocally: Bool
    let searchTextHandler: String?
    let selectionHandler: String?
    let selectedItemID: String?
    let searchBarAccessory: RenderNode?
    /// `List` 层级的 `isShowingDetail`；置位时行旁边会出现详情面板。
    let showsDetail: Bool
    /// 挂在屏幕自身上的操作（`Detail`/`Form`/`List` 层级）。
    let screenActions: RenderNode?
    /// 无行时展示的 `EmptyView`。
    let emptyView: RenderNode?

    /// 每个分组的可选行数：网格导航据此在跨分组标题时保持列位置。
    var sectionCounts: [Int] {
        var counts: [Int] = []
        for row in rows {
            switch row {
            case .header:
                counts.append(0)
            case .item:
                if counts.isEmpty { counts.append(0) }
                counts[counts.count - 1] += 1
            }
        }
        // 空分组虽然会被绘制，但没有任何可落点，因此不算作网格的一行。
        return counts.filter { $0 > 0 }
    }

    /// 空屏幕，作为解析失败时的兜底。
    static let empty = ExtensionScreen(
        kind: .unsupported(""), root: nil, rows: [], items: [], fields: [], isLoading: false,
        navigationTitle: nil, searchPlaceholder: nil, filtersLocally: false, searchTextHandler: nil,
        selectionHandler: nil, selectedItemID: nil, searchBarAccessory: nil, showsDetail: false,
        screenActions: nil, emptyView: nil)

    /// 仅在扩展未接管搜索文本时，按 `query` 过滤行。
    init(tree: RenderTree, query: String) {
        guard let root = tree.activeRoot else {
            self = .empty
            return
        }
        self.root = root
        isLoading = root.bool("isLoading") ?? false
        navigationTitle = root.string("navigationTitle")
        searchPlaceholder = root.string("searchBarPlaceholder")
        searchTextHandler = root.handler("onSearchTextChange")
        selectionHandler = root.handler("onSelectionChange")
        selectedItemID = root.string("selectedItemId")
        searchBarAccessory = root.node("searchBarAccessory")
        showsDetail = root.bool("isShowingDetail") ?? false
        screenActions = root.node("actions")
        filtersLocally =
            root.bool("filtering") ?? (root.object("filtering") != nil || searchTextHandler == nil)

        switch root.type {
        case "List":
            kind = .list
        case "Grid":
            kind = .grid(ExtensionGridLayout(root))
        case "Detail":
            kind = .detail
        case "Form":
            kind = .form
        default:
            kind = .unsupported(root.type)
        }

        switch kind {
        case .list, .grid:
            let itemType = root.type == "Grid" ? "Grid.Item" : "List.Item"
            let sectionType = root.type == "Grid" ? "Grid.Section" : "List.Section"
            let emptyType = root.type == "Grid" ? "Grid.EmptyView" : "List.EmptyView"
            emptyView = root.children.first { $0.type == emptyType }
            let needle = FuzzyMatch.Query(
                filtersLocally ? query.trimmingCharacters(in: .whitespaces) : "")
            var rows: [Row] = []
            var items: [Item] = []
            // 构建行时即编号，使 `selection` 与绘制顺序保持同步。
            func append(_ node: RenderNode) {
                let item = Item(node: node, index: items.count)
                items.append(item)
                rows.append(.item(item))
            }
            for child in root.children {
                if child.type == sectionType {
                    let matching = child.children
                        .filter { $0.type == itemType }
                        .filter { ExtensionScreen.matches($0, needle) }
                    guard !matching.isEmpty else { continue }
                    rows.append(
                        .header(
                            title: child.string("title") ?? "",
                            subtitle: child.string("subtitle"), id: String(child.id)))
                    matching.forEach(append)
                } else if child.type == itemType, ExtensionScreen.matches(child, needle) {
                    append(child)
                }
            }
            self.rows = rows
            self.items = items
            fields = []

        case .form:
            fields = root.children.filter { $0.type.hasPrefix("Form.") }
            rows = []
            // 表单中可聚焦的字段即为它的可选行，使 ↑/↓ 与 ⇥ 走同一套顺序。
            var fieldItems: [Item] = []
            for field in fields where ExtensionFormField(type: field.type).isFocusable {
                fieldItems.append(Item(node: field, index: fieldItems.count))
            }
            items = fieldItems
            emptyView = nil

        case .detail, .unsupported:
            rows = []
            items = []
            fields = []
            emptyView = nil
        }
    }

    /// 私有全量初始化器，供 `empty` 等静态构造使用。
    private init(
        kind: Kind, root: RenderNode?, rows: [Row], items: [Item], fields: [RenderNode],
        isLoading: Bool, navigationTitle: String?, searchPlaceholder: String?, filtersLocally: Bool,
        searchTextHandler: String?, selectionHandler: String?, selectedItemID: String?,
        searchBarAccessory: RenderNode?, showsDetail: Bool, screenActions: RenderNode?,
        emptyView: RenderNode?
    ) {
        self.kind = kind
        self.root = root
        self.rows = rows
        self.items = items
        self.fields = fields
        self.isLoading = isLoading
        self.navigationTitle = navigationTitle
        self.searchPlaceholder = searchPlaceholder
        self.filtersLocally = filtersLocally
        self.searchTextHandler = searchTextHandler
        self.selectionHandler = selectionHandler
        self.selectedItemID = selectedItemID
        self.searchBarAccessory = searchBarAccessory
        self.showsDetail = showsDetail
        self.screenActions = screenActions
        self.emptyView = emptyView
    }

    /// 当前选中条目在 `items` 中的下标。
    var selectedItemIndex: Int? {
        guard let selectedItemID else { return nil }
        return items.firstIndex { $0.node.string("id") == selectedItemID }
    }

    /// 本地过滤改变可见行顺序之后，解析出 List/Grid 的回调信息。
    func selectionChange(at index: Int) -> SelectionChange? {
        guard let selectionHandler else { return nil }
        let itemID = items.indices.contains(index) ? items[index].node.string("id") : nil
        return SelectionChange(handler: selectionHandler, itemID: itemID)
    }

    /// 以标题、副标题与关键词作为匹配范围，由启动器的模糊匹配器评分。
    static func matches(_ item: RenderNode, _ needle: FuzzyMatch.Query) -> Bool {
        guard !needle.isEmpty else { return true }
        var haystack = [item.string("title") ?? ""]
        if let subtitle = item.string("subtitle") { haystack.append(subtitle) }
        haystack.append(contentsOf: item.array("keywords").compactMap(\.stringValue))
        return haystack.contains { FuzzyMatch.score(needle, candidate: $0) != nil }
    }

    /// 当前选中项适用的 `ActionPanel`：优先取条目自身的，否则取屏幕级的。
    func actionPanel(forItemAt index: Int) -> RenderNode? {
        if items.indices.contains(index), let panel = items[index].node.node("actions") {
            return panel
        }
        return screenActions
    }

    /// 已绘制字段在焦点顺序中的位置；永远不会被聚焦的字段返回 nil。
    func focusItem(for field: RenderNode) -> Item? {
        items.first { $0.node.id == field.id }
    }

    /// 表单打开时聚焦的字段：优先请求自动聚焦的那个，否则取第一个。
    var autoFocusedField: Int {
        items.first { $0.node.bool("autoFocus") == true }?.index ?? 0
    }

    /// 子菜单会展平到所属分组中：调色板的菜单是扁平的。
    static func actions(in panel: RenderNode?) -> [ExtensionAction] {
        guard let panel else { return [] }
        var result: [ExtensionAction] = []
        // 按节点而非标题区分：无标题分组很常见，且仍需彼此分隔。
        var previousSection: RenderNode.ID?
        // submenuTitle：操作所属的最外层子菜单，使按 ⏎ 可以打开它而不是直接执行。
        func walk(_ node: RenderNode, section: RenderNode.ID?, submenuTitle: String?) {
            for child in node.children {
                switch child.type {
                case "Action":
                    let startsSection = !result.isEmpty && section != previousSection
                    result.append(
                        ExtensionAction(
                            node: child, startsSection: startsSection,
                            enclosingSubmenuTitle: submenuTitle))
                    previousSection = section
                case "ActionPanel.Section":
                    walk(child, section: child.id, submenuTitle: submenuTitle)
                case "ActionPanel.Submenu":
                    walk(child, section: section, submenuTitle: submenuTitle ?? child.string("title"))
                default:
                    break
                }
            }
        }
        walk(panel, section: nil, submenuTitle: nil)
        return result
    }
}

/// One activatable action from an `ActionPanel`.
/// `ActionPanel` 中一个可激活的操作。
struct ExtensionAction: Equatable, Identifiable {
    let node: RenderNode
    /// 分组边界后的第一个操作为 true，菜单会在它上方绘制分隔线。
    let startsSection: Bool
    /// 最外层所属子菜单的标题（若存在），使 ⏎ 可以打开子菜单而非触发操作。
    let enclosingSubmenuTitle: String?

    var id: Int { node.id }
    var title: String { node.string("title") ?? "Action" }
    var handler: String? { node.handler("onAction") }
    var isDestructive: Bool { node.string("style") == "destructive" }
    var iconValue: RenderValue? { node.props["icon"] }

    /// 把 `{modifiers: ["cmd","shift"], key: "c"}` 渲染为调色板的键帽字形。
    var shortcutCaps: [String]? {
        guard let shortcut = node.object("shortcut") else { return nil }
        // 跨平台快捷键会把真正的快捷键嵌套在 `macOS` 之下。
        let resolved = shortcut["macOS"]?.objectValue ?? shortcut
        guard let key = resolved["key"]?.stringValue else { return nil }
        let modifiers = (resolved["modifiers"]?.arrayValue ?? []).compactMap(\.stringValue)
        var caps = modifiers.compactMap { modifier -> String? in
            switch modifier {
            case "cmd": return "⌘"
            case "ctrl": return "⌃"
            case "opt", "alt": return "⌥"
            case "shift": return "⇧"
            default: return nil
            }
        }
        caps.append(ExtensionAction.keyCap(key))
        return caps
    }

    /// 修饰键必须完全一致，因此 ⌘⇧C 不会触发普通的 ⌘C 操作。
    func matches(key: KeyEquivalent, modifiers: EventModifiers) -> Bool {
        guard let shortcut = node.object("shortcut") else { return false }
        let resolved = shortcut["macOS"]?.objectValue ?? shortcut
        guard let declared = resolved["key"]?.stringValue else { return false }
        let declaredModifiers = (resolved["modifiers"]?.arrayValue ?? []).compactMap(\.stringValue)

        var expected: EventModifiers = []
        for modifier in declaredModifiers {
            switch modifier {
            case "cmd": expected.insert(.command)
            case "ctrl": expected.insert(.control)
            case "opt", "alt": expected.insert(.option)
            case "shift": expected.insert(.shift)
            default: break
            }
        }
        let pressed: EventModifiers = [.command, .control, .option, .shift].filter {
            modifiers.contains($0)
        }
        .reduce(into: EventModifiers()) { $0.insert($1) }
        guard pressed == expected else { return false }
        return ExtensionAction.keyEquivalent(declared) == key
    }

    /// 把 Raycast 的 `KeyEquivalent` 名称映射为 SwiftUI 的对应值。
    private static func keyEquivalent(_ key: String) -> KeyEquivalent {
        switch key {
        case "return", "enter": return .return
        case "delete", "backspace": return .delete
        case "deleteForward": return .deleteForward
        case "tab": return .tab
        case "arrowUp": return .upArrow
        case "arrowDown": return .downArrow
        case "arrowLeft": return .leftArrow
        case "arrowRight": return .rightArrow
        case "escape": return .escape
        case "space": return .space
        case "pageUp": return .pageUp
        case "pageDown": return .pageDown
        case "home": return .home
        case "end": return .end
        default: return KeyEquivalent(Character(key.lowercased().first.map(String.init) ?? " "))
        }
    }

    /// 把按键名映射为键帽上显示的符号。
    private static func keyCap(_ key: String) -> String {
        switch key {
        case "return", "enter": return "↵"
        case "delete", "backspace": return "⌫"
        case "deleteForward": return "⌦"
        case "tab": return "⇥"
        case "arrowUp": return "↑"
        case "arrowDown": return "↓"
        case "arrowLeft": return "←"
        case "arrowRight": return "→"
        case "escape": return "⎋"
        case "space": return "␣"
        case "pageUp": return "⇞"
        case "pageDown": return "⇟"
        case "home": return "↖"
        case "end": return "↘"
        default: return key.uppercased()
        }
    }
}
