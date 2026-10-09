// 文件职责：绘制扩展结果的三种形态（普通行列表、详情双栏、网格），以及列表项、附件与网格单元。
// 分层：UI；行序由 `ExtensionScreen` 决定，选中索引取自调用方传入的扁平索引。
import SwiftUI

/// 行序由 `ExtensionScreen` 决定，使调色板的扁平索引与绘制顺序一一对应。
struct ExtensionListView: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.isDarkAppearance) private var isDark
    let screen: ExtensionScreen
    let selection: Int
    let assetsPath: String?
    /// 仅在列表需要滚动时变化，因此鼠标选择不会拖动滚动位置。
    let scroll: ScrollIntent
    let onSelect: (Int) -> Void
    let onActivate: (Int) -> Void
    let onActions: (Int) -> Void

    private static let detailListWidth: CGFloat = 290

    var body: some View {
        Group {
            if screen.items.isEmpty {
                emptyState
            } else if screen.showsDetail {
                HStack(spacing: 0) {
                    rowList
                        .frame(width: metrics.scaled(Self.detailListWidth))
                    Rectangle().fill(Theme.Colors.separator).frame(width: 1)
                    detailPane
                }
            } else if case .grid(let layout) = screen.kind {
                gridBody(layout: layout)
            } else {
                rowList
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if screen.isLoading {
            EmptyResults(text: "Loading…")
        } else if let empty = screen.emptyView {
            VStack(spacing: metrics.spacing.md) {
                ExtensionIconView(
                    resolved: ExtensionImage.resolve(
                        empty.props["icon"], assetsPath: assetsPath, isDark: isDark),
                    size: 42)
                Text(empty.string("title") ?? "Nothing here")
                    .font(metrics.typography.rowTitle)
                if let description = empty.string("description") {
                    Text(description)
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, metrics.spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyResults(text: "No results")
        }
    }

    private var rowList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(screen.rows) { row in
                        switch row {
                        case .header(let title, let subtitle, _):
                            SectionHeader(
                                title: [title, subtitle].compactMap { $0 }.filter { !$0.isEmpty }
                                    .joined(separator: "  ·  "),
                                isFirst: row.id == screen.rows.first?.id)
                        case .item(let item):
                            ExtensionItemRow(
                                node: item.node, selected: item.index == selection,
                                assetsPath: assetsPath, compact: screen.showsDetail
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelect(item.index)
                                onActivate(item.index)
                            }
                            .onRightClick { onActions(item.index) }
                            .selectionFrame(item.index == selection)
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
                scroll, row: selectedRowID, atOrigin: selection == 0, proxy: proxy)
        }
    }

    /// 选中项的滚动 id；选中索引越界时为 nil。
    private var selectedRowID: String? {
        screen.items.indices.contains(selection) ? screen.items[selection].id : nil
    }

    /// 对整个网格只测量一次：若每个图块各自使用 `GeometryReader`，则每个格子都会多一轮布局。
    private func gridBody(layout: ExtensionGridLayout) -> some View {
        GeometryReader { geometry in
            grid(
                layout: layout,
                tileWidth: layout.tileWidth(
                    inWidth: geometry.size.width - metrics.spacing.md * 2,
                    spacing: metrics.spacing.sm))
        }
    }

    private func grid(layout: ExtensionGridLayout, tileWidth: Double) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: metrics.spacing.sm),
                        count: layout.columns),
                    spacing: metrics.spacing.sm
                ) {
                    ForEach(screen.items) { item in
                        ExtensionGridCell(
                            node: item.node, selected: item.index == selection,
                            assetsPath: assetsPath, layout: layout, width: tileWidth
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect(item.index)
                            onActivate(item.index)
                        }
                        .onRightClick { onActions(item.index) }
                        .selectionFrame(item.index == selection)
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
                scroll, row: selectedRowID, atOrigin: selection < layout.columns, proxy: proxy)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if screen.items.indices.contains(selection),
            let detail = screen.items[selection].node.node("detail")
        {
            ExtensionDetailBody(
                markdown: detail.string("markdown"), metadata: detail.node("metadata"),
                isLoading: detail.bool("isLoading") ?? false, assetsPath: assetsPath,
                stacksMetadata: true)
        } else {
            Color.clear
        }
    }
}

