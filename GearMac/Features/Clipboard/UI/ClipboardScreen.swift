// 文件职责：剪贴板浏览界面，以底部横条呈现类型标签与卡片行，并定义条目的动作菜单。
// 分层：UI；实现 PaletteScreen，读取 ClipboardStore 并通过 ClipboardCoordinator 执行动作。
import SwiftUI

/// 剪贴板浏览器：筛选后的列表位于选中条目预览的一侧。
struct ClipboardScreen: PaletteScreen {
    let store: ClipboardStore
    let core: AppCore
    let vm: PaletteState

    /// 右键路径：携带被点卡片的全局坐标，菜单悬挂在卡片正上方。
    let openActionsAt: (CGRect) -> Void
    /// 打开「标签」筛选菜单。
    let openTagFilterMenu: () -> Void
    /// 打开最右侧的剪贴板设置菜单。
    let openSettingsMenu: () -> Void
    /// 真实搜索框，由根视图惰性注入：在设置按钮左侧展示。
    /// 必须是闭包而非立即求值：字段视图链会读取 `screen`，急切求值会在构建
    /// `ClipboardScreen` 时与 `screen` 互相构建成无限递归。
    let searchField: () -> AnyView
    /// 动作菜单中的打标签行进入二级菜单。
    let onTagEntry: (ClipboardItem) -> Void
    let scrollToFollow: () -> Void

    /// 按当前查询、类型与标签筛选得到的条目列表。
    var rows: [ClipboardItem] {
        let base = store.search(vm.query, filter: vm.clipboardFilter)
        guard let tag = vm.clipboardTagFilter else { return base }
        return base.filter { $0.tag == tag }
    }

    /// 首次展示时应落位的选中行索引。
    var landingSelection: Int { store.landingIndex(in: vm.query, filter: vm.clipboardFilter) }

    /// 主操作按钮的标题，随默认动作与粘贴目标变化。
    var primaryActionTitle: String {
        let defaultAction = core.settings.clipboardDefaultAction
        let action = item(at: vm.selection).flatMap { defaultAction.action(for: .return, on: $0) }
        return (action ?? defaultAction).localizedTitle(
            pastingInto: vm.pasteTarget, language: core.settings.language)
    }

    /// 返回指定选中位置对应的条目；越界时返回 nil。
    private func item(at selection: Int) -> ClipboardItem? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    /// 返回选中条目的动作菜单内容。
    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let item = item(at: selection) else { return nil }
        return ClipboardActionsMenu.content(
            item: item, core: core, store: store, target: vm.pasteTarget,
            onTagEntry: { onTagEntry(item) })
    }

    /// 对选中条目执行默认动作。
    func activate(at selection: Int) {
        guard let item = item(at: selection) else { return }
        core.clipboardCoordinator.activate(item)
    }

    /// 按快捷键分派到删除、固定、收藏槽位或复制文本等操作。
    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .commandDelete, .delete:
            delete(at: selection)
            return true
        case .deleteAll:
            deleteAll()
            return true
        case .pin: return pin(at: selection)
        case .favoriteSlot(let index): return activatePinned(at: index)
        case .copyText:
            guard let item = item(at: selection), item.offersTextExtraction else { return false }
            core.clipboardCoordinator.copyImageText(item)
            return true
        default: return false
        }
    }

    /// ⌘1…⌘0 —— 第 N 个可见的固定条目（按 Pinned 分区顺序），行为同 ↵。
    private func activatePinned(at index: Int) -> Bool {
        guard let item = store.pinnedItem(at: index, in: vm.query, filter: vm.clipboardFilter) else {
            return false
        }
        core.clipboardCoordinator.activate(item)
        return true
    }

    /// ⌘↵ —— 执行 ↵ 未绑定的那个动作。
    func secondary(at selection: Int) -> Bool {
        guard let item = item(at: selection) else { return false }
        return core.clipboardCoordinator.activate(item, chord: .command)
    }

    /// ⌃⌘↵ —— 以纯文本粘贴；若纯文本已是默认动作则执行普通粘贴。
    func tertiary(at selection: Int) -> Bool {
        guard let item = item(at: selection) else { return false }
        return core.clipboardCoordinator.activate(item, chord: .controlCommand)
    }

    /// ⌥↵ —— 面板保持打开，可以连续发送多条条目而无需重新唤起。
    func pasteKeepingWindowOpen(at selection: Int) -> Bool {
        guard let item = item(at: selection) else { return false }
        core.clipboardCoordinator.pasteKeepingWindowOpen(item)
        return true
    }

    /// ⌘. —— 与动作菜单中的对应项一致；固定会把该行提升到 Pinned 分区。
    private func pin(at selection: Int) -> Bool {
        guard let item = item(at: selection) else { return false }
        core.clipboardCoordinator.togglePinnedClip(item)
        return true
    }

    /// ⌘⌫ / ⌃X —— 无论选中位置下方是否有行，都由本屏处理该快捷键。
    private func delete(at selection: Int) {
        guard let item = item(at: selection) else { return }
        store.remove(item)
    }

    /// ⌃⇧X —— 与动作菜单中的对应项一致且带确认；固定条目也会一并删除。
    private func deleteAll() {
        Task { await core.clipboardCoordinator.deleteAllClips() }
    }

    /// 跟随存储层移动过的行；已输入查询时高亮保持不动。
    private func follow(from old: ClipFollowKey, to new: ClipFollowKey) {
        // `old.id` 为 nil 表示首次加载落位，而非行被移动。
        guard old.id != nil else { return }
        let rows = rows
        if vm.query.trimmingCharacters(in: .whitespaces).isEmpty, old.id != new.id, let id = new.id,
            let index = rows.firstIndex(where: { $0.id == id })
        {
            vm.selection = index
        }
        scrollToFollow()
    }

    /// PaletteScreen 的视图入口，附带跟随移动行的事件绑定。
    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            content(selection: selection, scroll: scroll)
                .onChange(of: ClipFollowKey(id: store.items.first?.id, token: vm.followToken)) {
                    old, new in
                    follow(from: old, to: new)
                }
        )
    }

    /// 构建内容区：空结果展示提示，否则以底部横条展示标签行与卡片行。
    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        // 历史为空：把提示居中显示在整个面板，而不是卡片行内。
        if rows.isEmpty {
            // 提示中带上筛选名，避免某个筛掉全部条目的筛选被误读为空历史。
            EmptyResults(text: emptyMessage)
        } else {
            ClipboardBar(
                results: rows,
                selectedID: item(at: selection)?.id,
                scroll: scroll,
                onSelectFilter: { vm.clipboardFilter = $0 },
                filterActive: vm.clipboardFilter != .all || vm.clipboardTagFilter != nil,
                onClearFilters: {
                    vm.clipboardFilter = .all
                    vm.clipboardTagFilter = nil
                },
                openTagFilterMenu: openTagFilterMenu,
                openSettingsMenu: openSettingsMenu,
                searchField: searchField,
                onSelect: { item in vm.selection = rows.firstIndex(of: item) ?? 0 },
                onActivate: { activate(at: vm.selection) },
                onActions: { item, frame in
                    if let index = rows.firstIndex(of: item) { vm.selection = index }
                    openActionsAt(frame)
                },
                onDragPayload: { core.clipboardCoordinator.dragPayload(for: $0) },
                onDropped: { core.paletteCoordinator.dragLanded() })
        }
    }

    /// 空列表提示：标签筛选优先说明，其次才是类型筛选。
    private var emptyMessage: String {
        if vm.clipboardTagFilter != nil {
            return L10n.string(ClipboardKey.emptyTag, language: core.settings.language)
        }
        return vm.clipboardFilter.emptyMessage(core.settings.language)
    }

    /// ←/→ 在卡片间步进；卡片只有一行，↑/↓ 走默认的线性步进与之一致。
    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int? {
        guard axis == .horizontal else { return nil }
        let count = rows.count
        guard count > 0 else { return nil }
        return min(max(selection + delta, 0), count - 1)
    }
}

