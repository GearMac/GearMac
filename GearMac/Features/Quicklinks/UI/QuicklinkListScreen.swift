// 文件职责：「搜索快捷链接」命令面板屏幕，提供按搜索框过滤的列表、行操作菜单与 ⌘⌫/⌘. 快捷键，并组装头部的参数输入条。
// 分层：UI；通过 `QuicklinkStore` 读数据、经 `QuicklinkCoordinator` 执行所有写与打开动作，不在 UI 内含业务规则。
import SwiftUI

/// 「搜索快捷链接」屏幕：库按搜索框过滤，置顶条目优先。
struct QuicklinkListScreen: PaletteScreen {
    let store: QuicklinkStore
    let core: AppCore
    let vm: PaletteState

    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }
    let openActions: () -> Void
    /// 按参数名打开命令面板自带的菜单，用于 `options=` 字段。
    let openArgumentOptions: (String) -> Void

    /// 当前可见的行：搜索词为空时列出全部已启用条目，否则按名称不区分大小写过滤。
    var rows: [Quicklink] {
        let query = vm.query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return store.enabled }
        return store.enabled.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// 主操作按钮标题（↵ 打开快捷链接）。
    var primaryActionTitle: String { core.settings.text(QuicklinksKey.listOpen) }

    /// 按选中下标取出对应的快捷链接，越界时返回 nil。
    private func quicklink(at selection: Int) -> Quicklink? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    /// 构建该行的 ⌘K 操作菜单，并带上头部已输入的参数值。
    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let quicklink = quicklink(at: selection) else { return nil }
        return QuicklinkActionsMenu.content(
            quicklink: quicklink, core: core,
            values: QuicklinkArgumentsAccessory.values(for: quicklink, core: core, vm: vm))
    }

    /// ↵：带上头部参数字段的值打开选中的快捷链接。
    func activate(at selection: Int) {
        guard let quicklink = quicklink(at: selection) else { return }
        core.quicklinkCoordinator.openQuicklink(
            id: quicklink.id,
            values: QuicklinkArgumentsAccessory.values(for: quicklink, core: core, vm: vm))
    }

    /// 头部的参数输入条，也是模板化链接收集所需值的地方。
    func headerAccessory(
        at selection: Int, focus: FocusState<String?>.Binding
    ) -> PaletteHeaderAccessory? {
        QuicklinkArgumentsAccessory.make(
            quicklink: quicklink(at: selection), core: core, vm: vm, focus: focus,
            placement: .besideSearchField, onOpenOptions: openArgumentOptions,
            onSubmit: { activate(at: selection) })
    }

    /// ⌘↵ 绕过已保存的「打开方式」应用；未设置时则无可绕过的东西。
    func secondary(at selection: Int) -> Bool {
        guard let quicklink = quicklink(at: selection), quicklink.openWithBundleID != nil else {
            return false
        }
        core.quicklinkCoordinator.openQuicklink(
            id: quicklink.id, forcingDefaultApp: true,
            values: QuicklinkArgumentsAccessory.values(for: quicklink, core: core, vm: vm))
        return true
    }

    /// 处理该屏幕支持的额外快捷键；未处理的返回 false。
    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .commandDelete: return delete(at: selection)
        case .pin: return pin(at: selection)
        default: return false
        }
    }

    /// ⌘. —— 与操作菜单中的对应行一致；置顶会把该行提升到「置顶」分组。
    private func pin(at selection: Int) -> Bool {
        guard let quicklink = quicklink(at: selection) else { return false }
        core.quicklinkCoordinator.toggleQuicklinkPinned(id: quicklink.id)
        return true
    }

    /// ⌘⌫ —— 删除会遵循 `AppCore` 中的「删除前确认」设置。
    private func delete(at selection: Int) -> Bool {
        guard let quicklink = quicklink(at: selection) else { return false }
        Task { await core.quicklinkCoordinator.deleteQuicklink(id: quicklink.id) }
        return true
    }

    /// 屏幕主体：委托给 `content`，并包装为 `AnyView`。
    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    /// 行列表为空时显示空状态，否则展示两栏布局（左侧列表 + 分隔线 + 右侧预览）。
    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        if rows.isEmpty {
            EmptyResults(
                text: store.enabled.isEmpty
                    ? core.settings.text(QuicklinksKey.listEmpty)
                    : core.settings.text(QuicklinksKey.listNoMatch))
        } else {
            let selected = quicklink(at: selection)
            HStack(spacing: 0) {
                QuicklinkList(
                    results: rows, selectedID: selected?.id, scroll: scroll,
                    onSelect: { link in
                        if let index = rows.firstIndex(of: link) { vm.selection = index }
                    },
                    onActivate: { activate(at: vm.selection) },
                    onActions: { link in
                        if let index = rows.firstIndex(of: link) { vm.selection = index }
                        openActions()
                    }
                )
                .frame(width: metrics.size.clipboardListWidth)
                Rectangle().fill(Theme.Colors.separator).frame(width: Theme.Size.hairline)
                QuicklinkPreview(quicklink: selected)
            }
        }
    }
}

