// 文件职责：表情与符号选择器界面，把分区网格、固定/常用分区、粘贴与缩放等动作接到 PaletteScreen 上。
// 分层：UI；实现 PaletteScreen，所有投递动作转发给 EmojiCoordinator。
import SwiftUI

/// 表情与符号选择器：分区网格，↑/↓ 按视觉行移动而非按索引。
struct EmojiScreen: PaletteScreen {
    let index: EmojiIndex
    let frequent: FrequentEmojiStore
    let pinned: PinnedEmojiStore
    let core: AppCore
    let vm: PaletteState
    let tone: EmojiSkinTone
    let defaultColumns: EmojiGridColumns
    let openActions: () -> Void

    /// 当前列数：会话内的缩放覆盖值优先于默认列数。
    private var columns: EmojiGridColumns {
        vm.emojiGridColumnsOverride ?? defaultColumns
    }

    /// 网格实际展示的固定项；目录中不存在的已存字形不得影响任何位置。
    private var visiblePins: [String] {
        pinned.glyphs.filter { index.entry(for: $0) != nil }
    }

    /// 当前是否处于浏览状态（无搜索词）。
    private var isBrowsing: Bool {
        vm.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 固定分区在这里排在首位，因此固定项的位次同时就是它的扁平选中索引。
    private var pinsLeadGrid: Bool {
        isBrowsing && (vm.emojiCategoryFilter == .all || vm.emojiCategoryFilter == .pinned)
    }

    /// 当前按筛选条件与查询词计算出的全部网格分区。
    private var sections: [EmojiGridSection] {
        EmojiGrid.sections(
            query: vm.query, index: index, frequent: frequent, pinned: pinned,
            filter: vm.emojiCategoryFilter, columns: columns, language: core.settings.language)
    }

    /// 跨分区的扁平网格顺序——选中索引所指向的序列。
    var rows: [EmojiEntry] { sections.flatMap(\.entries) }

    var primaryActionTitle: String {
        vm.pasteTarget?.pasteTitle ?? core.settings.text(EmojiKey.actionPaste)
    }

    /// 取扁平索引对应的词条；越界时返回 nil。
    private func entry(at selection: Int) -> EmojiEntry? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    /// 当前单元格的右键菜单内容，包含粘贴、拷贝、固定与缩放动作。
    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let entry = entry(at: selection) else { return nil }
        let pins = visiblePins
        return EmojiActionsMenu.content(
            entry: entry, core: core, target: vm.pasteTarget,
            pinPosition: pins.firstIndex(of: entry.glyph), pinCount: pins.count,
            canZoom: { columns.applying($0, default: defaultColumns) != nil },
            togglePin: { togglePin(entry) },
            movePin: { movePin(entry, by: $0) },
            zoom: zoom)
    }

    /// 主操作：粘贴选中的表情。
    func activate(at selection: Int) {
        guard let entry = entry(at: selection) else { return }
        core.emojiCoordinator.pasteEmoji(entry)
    }

    /// 次操作：拷贝选中的表情到剪贴板。
    func secondary(at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        core.emojiCoordinator.copyEmoji(entry)
        return true
    }

    /// ⌥↵ —— 面板保持打开，可连续投递一批表情而无需重新呼出。
    func pasteKeepingWindowOpen(at selection: Int) -> Bool {
        guard let entry = entry(at: selection) else { return false }
        core.emojiCoordinator.pasteEmojiKeepingWindowOpen(entry)
        return true
    }

