// 文件职责：定义调色板屏幕协议（PaletteScreen）、菜单内容（PaletteMenuContent）与头部附件（PaletteHeaderAccessory）等抽象。
// 分层：UI/Model 协议层（SwiftUI）；@MainActor，描述屏幕的可见顺序与交互契约。
import QuartzCore
import SwiftUI

/// 一次移动来自哪对方向键：↑/↓ 或 ←/→。
enum PaletteAxis {
    case vertical
    case horizontal
}

/// 由内容提供的缩放入场/退场参数，窗口机制仍由调色板拥有。
@MainActor struct MenuPanelMotion {
    let entryScale: CGFloat
    let maximumScale: CGFloat
    let exitScaleDelta: CGFloat
    let expansionDuration: TimeInterval
    let settleDuration: TimeInterval
    let exitDuration: TimeInterval
    let expansionTiming: CAMediaTimingFunction
    let settleTiming: CAMediaTimingFunction
    let exitTiming: CAMediaTimingFunction

    static let palette = MenuPanelMotion(
        entryScale: Theme.MenuMotion.entryScale,
        maximumScale: Theme.MenuMotion.maximumScale,
        exitScaleDelta: Theme.MenuMotion.exitScaleDelta,
        expansionDuration: Theme.MenuMotion.expansionDuration,
        settleDuration: Theme.MenuMotion.settleDuration,
        exitDuration: Theme.MenuMotion.exitDuration,
        expansionTiming: Theme.MenuMotion.expansionTiming,
        settleTiming: Theme.MenuMotion.settleTiming,
        exitTiming: Theme.MenuMotion.exitTiming)
}

typealias MenuPanelClipPath =
    @MainActor (
        _ bounds: CGRect, _ metrics: InterfaceMetrics, _ corner: MenuPanelCorner
    ) -> CGPath

/// 调色板屏幕提供的菜单，包含其渲染与行激活动作。
@MainActor struct PaletteMenuContent {
    let rowCount: Int
    let preferredSelection: Int?
    let isSelectable: (Int) -> Bool
    let clipPath: MenuPanelClipPath
    let motion: MenuPanelMotion
    /// 按需构建：`moveMenu` 在每次方向键时重新解析已打开的菜单。
    let view: (MenuPanelCorner) -> AnyView
    /// 由调用方对照 `rowCount` 做边界校验，因此行索引总是本菜单确实拥有的。
    let activate: (Int) -> Void

    init(
        rowCount: Int, preferredSelection: Int? = nil,
        view: @escaping (MenuPanelCorner) -> AnyView,
        activate: @escaping (Int) -> Void,
        isSelectable: @escaping (Int) -> Bool = { _ in true },
        clipPath: @escaping MenuPanelClipPath,
        motion: MenuPanelMotion
    ) {
        self.rowCount = rowCount
        self.preferredSelection = preferredSelection
        self.view = view
        self.activate = activate
        self.isSelectable = isSelectable
        self.clipPath = clipPath
        self.motion = motion
    }

    init(
        popover: PopoverMenuContent, selection: Binding<Int>, width: CGFloat? = nil,
        search: PopoverMenu.Search, onActivate: @escaping (Int) -> Void,
        preferredSelection: Int? = nil
    ) {
        self.init(
            rowCount: popover.items.count, preferredSelection: preferredSelection,
            view: { corner in
                AnyView(
                    PopoverMenu(
                        header: popover.header, items: popover.items, selection: selection,
                        width: width, onActivate: onActivate,
                        attachment: corner.popoverAttachment, search: search))
            },
            activate: { popover.items[$0].action() },
            isSelectable: { popover.items[$0].isSelectable },
            clipPath: { bounds, metrics, corner in
                PopoverMenu.SurfaceShape(
                    attachment: corner.popoverAttachment, radius: metrics.radius.menuPanel,
                    attachedRadius: metrics.size.menuButton / 2
                ).path(in: bounds).cgPath
            },
            motion: .palette)
    }
}

