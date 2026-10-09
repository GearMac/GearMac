// 文件职责：把 ExtensionScreen 模型映射为 PaletteScreen：负责行序、焦点/移动、主操作、图标菜单与快捷键分发。
// 分层：UI/Coordinator；将 `selection` 一对一映射到可见行，并通过 ExtensionManager 派发操作。
import QuartzCore
import SwiftUI

/// 在此重述一份，使启动器的动效变更不会牵动扩展界面的表现。
@MainActor private enum ExtensionMenuMotion {
    private static let entryScale: CGFloat = 0.94
    private static let exitScaleDelta: CGFloat = 0.04

    static let panel = MenuPanelMotion(
        entryScale: entryScale,
        maximumScale: 1.003,
        exitScaleDelta: exitScaleDelta,
        expansionDuration: 0.10,
        settleDuration: 0.05,
        exitDuration: 0.18,
        expansionTiming: CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.2, 1),
        settleTiming: CAMediaTimingFunction(controlPoints: 0.42, 0, 0.58, 1),
        exitTiming: CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1))
}

/// 行顺序由 `ExtensionScreen` 决定；本类型把 `selection` 一对一映射到可见行。
struct ExtensionCommandScreen: PaletteScreen {
    let screen: ExtensionScreen
    let extensions: ExtensionManager
    let vm: PaletteState
    let openActions: () -> Void

    /// 运行中扩展的 `assets/` 路径，使其声明的图标能够解析。
    var assetsPath: String? {
        guard let name = extensions.running?.extensionName,
            let owner = extensions.extensionNamed(name)
        else { return nil }
        return owner.assetsPath
    }

    /// 仅包含可选择的行：分组标题会绘制但不会被选中，分隔线同理。
    var rows: [ExtensionScreen.Item] { screen.items }

    /// 表单独占整个键盘：其字段即输入目标，因此搜索框让位。
    var hidesSearchField: Bool { isForm }

    /// 表单或无行的 Detail 即使没有可落选的选中行，也保留其主操作。
    var actsWithoutRows: Bool { isForm || screen.kind == .detail }

    /// 文本域自身用 ↑/↓ 编辑，因此只有 ⇥ 能让它离开。
    func ownsVerticalKeys(at selection: Int) -> Bool {
        guard isForm, rows.indices.contains(selection) else { return false }
        return ExtensionFormField(type: rows[selection].node.type).ownsVerticalKeys
    }

    /// ⇥ / ⇧⇥ 在字段间移动，两端循环，行为与 Raycast 表单一致。
    func tabTarget(from selection: Int, backwards: Bool) -> Int? {
        guard isForm, !rows.isEmpty else { return nil }
        return (selection + (backwards ? -1 : 1) + rows.count) % rows.count
    }

    /// 网格需要同时处理两个轴：否则 ↓ 会逐个横向移动。
    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int? {
        guard case .grid(let layout) = screen.kind, !rows.isEmpty else { return nil }
        switch axis {
        case .vertical:
            let geometry = ExtensionGridGeometry(
                counts: screen.sectionCounts, columns: layout.columns)
            return delta > 0 ? geometry.down(from: selection) : geometry.up(from: selection)
        case .horizontal:
            return min(max(selection + delta, 0), rows.count - 1)
        }
    }

    /// 主操作即面板中的第一个 `Action`。
    private func primaryAction(at selection: Int) -> ExtensionAction? {
        ExtensionScreen.actions(in: screen.actionPanel(forItemAt: selection)).first
    }

    /// 最先遇到的子菜单是分组手段，因此用它的标题代表叶子节点的标题。
    var primaryActionTitle: String {
        let primary = primaryAction(at: vm.selection)
        return primary?.enclosingSubmenuTitle ?? primary?.title ?? "Run"
    }

    /// 判断该行是否存在可执行的主操作。
    func hasPrimaryAction(at selection: Int) -> Bool { primaryAction(at: selection) != nil }

    /// 表单通常只有一个 Submit 操作，仅有单行的 ⌘K 面板相对其按钮是多余的。
    func hasActions(at selection: Int) -> Bool {
        guard isForm else { return true }
        return ExtensionScreen.actions(in: screen.actionPanel(forItemAt: selection)).count > 1
    }

    /// 表单的按钮即使没有可落选的字段也存在：该操作属于整个界面。
    var isForm: Bool {
        if case .form = screen.kind { return true }
        return false
    }

