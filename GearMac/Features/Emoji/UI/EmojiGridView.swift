// 文件职责：表情网格视图及其分区/行/单元格渲染，负责分区内容计算、选中与滚动跟随、悬停和点击交互。
// 分层：UI；只做展示与交互，不直接读写固定/频次存储之外的持久化。
import SwiftUI

/// 一段带标题的网格单元序列；`start` 是其首个单元格的扁平选中索引。
struct EmojiGridSection: Identifiable {
    let title: String
    let entries: [EmojiEntry]
    let start: Int

    var id: String { title }
}

/// 网格分区的组装入口。
enum EmojiGrid {
    /// 搜索时返回排序后的结果，否则按固定、常用、目录分区的顺序拼接。
    @MainActor
    static func sections(
        query: String, index: EmojiIndex, frequent: FrequentEmojiStore,
        pinned: PinnedEmojiStore, filter: EmojiCategoryFilter, columns: EmojiGridColumns,
        language: AppLanguage = .english
    ) -> [EmojiGridSection] {
        var sections: [EmojiGridSection] = []
        var start = 0
        func append(_ title: String, _ entries: [EmojiEntry]) {
            guard !entries.isEmpty else { return }
            sections.append(EmojiGridSection(title: title, entries: entries, start: start))
            start += entries.count
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            switch filter {
            case .all:
                append(
                    L10n.string(EmojiKey.filterPinned, language: language),
                    pinned.glyphs.compactMap(index.entry(for:)))
                append(
                    L10n.string(EmojiKey.filterFrequentlyUsed, language: language),
                    frequentlyUsed(frequent, in: index, columns: columns))
                for section in index.categorySections {
                    append(section.category.localizedTitle(language), section.entries)
                }
            case .pinned:
                append(
                    L10n.string(EmojiKey.filterPinned, language: language),
                    pinned.glyphs.compactMap(index.entry(for:)))
            case .frequentlyUsed:
                append(
                    L10n.string(EmojiKey.filterFrequentlyUsed, language: language),
                    frequentlyUsed(frequent, in: index, columns: columns))
            case .category(let category):
                if let section = index.categorySections.first(where: { $0.category == category }) {
                    append(category.localizedTitle(language), section.entries)
                }
            }
        } else {
            let results = index.search(query, frequent: frequent)
            let filtered: [EmojiEntry]
            switch filter {
            case .all:
                filtered = results
            case .pinned:
                let glyphs = Set(pinned.glyphs)
                filtered = results.filter { glyphs.contains($0.glyph) }
            case .frequentlyUsed:
                let glyphs = Set(frequentlyUsed(frequent, in: index, columns: columns).map(\.glyph))
                filtered = results.filter { glyphs.contains($0.glyph) }
            case .category(let category):
                filtered = results.filter { $0.category == category }
            }
            append(L10n.string(EmojiKey.sectionResults, language: language), filtered)
        }
        return sections
    }

    /// 最新表情的前两行，按目录计数，目录中不存在的字形不占单元格。
    @MainActor
    static func frequentlyUsed(
        _ frequent: FrequentEmojiStore, in index: EmojiIndex, columns: EmojiGridColumns
    ) -> [EmojiEntry] {
        Array(frequent.records.lazy.compactMap { index.entry(for: $0.glyph) }.prefix(columns.rawValue * 2))
    }
}

/// 一行网格单元格；`start` 是其首个单元格的扁平选中索引。
private struct EmojiGridRow: Identifiable {
    let id: String
    let start: Int
    let entries: ArraySlice<EmojiEntry>
    let isLastInSection: Bool

    /// 按列序号取单元格。
    subscript(column: Int) -> EmojiEntry {
        entries[entries.index(entries.startIndex, offsetBy: column)]
    }
}

/// 一次查询的扁平渲染顺序：分区标题与网格行交替排列。
private enum EmojiGridItem: Identifiable {
    case header(id: String, title: String, count: Int)
    case row(EmojiGridRow)