private extension MenuPanelCorner {
    var popoverAttachment: PopoverMenu.Attachment {
        switch self {
        case .bottomLeading, .aboveLeading: .bottomLeading
        case .bottomTrailing, .aboveTrailing: .bottomTrailing
        case .belowHeaderTrailing, .aboveRect: .none
        }
    }
}

/// 一个调色板模式。`rows` 是可见顺序的唯一来源，因此选中项以它为索引。
@MainActor protocol PaletteScreen {
    associatedtype Row: Identifiable

    var rows: [Row] { get }
    var primaryActionTitle: String { get }
    /// 当屏幕拥有键盘时为 true，此时头部搜索框隐藏且失焦。
    var hidesSearchField: Bool { get }
    /// 当无任何行时底部栏与 ⌘K 仍可用时为 true——表单的动作属于屏幕本身。
    var actsWithoutRows: Bool { get }
    /// 打开、新查询或新过滤后高亮所在位置；超过第 0 行时居中。
    var landingSelection: Int { get }

    /// 选中项无法执行动作时为 false，此时隐藏底部胶囊并吞掉 ⌘K。
    func hasPrimaryAction(at selection: Int) -> Bool
    /// ⌘K 会在空处打开时为 false，此时隐藏底部按钮组的 Actions 一半。
    func hasActions(at selection: Int) -> Bool
    /// 选中行自己用 ↑/↓ 编辑时为 true，此时这两个键交给它处理。
    func ownsVerticalKeys(at selection: Int) -> Bool
    /// ⇥ 在屏幕内的去向，nil 则交给调色板自己的焦点环。
    func tabTarget(from selection: Int, backwards: Bool) -> Int?
    /// 当屏幕自己处理了 ⇥ 时为 true，此时它优先于 `tabTarget` 接管该键。
    func tab(at selection: Int, backwards: Bool) -> Bool
    /// 以调色板自己的菜单形式返回 ⌘K 行；无则为 nil。
    func actions(at selection: Int) -> PopoverMenuContent?
    /// 默认包装 `actions(at:)`，因此屏幕只需实现其中之一。
    func menuContent(
        at selection: Int, searchQuery: ActionMenuSearchQuery, menuSelection: Binding<Int>,
        onActivate: @escaping (Int) -> Void
    ) -> PaletteMenuContent?
    func activate(at selection: Int)
    /// ⌘↵。选中项无次要动作时为 false，此时该键不被处理。
    func secondary(at selection: Int) -> Bool
    /// ⌃⌘↵。选中项无第三动作时为 false，此时该组合键留给 `secondary`。
    func tertiary(at selection: Int) -> Bool
    /// ⌥↵。在大多数无内容可粘贴的屏幕上均为 false。
    func pasteKeepingWindowOpen(at selection: Int) -> Bool
    /// 当屏幕无法响应该组合键时为 false，此时该键不被处理。
    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool
    /// 方向键落到的选中项，nil 则交给调色板自身的默认行为。
    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int?
    /// 行需要在搜索框旁放置的控件；`focus` 是借入而非拥有。
    func headerAccessory(
        at selection: Int, focus: FocusState<String?>.Binding
    )
        -> PaletteHeaderAccessory?
    @ViewBuilder func body(selection: Int, scroll: ScrollIntent) -> AnyView
}