/// 「跟随移动行」处理器的变更键，取自存储层而非搜索结果。
private struct ClipFollowKey: Equatable {
    let id: ClipboardItem.ID?
    let token: UUID
}

/// 条目的动作菜单，与 `AppActionsMenu` 一样在右键时显示：只有打标签、粘贴与删除三项。
@MainActor
enum ClipboardActionsMenu {
    /// 为条目构建动作菜单；图片取字仅在条目支持时出现。
    static func content(
        item: ClipboardItem, core: AppCore, store: ClipboardStore, target: PasteTarget?,
        onTagEntry: @escaping () -> Void
    ) -> PopoverMenuContent {
        var items: [PopoverMenuItem] = [
            PopoverMenuItem(
                title: core.settings.text(ClipboardKey.tagEntry), systemImage: "tag"
            ) {
                onTagEntry()
            },
            PopoverMenuItem(
                title: ClipboardDefaultAction.paste.localizedTitle(
                    pastingInto: target, language: core.settings.language),
                icon: .paste(target, fallback: "doc.on.clipboard"),
                shortcut: "↵"
            ) {
                core.clipboardCoordinator.perform(.paste, on: item)
            }
        ]
        if item.offersTextExtraction {
            items.append(
                PopoverMenuItem(
                    title: core.settings.text(ClipboardKey.copyText),
                    systemImage: "doc.text.viewfinder", shortcut: "⇧⌘T"
                ) {
                    core.clipboardCoordinator.copyImageText(item)
                })
        }
        items.append(
            PopoverMenuItem(
                title: core.settings.text(ClipboardKey.deleteEntry), systemImage: "trash",
                startsSection: true, shortcut: "⌃X",
                isDestructive: true
            ) {
                store.remove(item)
            }
        )
        return PopoverMenuContent(
            header: headerText(item, language: core.settings.language), items: items)
    }

    /// 返回菜单标题：文本取其首行摘要，图片与文件取类型名或文件名。
    private static func headerText(_ item: ClipboardItem, language: AppLanguage) -> String {
        switch item.kind {
        case .text:
            // 折叠空白，使多行复制内容成为干净的单行标题。
            let oneLine = (item.text ?? "").split(whereSeparator: \.isWhitespace).joined(
                separator: " ")
            return String(oneLine.prefix(40))
        case .image: return L10n.string(ClipboardKey.typeImage, language: language)
        case .file:
            return (item.filePath as NSString?)?.lastPathComponent
                ?? L10n.string(ClipboardKey.fileKindOther, language: language)
        }
    }
}

extension ClipboardDefaultAction {
    /// 粘贴动作会标明它落入的应用，页脚胶囊与 ⌘K 菜单中一致。
    func localizedTitle(pastingInto target: PasteTarget?, language: AppLanguage) -> String {
        let title = localizedTitle(language)
        guard let target, self != .copy else { return title }
        return String(format: L10n.string(ClipboardKey.pasteToFormat, language: language), target.name)
    }
}
