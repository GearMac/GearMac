// 文件职责：渲染扩展命令运行时的 ⌘K 操作面板（分组行、快捷键、滚动与悬停选择）。
// 分层：UI；面板打开时自己持有焦点，扩展图标与配色由所属 Feature 提供。
import SwiftUI

/// 限定在文件内部：让行的实际高度与统计行数上限所用的计算读同一个数值。
private struct Metrics {
    /// 由本文件持有而非放进 `DesignSystem`：扩展不会改变启动器界面的尺寸。
    let interface: InterfaceMetrics

    var width: CGFloat { interface.scaled(320) }
    /// 图标槽位加上其留白——行内最高的元素。
    var rowHeight: CGFloat { interface.size.menuIcon + interface.spacing.md * 2 }
    var rowSpacing: CGFloat { 1 }
    var listInset: CGFloat { interface.spacing.md }
    /// 5 行加第 6 行的一半，使较长的面板看起来可滚动，而不是被裁切。
    var visibleRows: CGFloat { 5.5 }
    /// 取整：小数高度会让玻璃边缘落在半个像素上。
    var rowsMaxHeight: CGFloat { (visibleRows * (rowHeight + rowSpacing)).rounded() }
    /// 分组标题行的高度。
    var headerHeight: CGFloat {
        interface.size.menuSectionHeader + interface.spacing.xs * 1.5 + rowSpacing
    }
    /// 精确计算而非实测：受限视口结束在半行处，绝不落在分隔线上；同时返回折行位置。
    func extent(
        items: [ExtensionActionItem], hasHeader: Bool, hairline: CGFloat
    ) -> (content: CGFloat, viewport: CGFloat) {
        let header = hasHeader ? headerHeight : 0
        let capacity = rowsMaxHeight + header
        var offset = header
        var fold: CGFloat = 0
        for (index, item) in items.enumerated() {
            if index > 0 { offset += item.startsSection ? listInset * 2 + hairline : rowSpacing }
            let midRow = (offset + rowHeight / 2).rounded(.down)
            if midRow <= capacity { fold = midRow }
            offset += rowHeight
        }
        return (offset, offset > capacity ? fold : offset)
    }
}

/// 独立类型而非复用 `PopoverMenuItem`：扩展可以指定任意图标并为其着色。
struct ExtensionActionItem {
    let title: String
    let icon: ExtensionImage.Resolved
    var shortcut: String?
    var isDestructive = false
    var startsSection = false
}