extension PaletteScreen {
    func hasPrimaryAction(at selection: Int) -> Bool { true }
    func hasActions(at selection: Int) -> Bool { true }
    var hidesSearchField: Bool { false }
    var actsWithoutRows: Bool { false }
    var landingSelection: Int { 0 }
    func ownsVerticalKeys(at selection: Int) -> Bool { false }
    func tabTarget(from selection: Int, backwards: Bool) -> Int? { nil }
    func tab(at selection: Int, backwards: Bool) -> Bool { false }
    func actions(at selection: Int) -> PopoverMenuContent? { nil }
    func menuContent(
        at selection: Int, searchQuery: ActionMenuSearchQuery, menuSelection: Binding<Int>,
        onActivate: @escaping (Int) -> Void
    ) -> PaletteMenuContent? {
        guard let content = actions(at: selection) else { return nil }
        let filtered = content.matching(searchQuery)
        return PaletteMenuContent(
            popover: filtered.content, selection: menuSelection,
            search: PopoverMenu.Search(
                placeholder: "Search for actions…", placement: .bottom),
            onActivate: onActivate, preferredSelection: filtered.bestMatch)
    }
    func tertiary(at selection: Int) -> Bool { false }
    func pasteKeepingWindowOpen(at selection: Int) -> Bool { false }
    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool { false }
    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int? { nil }
    func headerAccessory(
        at selection: Int, focus: FocusState<String?>.Binding
    )
        -> PaletteHeaderAccessory?
    { nil }
}

extension PopoverMenuContent {
    /// 即使原本携带分节的行使被过滤掉，也保留分节边界。
    func matching(
        _ query: ActionMenuSearchQuery
    ) -> (
        content: PopoverMenuContent, bestMatch: Int?
    ) {
        guard !query.isEmpty else { return (self, nil) }
        var pendingSection = false
        var pendingTitle: String?
        var matches: [PopoverMenuItem] = []
        var bestMatch: (index: Int, score: Int)?

        for original in items {
            if original.startsSection {
                pendingSection = true
                pendingTitle = nil
            }
            if let sectionTitle = original.sectionTitle { pendingTitle = sectionTitle }
            guard let score = query.score(original.title) else { continue }

            var item = original
            item.startsSection = pendingSection && !matches.isEmpty
            item.sectionTitle = pendingTitle
            pendingSection = false
            pendingTitle = nil
            matches.append(item)
            if item.isSelectable, score > (bestMatch?.score ?? .min) {
                bestMatch = (matches.count - 1, score)
            }
        }
        return (PopoverMenuContent(header: header, items: matches), bestMatch?.index)
    }
}

/// 搜索框旁的控件，以调色板无需知道其具体类型即可处理的方式描述。
struct PaletteHeaderAccessory {
    /// 控件条所处位置，这也决定了它给旁边的搜索框带来什么影响。
    enum Placement {
        /// 紧跟在已输入文本之后，搜索框因此缩短以容纳它——用于根搜索。
        case afterQuery
        /// 置于一个仍保持搜索框形态的字段旁，提示与全宽保持不变。
        case besideSearchField
    }

    /// 控件条需要的宽度，供搜索框让出空间。
    let width: CGFloat
    /// 按视觉顺序排列的可聚焦字段；Tab 在离开头部前会依次走过它们。
    let fieldNames: [String]
    /// ↵ 可执行前仍必须填写的第一个字段，若有。
    let firstIncompleteField: String?
    /// 取值方式为选择而非输入的字段会交回其菜单；nil 表示自由文本。
    let optionsMenu: (String) -> PopoverMenuContent?
    let placement: Placement
    let view: AnyView

    init(
        width: CGFloat, fieldNames: [String], firstIncompleteField: String?,
        optionsMenu: @escaping (String) -> PopoverMenuContent? = { _ in nil },
        placement: Placement = .afterQuery,
        view: AnyView
    ) {
        self.width = width
        self.fieldNames = fieldNames
        self.firstIncompleteField = firstIncompleteField
        self.optionsMenu = optionsMenu
        self.placement = placement
        self.view = view
    }

    /// 相邻的 Tab 字段；焦点回到搜索框后返回 nil。
    func field(after current: String?, backwards: Bool) -> String? {
        guard let current, let index = fieldNames.firstIndex(of: current) else {
            return backwards ? fieldNames.last : fieldNames.first
        }
        let next = index + (backwards ? -1 : 1)
        return fieldNames.indices.contains(next) ? fieldNames[next] : nil
    }
}