    var id: String {
        switch self {
        case .header(let id, _, _): return id
        case .row(let row): return row.id
        }
    }
}

/// 表情网格主体：把分区列表展开为标题与行，并处理滚动跟随。
struct EmojiGridView: View {

    @Environment(\.metrics) private var metrics
    let sections: [EmojiGridSection]
    /// 跨全部分区的扁平选中索引，与列表模式一致。
    let selection: Int
    let tone: EmojiSkinTone
    let columns: EmojiGridColumns
    /// 待处理的滚动请求；鼠标选择不会触碰它。
    let scroll: ScrollIntent
    let onSelect: (Int) -> Void
    let onActivate: () -> Void
    let onActions: (Int) -> Void

    /// 按可见顺序排列的标题与行；行是滚动目标。docs/features/emoji.md
    private var items: [EmojiGridItem] {
        var items: [EmojiGridItem] = []
        for section in sections {
            items.append(
                .header(
                    id: section.id + "-header", title: section.title,
                    count: section.entries.count))
            var offset = 0
            var row = 0
            while offset < section.entries.count {
                let end = min(offset + columns.rawValue, section.entries.count)
                items.append(
                    .row(
                        EmojiGridRow(
                            id: section.id + "-row-\(row)",
                            start: section.start + offset,
                            entries: section.entries[offset..<end],
                            isLastInSection: end == section.entries.count)))
                offset = end
                row += 1
            }
        }
        return items
    }

    /// 包含选中项的行；ID 带分区前缀，因为不同分区的 row 会重名。
    private var selectedRowID: String? {
        guard let section = sections.last(where: { selection >= $0.start }),
            selection - section.start < section.entries.count
        else { return nil }
        return section.id + "-row-\((selection - section.start) / columns.rawValue)"
    }

    /// 第一个网格行；选中到它时改为回滚到起点，以便一并露出标题。
    private var firstRowID: String? { sections.first.map { $0.id + "-row-0" } }

    var body: some View {
        let items = items
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        switch item {
                        case .header(_, let title, let count):
                            EmojiSectionHeader(
                                title: title, count: count, isFirst: item.id == items.first?.id)
                        case .row(let row):
                            EmojiGridRowView(
                                row: row, selection: selection, tone: tone, columns: columns,
                                onSelect: onSelect, onActivate: onActivate, onActions: onActions
                            )
                            .padding(
                                .bottom,
                                row.isLastInSection ? 0 : metrics.spacing.md
                            )
                            .selectionFrame(item.id == selectedRowID)
                        }
                    }
                }
                .padding(.horizontal, metrics.size.emojiGridInset)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            // 在第一个网格行上回滚到起点，使其标题也一并可见。
            .scrollFollowsSelection(
                scroll, row: selectedRowID, atOrigin: selectedRowID == firstRowID, proxy: proxy
            )
        }
    }
}

/// 计数紧跟在标题后，不改动其他屏幕共用的分区标题样式。
private struct EmojiSectionHeader: View {
    @Environment(\.metrics) private var metrics
    let title: String
    let count: Int
    let isFirst: Bool

    var body: some View {
        HStack(spacing: metrics.spacing.sm) {
            Text(title)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(count, format: .number)
                .foregroundStyle(Theme.Colors.textTertiary)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .font(metrics.typography.sectionHeader)
        .padding(.top, isFirst ? metrics.spacing.xs : metrics.spacing.emojiSectionSpacing)
        .padding(.bottom, metrics.spacing.md)
    }
}

/// 一行网格，负责其单元格的全部交互。参见 docs/features/emoji.md#rendering。
private struct EmojiGridRowView: View {
    @Environment(\.metrics) private var metrics
    let row: EmojiGridRow
    let selection: Int
    let tone: EmojiSkinTone
    let columns: EmojiGridColumns
    let onSelect: (Int) -> Void
    let onActivate: () -> Void
    let onActions: (Int) -> Void

    @Environment(PaletteState.self) private var palette
    @State private var hoveredColumn: Int?

