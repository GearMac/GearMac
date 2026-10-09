// 文件职责：渲染选择器下拉的结果列表（样式与 ⌘K 面板一致）以及其中的菜单搜索框。
// 分层：UI；只负责列表绘制与高亮反馈，查询状态由上层控件持有。
import SwiftUI

/// 选择器下拉的结果列表，样式与 ⌘K 面板一致；查询状态由上方控件持有。
struct ExtensionPickerList: View {
    private var form: ExtensionFormMetrics { ExtensionFormMetrics(scale: metrics.scale) }
    @Environment(\.metrics) private var metrics
    @Environment(\.displayScale) private var displayScale
    @Environment(\.isDarkAppearance) private var isDark
    /// 供 `hoverHighlightArmed` 读取：列表恰好落在指针下方时不应点亮任何行。
    @Environment(PaletteState.self) private var palette
    private var menuListInset: CGFloat { metrics.spacing.md }
    let items: [ExtensionPickerItem]
    let selection: Int
    /// 已选择的值；单选选择器传入它持有的那一个。
    let chosen: Set<String>
    let assetsPath: String?
    /// 固定宽度而非固有宽度，使列表不会随行内容变化而抖动。表单内的选择器
    /// 与上方字段宽度对齐；头部下拉挂在 chip 上，因此宽度更窄。
    var width: CGFloat?
    var searchPlaceholder: String?
    let onSelect: (Int) -> Void
    /// 把高亮移动到指针所在行，使鼠标与键盘共用同一处选中状态。
    let onHighlight: (Int) -> Void

    /// 列表主体：可选搜索框，加上行列表（或空态）。
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let searchPlaceholder {
                ExtensionMenuSearchField(
                    placeholder: searchPlaceholder, height: form.popoverRowHeight,
                    verticalOffset: 0)
                Rectangle()
                    .fill(Theme.Colors.separator)
                    // 一个设备像素，与操作面板的细分隔线一致。
                    .frame(height: 1 / displayScale)
                    .accessibilityHidden(true)
            }
            list
                .padding(searchPlaceholder == nil ? metrics.spacing.sm : 0)
        }
        .frame(width: width ?? form.controlWidth)
        .glassSurface(
            in: RoundedRectangle(cornerRadius: metrics.radius.menuPanel, style: .continuous)
        )
    }

    /// 列表本体：无匹配项时显示空态，否则渲染可滚动的行与分组标题。
    @ViewBuilder
    private var list: some View {
        if items.isEmpty {
            Text(searchPlaceholder == nil ? "No matches" : "No Results")
                .font(metrics.typography.menuRow)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(
                    height: form.popoverRowHeight,
                    alignment: searchPlaceholder == nil ? .leading : .center
                )
                .padding(searchPlaceholder == nil ? 0 : menuListInset)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: form.popoverRowSpacing) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if let section = item.section, section != sectionBefore(index) {
                                sectionHeader(section)
                            }
                            ExtensionPickerRow(
                                title: item.title,
                                detail: item.detail,
                                icon: ExtensionImage.resolve(
                                    item.iconValue, assetsPath: assetsPath, isDark: isDark),
                                checked: chosen.contains(item.value),
                                selected: index == selection,
                                onActivate: { onSelect(index) }
                            )
                            .id(index)
                            .onHover { if $0, palette.hoverHighlightArmed { onHighlight(index) } }
                        }
                    }
                    .padding(searchPlaceholder == nil ? 0 : menuListInset)
                }
                .frame(
                    height: form.popoverListHeight(
                        rows: items.count, headers: headerCount)
                        + (searchPlaceholder == nil ? 0 : menuListInset * 2)
                )
                .scrollBounceBehavior(
                    form.popoverListContentHeight(rows: items.count, headers: headerCount)
                        > form.popoverRowsMaxHeight
                        ? .always : .basedOnSize
                )
                // 用 `never` 而非 `hidden`：`hidden` 仍会让 AppKit 占用滚动条的边槽。
                .scrollIndicators(.never)
                .overflowFade(
                    band: form.popoverFadeBand, includingTop: searchPlaceholder == nil
                )
                .onChange(of: selection, initial: true) { proxy.scrollTo(selection) }
            }
        }
    }

    /// 绘制一条分组标题行。
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(metrics.typography.sectionHeader)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, metrics.spacing.lg)
            .frame(height: form.popoverSectionHeaderHeight, alignment: .leading)
    }

    /// The section of the row before this one, so only the first of a run draws its heading.
    /// 上一行所属的分组，使连续同组中只有第一行绘制标题。
    private func sectionBefore(_ index: Int) -> String? {
        index > 0 ? items[index - 1].section : nil
    }

    /// 列表绘制的分组标题数量，高度计算会把它与行数一并计入。
    private var headerCount: Int {
        items.indices.reduce(into: 0) { total, index in
            guard let section = items[index].section, section != sectionBefore(index) else { return }
            total += 1
        }
    }
}

/// 面板内嵌的菜单搜索框，绑定到调色板的 `menuQuery`；为空时用占位文案覆盖显示。
struct ExtensionMenuSearchField: View {
    let placeholder: String
    let height: CGFloat
    let verticalOffset: CGFloat

    @Environment(PaletteState.self) private var palette
    @Environment(\.metrics) private var metrics
    @FocusState private var focused: Bool

    /// 搜索框主体：无边框输入框叠加占位文案，出现时自动聚焦。
    var body: some View {
        @Bindable var palette = palette
        TextField("", text: $palette.menuQuery)
            .textFieldStyle(.plain)
            .font(metrics.typography.menuRow)
            .foregroundStyle(Theme.Colors.textPrimary)
            .tint(Theme.Colors.textPrimary)
            .focused($focused)
            .lineLimit(1)
            .background(alignment: .leading) {
                if palette.menuQuery.isEmpty {
                    Text(placeholder)
                        .font(metrics.typography.menuRow)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, metrics.spacing.xl + metrics.spacing.sm)
            .frame(height: height)
            .offset(y: verticalOffset)
            .padding(.vertical, metrics.spacing.xxs / 2)
            .accessibilityLabel(placeholder)
            .onAppear { focused = true }
    }
}