/// 运行中命令的 ⌘K 面板；扩展的图标与配色由所属 Feature 持有。
struct ExtensionActionsPanel: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.displayScale) private var displayScale
    var header: String?
    let items: [ExtensionActionItem]
    @Binding var selection: Int
    let onActivate: (Int) -> Void
    let shortcutRow: (KeyEquivalent, EventModifiers) -> Int?

    /// 只有当指针自行移动之后，Palette 才会启用悬停高亮。
    @Environment(PaletteState.self) private var palette
    /// 悬停的行本就可见，滚动反而会让列表在其下方移动。
    @State private var hoverSelection: Int?

    private var panel: Metrics { Metrics(interface: metrics) }
    /// 一个设备像素：1 点宽的分隔线在玻璃材质上显得过重。
    private var hairline: CGFloat { 1 / displayScale }

    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: metrics.radius.menuPanel,
            bottomLeadingRadius: metrics.radius.menuPanel,
            bottomTrailingRadius: metrics.size.menuButton / 2,
            topTrailingRadius: metrics.radius.menuPanel,
            style: .continuous)
        return VStack(spacing: 0) {
            listContent
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(height: hairline)
                .accessibilityHidden(true)
            ExtensionMenuSearchField(
                placeholder: "Search for actions…", height: panel.rowHeight,
                verticalOffset: -metrics.spacing.xxs / 2)
        }
        // 面板打开时保持焦点，因此外层屏幕自身的快捷键不会收到这些按键。
        .onKeyPress(phases: .down) { press in
            guard !press.modifiers.isEmpty,
                let row = shortcutRow(
                    ASCIIKeyboardLayout.keyEquivalent(fallingBackTo: press.key), press.modifiers)
            else { return .ignored }
            onActivate(row)
            return .handled
        }
        .frame(width: panel.width)
        .glassSurface(in: shape)
    }

    @ViewBuilder
    private var listContent: some View {
        if items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                headerLabel
                Text("No Results")
                    .font(metrics.typography.menuRow)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: panel.rowHeight)
            }
            .padding(panel.listInset)
        } else {
            actionRows
        }
    }

    private var actionRows: some View {
        let extent = panel.extent(items: items, hasHeader: header != nil, hairline: hairline)
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 用索引作为 id 是稳定的：面板打开期间行序不会变化。
                    ForEach(items.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 0) {
                            // 置于第一行的点击目标内，使该行滚入可见时标题一并出现。
                            if index == 0 { headerLabel }
                            rowBoundary(before: index)
                            ExtensionActionRow(
                                item: items[index],
                                selected: index == selection,
                                onActivate: { onActivate(index) }
                            )
                            .onContinuousHover { if case .active = $0 { hover(index) } }
                        }
                        .id(index)
                    }
                }
                .padding(.horizontal, panel.listInset)
            }
            // 用 margin 而非 padding：滚动到底时行仍保留内边距，而不会贴到边缘。
            .contentMargins(.vertical, panel.listInset, for: .scrollContent)
            .frame(height: extent.viewport + panel.listInset * 2)
            .scrollBounceBehavior(extent.content > extent.viewport ? .always : .basedOnSize)
            // 用 `never` 而非 `hidden`：hidden 仍会让 AppKit 占用滚动条的装订线。
            .scrollIndicators(.never)
            .onChange(of: selection) {
                let movedByPointer = hoverSelection == selection
                hoverSelection = nil
                guard !movedByPointer else { return }
                // 不指定锚点：只是让该行可见，绝不将列表重新居中到它周围。
                proxy.scrollTo(selection)
            }
        }
    }

    @ViewBuilder
    private var headerLabel: some View {
        if let header {
            Text(header)
                .font(metrics.typography.sectionHeader)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(height: metrics.size.menuSectionHeader, alignment: .leading)
                .padding(.horizontal, metrics.spacing.lg)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.xs / 2)
            Color.clear.frame(height: panel.rowSpacing)
        }
    }

    @ViewBuilder
    private func rowBoundary(before index: Int) -> some View {
        if index > 0, items[index].startsSection {
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(height: hairline)
                .padding(.horizontal, metrics.spacing.md)
                // 使用列表内边距，使行与这条分隔线的距离与其到搜索框分隔线的距离一致。
                .padding(.vertical, panel.listInset)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else if index > 0 {
            Color.clear.frame(height: panel.rowSpacing)
        }
    }

    /// 仅在指针自行移动后才会启用，因此滚动经过时不会点亮任何行。
    private func hover(_ index: Int) {
        guard palette.hoverHighlightArmed, index != selection else { return }
        hoverSelection = index
        selection = index
    }
}

/// 独立实现的行视图而非复用 Palette 的：后者是文件私有的。
private struct ExtensionActionRow: View {
    @Environment(\.metrics) private var metrics
    let item: ExtensionActionItem
    let selected: Bool
    let onActivate: () -> Void

    private var panel: Metrics { Metrics(interface: metrics) }

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: metrics.spacing.md) {
                ExtensionIconView(
                    resolved: item.icon, size: metrics.size.menuIcon, usesMenuSymbolStyle: true)
                Text(item.title)
                    .font(metrics.typography.menuRow)
                    .foregroundStyle(item.isDestructive ? Color.red : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: metrics.spacing.sm)
                if let shortcut = item.shortcut {
                    HStack(spacing: metrics.spacing.xxs) {
                        ForEach(Array(shortcut.enumerated()), id: \.offset) { _, glyph in
                            KeyCapChip(text: String(glyph), style: .outline)
                        }
                    }
                }
            }
            .padding(.horizontal, metrics.spacing.md)
            // 固定高度而非用 padding：上方的高度计算按行计数，因此每行必须是精确的单一高度。
            .frame(
                maxWidth: .infinity, minHeight: panel.rowHeight, maxHeight: panel.rowHeight,
                alignment: .leading
            )
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.menuRow, style: .continuous)
                    .fill(selected ? Theme.Colors.menuHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