    private var spacing: CGFloat { metrics.spacing.md }

    /// 面板宽度是固定度量，因此单元格可以直接取正方形，无需测量重绘。
    private var cellSize: CGFloat {
        let count = CGFloat(columns.rawValue)
        let contentWidth = metrics.size.panelWidth - metrics.size.emojiGridInset * 2
        return (contentWidth - spacing * (count - 1)) / count
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<columns.rawValue, id: \.self) { column in
                if column < row.entries.count {
                    EmojiCell(
                        glyph: row[column].display(tone: tone),
                        selected: row.start + column == selection,
                        hovered: column == hoveredColumn,
                        size: cellSize
                    )
                } else {
                    // 末尾的空槽使不满的末行与整行对齐。
                    Color.clear.frame(width: cellSize, height: cellSize)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // 单击选中；双击粘贴作为同时手势一并生效。
        .gesture(
            SpatialTapGesture().onEnded { value in
                if let column = column(at: value.location) { onSelect(row.start + column) }
            }
        )
        .simultaneousGesture(
            SpatialTapGesture(count: 2).onEnded { value in
                guard let column = column(at: value.location) else { return }
                onSelect(row.start + column)
                onActivate()
            }
        )
        .onRightClick { point in
            if let column = column(at: point) { onActions(row.start + column) }
        }
        // 列悬停，与 `armedHover` 一样仅在指针真实移动时生效。
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point):
                hoveredColumn = palette.hoverHighlightArmed ? column(at: point) : nil
            case .ended:
                hoveredColumn = nil
            }
        }
        .onChange(of: palette.hoverDisarmToken) { hoveredColumn = nil }
    }

    /// 坐标 → 列号，会排掉单元格之间的间隔与不满行中的空槽。
    private func column(at point: CGPoint) -> Int? {
        guard point.x >= 0 else { return nil }
        let pitch = cellSize + spacing
        let column = Int(point.x / pitch)
        let positionInCell = point.x - CGFloat(column) * pitch
        guard column < row.entries.count, positionInCell <= cellSize else { return nil }
        return column
    }
}

/// 纯内容展示：不含手势、遮罩或悬停跟踪。参见 docs/features/emoji.md#rendering。
private struct EmojiCell: View {
    @Environment(\.metrics) private var metrics
    let glyph: String
    let selected: Bool
    let hovered: Bool
    let size: CGFloat

    /// 当前单元格的底色：选中 > 悬停 > 默认。
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return Theme.Colors.emojiCell
    }

    /// 字形尺寸：按单元格尺寸缩放，并限制在 30–52 之间。
    private var glyphSize: CGFloat { min(max(size * 0.48, 30), 52) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.radius.emojiCell, style: .continuous)
        return ZStack {
            shape.fill(fill)
            if selected {
                // 模糊副本保留字形本身的各种颜色，而不是另外造一层单色。
                selectedHalo
                    .opacity(0.25)
                    .clipShape(shape)
            }
            Text(glyph)
                .font(.system(size: glyphSize))
            if selected {
                shape.strokeBorder(Theme.Colors.emojiSelectionBorder, lineWidth: 2)
                selectedHalo
                    .opacity(0.30)
                    .mask(shape.strokeBorder(lineWidth: 2))
                shape.inset(by: 2)
                    .strokeBorder(Theme.Colors.emojiInnerBorder, lineWidth: 1)
            } else if hovered {
                ZStack {
                    shape.strokeBorder(
                        Theme.Colors.emojiHoverBorder, lineWidth: 2)
                    shape.inset(by: 2)
                        .strokeBorder(Theme.Colors.emojiInnerBorder, lineWidth: 1)
                }
                .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: Theme.Duration.hover), value: hovered)
    }

    /// 先放大再模糊，使多色光晕能覆盖选中格子的每个角。
    private var selectedHalo: some View {
        Text(glyph)
            .font(.system(size: size))
            .scaleEffect(1.6)
            .blur(radius: max(16, size * 0.28))
            .saturation(2)
            .opacity(0.76)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
