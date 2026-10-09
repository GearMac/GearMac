// 文件职责：「搜索文件」的结果列表与单行视图：滚动跟随选中、拖动导出、图标异步加载与无障碍标签。
// 分层：UI；SwiftUI 视图，通过闭包向上层回调。
import SwiftUI

/// 「搜索文件」结果列表。
struct FileSearchList: View {

    @Environment(\.metrics) private var metrics
    let title: String
    let results: [FileSearchResult]
    let selectedID: FileSearchResult.ID?
    let scroll: ScrollIntent
    let onSelect: (FileSearchResult) -> Void
    let onActivate: (FileSearchResult) -> Void
    let onActions: (FileSearchResult) -> Void
    let onDropped: () -> Void

    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == results.first?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    SectionHeader(title: title, isFirst: true)
                    ForEach(results) { result in
                        FileSearchRow(result: result, selected: result.id == selectedID)
                            .selectionFrame(result.id == selectedID)
                            .contentShape(Rectangle())
                            .onRowClick(
                                select: { onSelect(result) }, activate: { onActivate(result) },
                                drag: drag(for: result)
                            )
                            .onRightClick { onActions(result) }
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
        .onDisappear { IconCache.purgeFitted() }
    }

    /// 该行自身已适配尺寸的图标，指针能到达时它已被预热。
    private func drag(for result: FileSearchResult) -> RowDrag {
        RowDrag(
            item: { .file(result.url, image: IconCache.cachedFitted(forFile: result.id)) },
            dropped: onDropped)
    }
}

/// 结果列表中的单行：图标、标签与选中/悬停背景。
private struct FileSearchRow: View {

    @Environment(\.metrics) private var metrics
    let result: FileSearchResult
    let selected: Bool
    @State private var image: NSImage?
    @State private var hovered = false

    /// 初始化时先取缓存图标，避免首帧空自。
    init(result: FileSearchResult, selected: Bool) {
        self.result = result
        self.selected = selected
        _image = State(initialValue: IconCache.cachedFitted(forFile: result.id))
    }

    /// 当前行背景色：选中优先，其次是悬停，否则透明。
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    /// 文件夹用它的所在位置来标识：一半的命中都是某个 `src` 或 `GearMac`。
    private var label: Text {
        guard result.isDirectory, !result.parentName.isEmpty else { return Text(result.name) }
        let parent = Text("\(result.parentName)/").foregroundStyle(.secondary)
        return Text("\(parent)\(result.name)")
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            Group {
                if let image {
                    Image(nsImage: image).resizable()
                } else {
                    RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous)
                        .fill(Theme.Colors.iconPlaceholder)
                }
            }
            .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            // 这一列太窄，放不下名称旁边的路径；改由预览区展示。
            label
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(result.name)
        .accessibilityValue(result.parentPath)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .task(id: IconRequest(result.id)) {
            if let warm = IconCache.cachedFitted(forFile: result.id) {
                image = warm
                return
            }
            image = await IconCache.loadFittedAsync(forFile: result.id)
        }
    }
}