/// 快捷链接行的 ⌘K 菜单。
@MainActor
enum QuicklinkActionsMenu {
    /// `values` 是头部的参数字段，因此菜单项会带上与 ↵ 相同的参数打开。
    static func content(
        quicklink: Quicklink, core: AppCore, values: [String: String]
    ) -> PopoverMenuContent {
        var items: [PopoverMenuItem] = [
            PopoverMenuItem(
                title: core.settings.text(QuicklinksKey.listOpen), systemImage: quicklink.symbol,
                shortcut: "↵"
            ) {
                core.quicklinkCoordinator.openQuicklink(id: quicklink.id, values: values)
            }
        ]
        // 扁平菜单没有选择器，因此命令面板只提供绕过系统默认处理器的选项。
        if quicklink.openWithBundleID != nil {
            items.append(
                PopoverMenuItem(
                    title: core.settings.text(QuicklinksKey.actionOpenWithDefault),
                    systemImage: "arrow.up.forward.app",
                    shortcut: "⌘↵"
                ) {
                    core.quicklinkCoordinator.openQuicklink(
                        id: quicklink.id, forcingDefaultApp: true, values: values)
                })
        }
        items.append(
            PopoverMenuItem(
                title: core.settings.text(QuicklinksKey.editQuicklink), systemImage: "pencil",
                startsSection: true
            ) {
                core.paletteCoordinator.hidePalette(restoreFocus: false)
                core.quicklinkCoordinator.editQuicklink(quicklink)
            })
        items.append(
            PopoverMenuItem(
                title: core.settings.text(QuicklinksKey.actionDuplicate),
                systemImage: "plus.square.on.square"
            ) {
                core.quicklinkCoordinator.duplicateQuicklink(id: quicklink.id)
            })
        items.append(
            quicklink.isPinned
                ? PopoverMenuItem(
                    title: core.settings.text(QuicklinksKey.actionUnpin),
                    systemImage: "pin.slash", startsSection: true,
                    shortcut: "⌘."
                ) {
                    core.quicklinkCoordinator.toggleQuicklinkPinned(id: quicklink.id)
                }
                : PopoverMenuItem(
                    title: core.settings.text(QuicklinksKey.actionPin), systemImage: "pin",
                    startsSection: true, shortcut: "⌘."
                ) {
                    core.quicklinkCoordinator.toggleQuicklinkPinned(id: quicklink.id)
                })
        items.append(
            PopoverMenuItem(
                title: quicklink.showsInRootSearch
                    ? core.settings.text(QuicklinksKey.actionHideFromRoot)
                    : core.settings.text(QuicklinksKey.actionShowInRoot),
                systemImage: quicklink.showsInRootSearch ? "eye.slash" : "eye"
            ) {
                core.quicklinkCoordinator.setQuicklinkShowsInRootSearch(
                    !quicklink.showsInRootSearch, id: quicklink.id)
            })
        // 在 Finder 中显示需要真实路径，而模板在展开前并没有路径。
        if case .path(let path)? = QuicklinkDestination.detect(quicklink.link),
            !QuicklinkDestination.containsPlaceholder(quicklink.link)
        {
            items.append(
                PopoverMenuItem(
                    title: core.settings.text(QuicklinksKey.showInFinder), systemImage: "folder",
                    startsSection: true, shortcut: "⌘F"
                ) {
                    core.paletteCoordinator.hidePalette(restoreFocus: false)
                    AppLauncher.showInFinder(URL(fileURLWithPath: path))
                })
        }
        items.append(
            PopoverMenuItem(
                title: core.settings.text(QuicklinksKey.deleteQuicklink), systemImage: "trash",
                startsSection: true, shortcut: "⌘⌫",
                isDestructive: true
            ) {
                Task { await core.quicklinkCoordinator.deleteQuicklink(id: quicklink.id) }
            })
        return PopoverMenuContent(header: quicklink.name, items: items)
    }
}