    /// 命令的行带有着色图标且其面板可滚动，菜单行则不能。
    func menuContent(
        at selection: Int, searchQuery: ActionMenuSearchQuery, menuSelection: Binding<Int>,
        onActivate: @escaping (Int) -> Void
    ) -> PaletteMenuContent? {
        let actions = ExtensionScreen.actions(in: screen.actionPanel(forItemAt: selection))
        guard !actions.isEmpty else { return nil }
        var pendingSection = false
        var filteredActions: [ExtensionAction] = []
        var filteredSectionStarts: [Bool] = []
        var bestMatch: (index: Int, score: Int)?
        for action in actions {
            if action.startsSection { pendingSection = true }
            guard let score = searchQuery.score(action.title) else { continue }
            filteredSectionStarts.append(pendingSection && !filteredActions.isEmpty)
            filteredActions.append(action)
            pendingSection = false
            if score > (bestMatch?.score ?? .min) {
                bestMatch = (filteredActions.count - 1, score)
            }
        }
        let screen = screen
        let assetsPath = assetsPath
        let extensions = extensions
        var items = ExtensionActionsMenu.rows(filteredActions, assetsPath: assetsPath)
        for index in items.indices { items[index].startsSection = filteredSectionStarts[index] }
        return PaletteMenuContent(
            rowCount: filteredActions.count, preferredSelection: bestMatch?.index,
            view: { _ in
                AnyView(
                    ExtensionActionsPanel(
                        header: ExtensionActionsMenu.header(screen: screen, selection: selection),
                        items: items, selection: menuSelection, onActivate: onActivate,
                        shortcutRow: { key, modifiers in
                            filteredActions.firstIndex { $0.matches(key: key, modifiers: modifiers) }
                        }))
            },
            activate: { index in
                guard let handler = filteredActions[index].handler else { return }
                extensions.dispatch(handler: handler)
            },
            clipPath: { bounds, metrics, _ in
                UnevenRoundedRectangle(
                    topLeadingRadius: metrics.radius.menuPanel,
                    bottomLeadingRadius: metrics.radius.menuPanel,
                    bottomTrailingRadius: metrics.size.menuButton / 2,
                    topTrailingRadius: metrics.radius.menuPanel,
                    style: .continuous
                ).path(in: bounds).cgPath
            },
            motion: ExtensionMenuMotion.panel)
    }

    func activate(at selection: Int) {
        guard let primary = primaryAction(at: selection) else { return }
        if primary.enclosingSubmenuTitle != nil {
            vm.selection = selection
            openActions()
            return
        }
        guard let handler = primary.handler else { return }
        extensions.dispatch(handler: handler)
    }

    /// 扩展命令不支持次要操作（右键）。
    func secondary(at selection: Int) -> Bool { false }

    /// `searchBarAccessory` 下拉；为空的既不显示也不可打开，因此视为无。
    var searchAccessory: ExtensionSearchAccessory? {
        guard let accessory = ExtensionSearchAccessory(node: screen.searchBarAccessory),
            !accessory.items.isEmpty
        else { return nil }
        return accessory
    }

    /// 对应的表头控件；作为不透明盒子，Palette 仅负责放置与开关。
    func searchAccessoryButton(
        _ accessory: ExtensionSearchAccessory, isOpen: Bool, action: @escaping () -> Void
    ) -> AnyView {
        AnyView(
            ExtensionSearchAccessoryButton(
                accessory: accessory, value: extensions.accessorySelection(accessory),
                assetsPath: assetsPath, isOpen: isOpen, action: action))
    }

    /// 将其选项作为 Palette 菜单呈现，从而免费获得方向键、↵、Escape 与点击外部关闭的行为。
    func searchAccessoryMenu(
        searchQuery: ActionMenuSearchQuery, menuSelection: Binding<Int>,
        onActivate: @escaping (Int) -> Void
    ) -> PaletteMenuContent? {
        guard let accessory = searchAccessory else { return nil }
        var items: [ExtensionPickerItem] = []
        var bestMatch: (index: Int, score: Int)?
        for item in accessory.items {
            guard let score = searchQuery.score(item.title) else { continue }
            items.append(item)
            if score > (bestMatch?.score ?? .min) {
                bestMatch = (items.count - 1, score)
            }
        }
        let chosen = extensions.accessorySelection(accessory).map { Set([$0]) } ?? []
        let assetsPath = assetsPath
        let extensions = extensions
        return PaletteMenuContent(
            rowCount: items.count, preferredSelection: bestMatch?.index,
            view: { _ in
                AnyView(
                    ExtensionPickerList(
                        items: items, selection: menuSelection.wrappedValue,
                        chosen: chosen, assetsPath: assetsPath,
                        width: ExtensionSearchAccessoryButton.listWidth,
                        searchPlaceholder: "Search…", onSelect: onActivate,
                        onHighlight: { menuSelection.wrappedValue = $0 }))
            },
            activate: { index in
                extensions.chooseAccessorySelection(accessory, value: items[index].value)
            },
            clipPath: { bounds, metrics, _ in
                RoundedRectangle(cornerRadius: metrics.radius.menuPanel, style: .continuous)
                    .path(in: bounds).cgPath
            },
            motion: ExtensionMenuMotion.panel)
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            ExtensionCommandView(
                screen: screen,
                state: extensions.state,
                selection: selection,
                assetsPath: assetsPath,
                scroll: scroll,
                onSelect: { vm.selection = $0 },
                onActivate: { activate(at: $0) },
                onActions: { index in
                    vm.selection = index
                    openActions()
                },
                onFieldChange: { field, value in
                    guard let handler = field.handler("onGearMacChange") else { return }
                    extensions.dispatch(handler: handler, arguments: [value])
                }
            ))
    }

    /// 在 Palette 自身处理之前先行匹配；有操作触发时返回 true。
    func dispatchShortcut(key: KeyEquivalent, modifiers: EventModifiers, at selection: Int) -> Bool {
        let actions = ExtensionScreen.actions(in: screen.actionPanel(forItemAt: selection))
        guard
            let handler = actions.first(where: { $0.matches(key: key, modifiers: modifiers) })?
                .handler
        else { return false }
        extensions.dispatch(handler: handler)
        return true
    }
}