/// 单个 `List.Item`：图标、标题、副标题，随后是右对齐的附件。
private struct ExtensionItemRow: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.isDarkAppearance) private var isDark
    let node: RenderNode
    let selected: Bool
    let assetsPath: String?
    let compact: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            if let icon = node.props["icon"], icon != .null {
                ExtensionIconView(
                    resolved: ExtensionImage.resolve(icon, assetsPath: assetsPath, isDark: isDark),
                    size: metrics.size.resultRowIcon)
            }
            Text(node.string("title") ?? "")
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
                // 优先级高于 Spacer，否则 Spacer 会占去标题一半的空间。
                .layoutPriority(1)
            if !compact, let subtitle = node.string("subtitle"), !subtitle.isEmpty {
                Text(subtitle)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: metrics.spacing.sm)
            // Raycast 会绘制传入的附件，配额行的信号也全部体现在这些附件里。
            ExtensionAccessoriesView(
                accessories: node.array("accessories"), assetsPath: assetsPath
            )
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill)
        )
        .armedHover($hovered)
    }
}

/// `List.Item.Accessory` 的取值：文本、标签、日期、图标，或它们的组合。
struct ExtensionAccessoriesView: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.isDarkAppearance) private var isDark
    let accessories: [RenderValue]
    let assetsPath: String?

    var body: some View {
        HStack(spacing: metrics.spacing.sm) {
            ForEach(Array(accessories.enumerated()), id: \.offset) { _, accessory in
                if let fields = accessory.objectValue {
                    accessoryView(fields)
                }
            }
        }
    }

    @ViewBuilder
    private func accessoryView(_ fields: [String: RenderValue]) -> some View {
        HStack(spacing: metrics.spacing.xs) {
            if let icon = fields["icon"] {
                ExtensionIconView(
                    resolved: ExtensionImage.resolve(icon, assetsPath: assetsPath, isDark: isDark), size: 13)
            }
            if let tag = fields["tag"] {
                tagView(tag)
            }
            if let text = ExtensionAccessoriesView.label(fields["text"]) {
                Text(text)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(
                        ExtensionImage.color(fields["text"]?.objectValue?["color"], isDark: isDark)
                            ?? Theme.Colors.textSecondary
                    )
                    .lineLimit(1)
            }
            if let date = ExtensionAccessoriesView.date(fields["date"]) {
                Text(date, format: .relative(presentation: .numeric))
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .help(fields["tooltip"]?.stringValue ?? "")
    }

    /// 标签是 `{value, color}`，或裸的字符串/日期。
    @ViewBuilder
    private func tagView(_ tag: RenderValue) -> some View {
        let fields = tag.objectValue
        let text =
            ExtensionAccessoriesView.label(fields?["value"] ?? tag)
            ?? ExtensionAccessoriesView.date(fields?["value"] ?? tag).map {
                $0.formatted(date: .abbreviated, time: .omitted)
            }
        if let text {
            let color = ExtensionImage.color(fields?["color"], isDark: isDark) ?? Theme.Colors.textSecondary
            Text(text)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(color)
                .padding(.horizontal, metrics.spacing.xs)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(color.opacity(0.16))
                )
                .lineLimit(1)
        }
    }

    /// `text` 可以是字符串，或 `{value, color}`。
    static func label(_ value: RenderValue?) -> String? {
        guard let value else { return nil }
        if let text = value.stringValue { return text }
        return value.objectValue?["value"]?.stringValue
    }

    static func date(_ value: RenderValue?) -> Date? {
        guard let value else { return nil }
        if let date = value.dateValue { return date }
        return value.objectValue?["value"]?.dateValue
    }
}

