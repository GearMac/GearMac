// 文件职责：渲染菜单搜索结果列表，按菜单分组或在搜索时作为整体结果排序展示。
// 分层：UI；纯 SwiftUI 视图，通过回调向上传递激活意图，自身不访问 AX。
import SwiftUI

/// 菜单搜索结果列表：按菜单分组展示行，并在搜索时把行当作一组结果展示。
struct MenuSearchList: View {

    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    let items: [MenuSearchItem]
    let targetName: String
    /// 已排序的行按得分顺序到达，因此渲染为一组连续结果而非按菜单分组。
    let isSearching: Bool
    let iconURL: URL?
    let iconStamp: Int
    let selectedID: MenuSearchItem.ID?
    let scroll: ScrollIntent
    let onActivate: (MenuSearchItem) -> Void

    /// 整个列表共用一个位图；每一行都绘制同一个冻结的应用图标。
    @State private var icon: NSImage?

    /// 列表中的一个分组：标题加同一菜单下的连续行。
    private struct Section: Identifiable {
        let id: Int
        let title: String
        let items: ArraySlice<MenuSearchItem>
    }

    /// 分组标题：标题加条目数量。
    private func label(for section: Section) -> String {
        let count = section.items.count
        return count == 1
            ? String(format: settings.text(MenuSearchKey.sectionLabelOne), section.title)
            : String(format: settings.text(MenuSearchKey.sectionLabelMany), section.title, count)
    }

    /// 遍历时同一菜单的叶子是连续的，因此分组无需重排行序。
    private var sections: [Section] {
        guard !isSearching else {
            return [Section(id: 0, title: settings.text(MenuSearchKey.results), items: items[...])]
        }
        var sections: [Section] = []
        var start = items.startIndex
        while start < items.endIndex {
            let menu = items[start].menu
            var end = items.index(after: start)
            while end < items.endIndex, items[end].menu == menu { end = items.index(after: end) }
            sections.append(
                Section(
                    id: sections.count, title: menu.isEmpty ? targetName : menu,
                    items: items[start..<end]))
            start = end
        }
        return sections
    }

    /// 首行是否即当前选中行，用于滚动定位。
    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == items.first?.id
    }

    /// 图标缓存键：URL 与时间戳的组合。
    private var iconKey: String { "\(iconURL?.path ?? "")|\(iconStamp)" }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sections) { section in
                        SectionHeader(title: label(for: section), isFirst: section.id == 0)
                        ForEach(section.items) { item in
                            MenuSearchRow(
                                item: item, path: isSearching ? item.menuPath : item.submenuPath,
                                icon: icon, selected: item.id == selectedID
                            )
                            .selectionFrame(item.id == selectedID)
                            .contentShape(Rectangle())
                            .onTapGesture { onActivate(item) }
                        }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedID, atOrigin: firstRowSelected, proxy: proxy)
        }
        // 以图标为键，使外观变化时重新解码，而不是沿用旧的位图。
        .task(id: IconRequest(iconKey)) {
            guard let iconURL else { return }
            if let warm = IconCache.cached(.file(stamp: iconStamp), fileURL: iconURL) {
                icon = warm
                return
            }
            icon = await IconCache.loadAsync(.file(stamp: iconStamp), fileURL: iconURL)
        }
    }
}

/// 单条菜单项行：图标、标题、路径与快捷键。
private struct MenuSearchRow: View {

    @Environment(\.metrics) private var metrics
    let item: MenuSearchItem
    let path: String
    let icon: NSImage?
    let selected: Bool
    @State private var hovered = false

    /// 行的背景色：选中优先，其次悬停，否则透明。
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable()
                } else {
                    RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous)
                        .fill(Theme.Colors.iconPlaceholder)
                }
            }
            .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            Text(item.title)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
                .layoutPriority(1)
            if !path.isEmpty {
                Text(path)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: metrics.spacing.md)
            let caps = item.shortcut?.keycaps ?? []
            if !caps.isEmpty {
                HStack(spacing: metrics.spacing.xxs) {
                    ForEach(caps, id: \.self) { cap in
                        KeyCapChip(text: cap, style: .outline)
                    }
                }
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.displayPath)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