    /// 处理面板快捷键；当前仅响应固定键，其余返回 false。
    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        guard shortcut == .pin, let entry = entry(at: selection) else { return false }
        togglePin(entry)
        return true
    }

    /// ⌥⌘↑/↓：当选中单元格已被固定时，在固定列表内平移它。
    func movePin(_ delta: Int, at selection: Int) {
        guard let entry = entry(at: selection) else { return }
        movePin(entry, by: delta)
    }

    /// 执行缩放；回到默认列数时清除会话内覆盖值。
    func zoom(_ zoom: EmojiGridZoom) {
        guard let next = columns.applying(zoom, default: defaultColumns) else { return }
        vm.emojiGridColumnsOverride = next == defaultColumns ? nil : next
    }

    /// 不受筛选与查询影响，因此只有一次使用或密度变化才会重写它。
    var frequentlyUsed: [String] {
        EmojiGrid.frequentlyUsed(frequent, in: index, columns: columns).map(\.glyph)
    }

    /// 常用分区内容变化后，把选中项跟随着平移，必要时钳位。
    func frequentlyUsedChanged(from old: [String], to new: [String]) {
        guard isBrowsing else { return }
        let start: Int
        switch vm.emojiCategoryFilter {
        case .all: start = visiblePins.count
        case .frequentlyUsed: start = 0
        case .pinned, .category: return
        }
        vm.selection = EmojiGridGeometry.selection(
            vm.selection, afterSectionAt: start, changesFrom: old, to: new)
    }

    /// 纵向移动一个视觉行，到边界时按列溢出到相邻分区；横向只移动一格。
    func move(_ delta: Int, axis: PaletteAxis, from selection: Int) -> Int? {
        let sections = sections
        let count = sections.reduce(0) { $0 + $1.entries.count }
        guard count > 0 else { return selection }
        switch axis {
        case .vertical:
            let geometry = EmojiGridGeometry(
                counts: sections.map(\.entries.count), columns: columns.rawValue)
            return delta > 0 ? geometry.down(from: selection) : geometry.up(from: selection)
        case .horizontal:
            return min(max(selection + delta, 0), count - 1)
        }
    }

    /// 主体内容入口，转发给带 @ViewBuilder 的 `content`。
    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    /// 按加载中/无结果/有结果三种状态渲染主体内容。
    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let sections = sections
        if !index.isLoaded {
            EmptyResults(text: core.settings.text(EmojiKey.emptyLoading))
        } else if sections.isEmpty {
            EmptyResults(text: core.settings.text(EmojiKey.emptyNoResults))
        } else {
            EmojiGridView(
                sections: sections,
                selection: selection,
                tone: tone,
                columns: columns,
                scroll: scroll,
                onSelect: { vm.selection = $0 },
                onActivate: { activate(at: vm.selection) },
                onActions: { flat in
                    vm.selection = flat
                    openActions()
                }
            )
        }
    }

    /// 切换固定状态，并按受影响的分区调整选中位置。
    private func togglePin(_ entry: EmojiEntry) {
        let position = visiblePins.firstIndex(of: entry.glyph)
        pinned.toggle(entry.glyph)
        if let position, pinsLeadGrid, vm.selection == position {
            // 滑入该位置的邻居接管选中，而不是目录中的副本。
            vm.selection = EmojiGridGeometry.selectionAfterRemovingPin(
                at: position, remainingCount: visiblePins.count)
        } else if isBrowsing, vm.emojiCategoryFilter == .all {
            vm.selection = max(vm.selection + (position == nil ? 1 : -1), 0)
        } else if vm.emojiCategoryFilter == .pinned {
            vm.selection = min(vm.selection, max(rows.count - 1, 0))
        }
    }

    /// 将固定项在固定列表内平移一格；越界时不动作。
    private func movePin(_ entry: EmojiEntry, by delta: Int) {
        let pins = visiblePins
        guard let position = pins.firstIndex(of: entry.glyph),
            pins.indices.contains(position + delta)
        else { return }
        pinned.swap(entry.glyph, with: pins[position + delta])
        if pinsLeadGrid, vm.selection == position { vm.selection = position + delta }
    }
}

/// 单元格的动作菜单，右键时像 `ClipboardActionsMenu` 一样在右下角弹出。
@MainActor
enum EmojiActionsMenu {
    /// 根据当前词条与固定位置生成菜单内容（粘贴、拷贝、固定与缩放）。
    static func content(
        entry: EmojiEntry, core: AppCore, target: PasteTarget?, pinPosition: Int?, pinCount: Int,
        canZoom: (EmojiGridZoom) -> Bool, togglePin: @escaping () -> Void,
        movePin: @escaping (Int) -> Void, zoom: @escaping (EmojiGridZoom) -> Void
    )
        -> PopoverMenuContent
    {
        let noun = entry.category.localizedItemTitle(core.settings.language)
        var items = [
            PopoverMenuItem(
                title: target?.pasteTitle ?? core.settings.text(EmojiKey.actionPaste),
                icon: .paste(target, fallback: "doc.on.clipboard"), shortcut: "↵"
            ) {
                core.emojiCoordinator.pasteEmoji(entry)
            },
            PopoverMenuItem(
                title: core.settings.text(EmojiKey.actionCopyToClipboard),
                systemImage: "doc.on.doc", shortcut: "⌘↵"
            ) {
                core.emojiCoordinator.copyEmoji(entry)
            },
            PopoverMenuItem(
                title: core.settings.text(EmojiKey.actionPasteAndKeepOpen),
                icon: .paste(target, fallback: "macwindow"), shortcut: "⌥↵"
            ) {
                core.emojiCoordinator.pasteEmojiKeepingWindowOpen(entry)
            },
            PopoverMenuItem(
                title: String(
                    format: core.settings.text(
                        pinPosition == nil ? EmojiKey.actionPinFormat : EmojiKey.actionUnpinFormat),
                    noun),
                systemImage: pinPosition == nil ? "pin" : "pin.slash",
                startsSection: true, shortcut: "⌘.", action: togglePin)
        ]
        if let pinPosition {
            items.append(
                PopoverMenuItem(
                    title: core.settings.text(EmojiKey.actionMoveUp), systemImage: "arrow.up",
                    isEnabled: pinPosition > 0, shortcut: "⌥⌘↑"
                ) { movePin(-1) })
            items.append(
                PopoverMenuItem(
                    title: core.settings.text(EmojiKey.actionMoveDown), systemImage: "arrow.down",
                    isEnabled: pinPosition < pinCount - 1, shortcut: "⌥⌘↓"
                ) { movePin(1) })
        }
        items.append(contentsOf: [
            PopoverMenuItem(
                title: core.settings.text(EmojiKey.actionActualSize),
                systemImage: "magnifyingglass",
                isEnabled: canZoom(.actualSize), startsSection: true, shortcut: "⌘0"
            ) { zoom(.actualSize) },
            PopoverMenuItem(
                title: core.settings.text(EmojiKey.actionZoomIn), systemImage: "plus.magnifyingglass",
                isEnabled: canZoom(.zoomIn), shortcut: "⌘+"
            ) { zoom(.zoomIn) },
            PopoverMenuItem(
                title: core.settings.text(EmojiKey.actionZoomOut),
                systemImage: "minus.magnifyingglass",
                isEnabled: canZoom(.zoomOut), shortcut: "⌘-"
            ) { zoom(.zoomOut) }
        ])
        return PopoverMenuContent(header: entry.displayName, items: items)
    }
}