/// 单个 `Grid.Item`：内容按 `Grid` 属性要求的图块尺寸绘制，标题位于其下。
private struct ExtensionGridCell: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.isDarkAppearance) private var isDark
    let node: RenderNode
    let selected: Bool
    let assetsPath: String?
    let layout: ExtensionGridLayout
    let width: Double
    @State private var hovered = false

    private var content: RenderValue? { node.props["content"] }

    /// 图块也可能是裸的 `{color}` 色样，此时没有可解析的图像。
    private var swatch: Color? {
        guard let fields = content?.objectValue else { return nil }
        return ExtensionImage.color((fields["value"]?.objectValue ?? fields)["color"], isDark: isDark)
    }

    private var height: Double { width / layout.aspectRatio }

    private var contentSize: CGSize {
        let inset = width * layout.inset.fraction
        return CGSize(width: width - inset * 2, height: height - inset * 2)
    }

    private var background: Color {
        if selected { return Theme.Colors.selection }
        return hovered ? Theme.Colors.rowHover : ExtensionColors.gridItemFill
    }

    var body: some View {
        VStack(spacing: metrics.spacing.xs) {
            tile
            if let title = node.string("title") {
                Text(title)
                    .font(metrics.typography.rowTrailing)
                    .lineLimit(1)
            }
            if let subtitle = node.string("subtitle") {
                Text(subtitle)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: width)
        .armedHover($hovered)
    }

    private var tile: some View {
        tileContent
            .frame(width: contentSize.width, height: contentSize.height)
            .clipShape(RoundedRectangle(cornerRadius: contentRadius, style: .continuous))
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: ExtensionGridLayout.tileRadius, style: .continuous)
                    .fill(background)
            )
            // 铺满图块的内容会遮住底色，因此用描边来标记选中。
            .overlay {
                RoundedRectangle(cornerRadius: ExtensionGridLayout.tileRadius, style: .continuous)
                    .strokeBorder(Theme.Colors.border, lineWidth: 2)
                    .opacity(selected ? 1 : 0)
            }
    }

    /// 铺满的内容沿用图块的圆角；内缩图稿较小，需要更紧的圆角。
    private var contentRadius: Double {
        layout.inset == .zero ? ExtensionGridLayout.tileRadius : metrics.radius.thumbnail
    }

    /// `content` 是 `ImageLike`，或包裹它的 `{value, tooltip}` —— 两者都由 `resolve` 处理。
    @ViewBuilder
    private var tileContent: some View {
        let resolved = ExtensionImage.resolve(content, assetsPath: assetsPath, isDark: isDark)
        if resolved == nil, let swatch {
            Rectangle().fill(swatch)
        } else {
            ExtensionGridContentView(resolved: resolved, fills: layout.fills, size: contentSize)
        }
    }
}

/// 图块的图像，按给定图块尺寸缩放 —— 与 `ExtensionIconView` 固定尺寸的图标框不同。
private struct ExtensionGridContentView: View {
    @Environment(\.isDarkAppearance) private var isDark
    let resolved: ExtensionImage.Resolved?
    let fills: Bool
    /// 由上层传入而非自行测量：网格已经知道每个图块的尺寸。
    let size: CGSize
    @State private var loaded: NSImage?

    var body: some View {
        content
            // 也以外观作为键：内联 SVG 的调色板在解码时解析。
            .task(id: ExtensionImage.LoadKey(source: resolved?.source, isDark: isDark)) {
                loaded = await ExtensionImage.load(resolved, isDark: isDark, animates: true)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch resolved?.source {
        case .symbol(let name):
            // SF Symbol 没有可缩放的图稿，因此只占图块的一部分而非全部。
            Image(systemName: name)
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(resolved?.tint == nil ? .hierarchical : .monochrome)
                .foregroundStyle(resolved?.tint ?? Theme.Colors.textSecondary)
                .padding(min(size.width, size.height) * 0.2)
        case .glyph(let text):
            Text(text)
                .font(.system(size: min(size.width, size.height) * 0.72))
        case .file, .fileIcon, .remote, .inline:
            if let loaded {
                image(loaded)
            } else {
                placeholder
            }
        case nil:
            placeholder
        }
    }

    /// 图块已被裁剪，因此淡色填充无需自己的圆角。
    private var placeholder: some View { Rectangle().fill(Theme.Colors.iconPlaceholder) }

    @ViewBuilder
    private func image(_ image: NSImage) -> some View {
        // 只有多帧图片才走 `NSImageView`；静态图仍留在 SwiftUI 的绘制路径上。
        if image.isAnimated {
            AnimatedImageView(image: image)
                .scaleEffect(fills ? coverScale(image) : 1)
        } else {
            // `tintColor` 会遮蔽图稿，这正是为 `currentColor` 的 SVG 着色的方式。
            Image(nsImage: image)
                .resizable()
                .renderingMode(resolved?.tint == nil ? .original : .template)
                .aspectRatio(contentMode: fills ? .fill : .fit)
                .foregroundStyle(resolved?.tint ?? .primary)
        }
    }

    /// `NSImageView` 只能等比适配，因此 `Grid.Fit.Fill` 将该绘制放大到铺满。
    private func coverScale(_ image: NSImage) -> Double {
        let scales = [size.width / image.size.width, size.height / image.size.height]
        guard let low = scales.min(), let high = scales.max(), low > 0, high.isFinite else { return 1 }
        return high / low
    }
}
