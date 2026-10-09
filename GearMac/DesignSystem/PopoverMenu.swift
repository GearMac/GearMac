// 文件职责：实现命令面板使用的弹出菜单视图（PopoverMenu），包括图标描述、行数据模型、可搜索列表布局及单行渲染。
// 分层：UI（DesignSystem）；菜单内容由外部构建后传入，本文件只负责布局、滚动定位与悬停/选中交互。
import SwiftUI

/// 菜单行开头的图标：SF Symbol、打包的模板资源图，或来自 `IconCache` 的应用图标。
enum PopoverMenuIcon: Equatable {
    case symbol(String)
    case asset(String)
    case file(path: String)
    /// 图片自身的预览图，按 id 只解码一次：暂存文件所在行因此能显示它将要移除的内容。
    case thumbnail(id: UUID, data: Data)
    /// 颜色编码的实心圆点：标签等按颜色区分的行。
    case dot(Color)
    /// 既无图标也不占位：同一图标下的一串菜单行，省略图标反而更清楚。
    case blank

    /// 生成粘贴行的图标：目标应用的图标路径已知时用该文件图标，否则用给定的兜底符号。
    static func paste(_ target: PasteTarget?, fallback: String) -> PopoverMenuIcon {
        guard let path = target?.iconPath else { return .symbol(fallback) }
        return .file(path: path)
    }
}

/// 一个菜单行；渲染路径与键盘处理都通过该结构定位行。
struct PopoverMenuItem {
    let title: String
    let icon: PopoverMenuIcon
    let isLoading: Bool
    let isEnabled: Bool
    var sectionTitle: String?
    var startsSection: Bool
    var shortcut: String?
    /// 该行展示的取值，而不是可执行的快捷键——例如「拷贝为」行实际拷贝的内容。
    var detail: String?
    /// 破坏性行（如删除）的图标与文字为红色，遵循原生菜单惯例。
    var isDestructive: Bool = false
    let action: () -> Void

    /// 键盘与指针可以落到的行；加载中或已禁用的行只能被读出，不可操作。
    var isSelectable: Bool { isEnabled && !isLoading }

    /// 完整初始化器：按上方字段默认值创建菜单行。
    init(
        title: String, icon: PopoverMenuIcon, isLoading: Bool = false, isEnabled: Bool = true,
        sectionTitle: String? = nil, startsSection: Bool = false, shortcut: String? = nil,
        detail: String? = nil, isDestructive: Bool = false, action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.isEnabled = isEnabled
        self.sectionTitle = sectionTitle
        self.startsSection = startsSection
        self.shortcut = shortcut
        self.detail = detail
        self.isDestructive = isDestructive
        self.action = action
    }

    /// 便捷初始化器：以 SF Symbol 名称而非 `PopoverMenuIcon` 指定图标。
    init(
        title: String, systemImage: String, isLoading: Bool = false, isEnabled: Bool = true,
        sectionTitle: String? = nil, startsSection: Bool = false, shortcut: String? = nil,
        isDestructive: Bool = false, action: @escaping () -> Void
    ) {
        self.init(
            title: title, icon: .symbol(systemImage), isLoading: isLoading, isEnabled: isEnabled,
            sectionTitle: sectionTitle, startsSection: startsSection, shortcut: shortcut,
            isDestructive: isDestructive, action: action)
    }
}

/// 菜单的标题与行数据，构建一次后同时供渲染与键盘逻辑消费。
struct PopoverMenuContent {
    var header: String?
    let items: [PopoverMenuItem]
}

/// 命令面板自带的菜单视图，由 `MenuPanelController` 承载在独立窗口中。
struct PopoverMenu: View {
    /// 菜单面板与锚点控件贴合的一角，用于决定对应圆角是否收窄。
    enum Attachment {
        case none
        case bottomLeading
        case bottomTrailing
    }

    /// 搜索框配置：占位文案与放置位置。
    struct Search {
        /// 搜索框位于菜单顶部还是底部。
        enum Placement {
            case top
            case bottom
        }

        let placeholder: String
        let placement: Placement
    }

    /// 菜单面板外形：贴合角使用更小的圆角，其余三角保持常规圆角。
    struct SurfaceShape: Shape {
        let attachment: Attachment
        let radius: CGFloat
        let attachedRadius: CGFloat

        func path(in rect: CGRect) -> Path {
            UnevenRoundedRectangle(
                topLeadingRadius: radius,
                bottomLeadingRadius: attachment == .bottomLeading ? attachedRadius : radius,
                bottomTrailingRadius: attachment == .bottomTrailing ? attachedRadius : radius,
                topTrailingRadius: radius,
                style: .continuous
            ).path(in: rect)
        }
    }

    var header: String?
    let items: [PopoverMenuItem]
    @Binding var selection: Int
    /// 固定宽度，绝不随内容自适应：跟随最长行的宽度会随行变化而抖动。
    var width: CGFloat?
    let onActivate: (Int) -> Void
    var attachment = Attachment.none
    let search: Search

    /// 只有在指针自行移动过后，命令面板才会启用悬停高亮。
    @Environment(PaletteState.self) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.displayScale) private var displayScale
    @FocusState private var searchFocused: Bool
    /// 由指针设置，使滚动到选中行时能区分是指针移动还是键盘移动。
    @State private var pointerSelection: Int?

    private var listInset: CGFloat { metrics.spacing.md }
    /// 一个设备像素：一个点宽的分隔线在玻璃背景上会显得过重。
    private var hairline: CGFloat { 1 / displayScale }
    var body: some View {
        let shape = SurfaceShape(
            attachment: attachment, radius: metrics.radius.menuPanel,
            attachedRadius: metrics.size.menuButton / 2)
        surfaceContent
            .frame(width: width ?? metrics.size.actionMenuWidth)
            .glassSurface(in: shape)
    }

    /// 按搜索框位置把搜索区与列表上下拼接。
    private var surfaceContent: some View {
        VStack(spacing: 0) {
            if search.placement == .top {
                searchField
                searchSeparator
            }
            menuContent
            if search.placement == .bottom {
                searchSeparator
                searchField
            }
        }
    }

    /// 列表主体：无结果时展示提示文案，否则展示各行。
    @ViewBuilder
    private var menuContent: some View {
        if items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                if let header {
                    headerLabel(header)
                    Color.clear.frame(height: metrics.size.menuRowSpacing)
                }
                Text("No Results")
                    .font(metrics.typography.menuRow)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.size.menuRowHeight)
            }
            .padding(listInset)
        } else {
            rows
        }
    }

    /// 菜单内搜索框，占位文案由调用方提供，出现时自动获取焦点。
    private var searchField: some View {
        @Bindable var palette = palette
        let placeholder = search.placeholder
        return TextField("", text: $palette.menuQuery)
            .textFieldStyle(.plain)
            .font(metrics.typography.menuRow)
            .foregroundStyle(Theme.Colors.textPrimary)
            .tint(Theme.Colors.textPrimary)
            .focused($searchFocused)
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
            .frame(height: metrics.size.menuRowHeight)
            .offset(y: search.placement == .bottom ? -metrics.spacing.xxs / 2 : 0)
            .padding(.vertical, metrics.spacing.xxs / 2)
            .accessibilityLabel(placeholder)
            .onAppear { searchFocused = true }
    }

    /// 搜索区与列表之间的一个设备像素分隔线。
    private var searchSeparator: some View {
        Rectangle()
            .fill(Theme.Colors.separator)
            .frame(height: hairline)
            .accessibilityHidden(true)
    }

    /// 菜单顶部的标题文本，使用章节标题样式。
    private func headerLabel(_ text: String) -> some View {
        Text(text)
            .font(metrics.typography.sectionHeader)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(height: metrics.size.menuSectionHeader, alignment: .leading)
            .padding(.horizontal, metrics.spacing.lg)
            .padding(.top, metrics.spacing.xs)
            .padding(.bottom, metrics.spacing.xs / 2)
    }

    /// 标题与各行作为同一表面整体滚动，同时仍以行索引驱动键盘滚动定位。
    private var rows: some View {
        let extent = listExtent
        return ScrollViewReader { proxy in
            ScrollView {
                // 使用懒加载：模型菜单可能有数百行，实际可见的只有视口内的部分。
                LazyVStack(alignment: .leading, spacing: 0) {
                    // 以索引作为 id 是稳定的：菜单打开期间行顺序不会变化。
                    ForEach(items.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 0) {
                            // 位于首行的滚动目标内，因此滚动到首行时标题会一并出现。
                            if index == 0, let header {
                                headerLabel(header)
                                Color.clear.frame(height: metrics.size.menuRowSpacing)
                            }
                            rowBoundary(before: index)
                            VStack(alignment: .leading, spacing: 0) {
                                if let sectionTitle = items[index].sectionTitle {
                                    sectionLabel(sectionTitle, isFirst: index == 0)
                                }
                                PopoverMenuRow(
                                    item: items[index],
                                    selected: index == selection && items[index].isSelectable
                                ) {
                                    onActivate(index)
                                }
                            }
                            .onContinuousHover { if case .active = $0 { hover(index) } }
                        }
                        .id(index)
                    }
                }
                .padding(.horizontal, listInset)
            }
            // 使用内容边距而非 padding：滚动到末行时该行仍保留内缩，而不会贴到边缘。
            .contentMargins(.vertical, listInset, for: .scrollContent)
            .frame(height: extent.viewport + listInset * 2)
            // 用 `never` 而非 `hidden`：`hidden` 仍会让 AppKit 占用滚动条的空间。
            .scrollIndicators(.never)
            .scrollBounceBehavior(extent.content > extent.viewport ? .always : .basedOnSize)
            // 承载视图的生命周期长于一次展示，因此新一次展示不应继承上一次的滚动偏移。
            .id(palette.menuPresentationToken)
            .onAppear { proxy.scrollTo(selection, anchor: .center) }
            .onChange(of: selection) {
                let byPointer = pointerSelection == selection
                pointerSelection = nil
                guard !byPointer else { return }
                proxy.scrollTo(selection)
            }
        }
    }

    @ViewBuilder
    private func rowBoundary(before index: Int) -> some View {
        if index > 0, items[index].startsSection {
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(height: hairline)
                .padding(.horizontal, metrics.spacing.md)
                // 与列表内边距一致，使行到该分隔线的距离与到搜索分隔线的距离相同。
                .padding(.vertical, listInset)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else if index > 0 {
            Color.clear.frame(height: metrics.size.menuRowSpacing)
        }
    }

    /// 精确计算而非实测：视口被限高时会在行中间截断，而不会落在分隔线或章节标题上。
    private var listExtent: (content: CGFloat, viewport: CGFloat) {
        let capacity = metrics.size.menuRowsMaxHeight + headerExtent
        let rowHeight = metrics.size.menuRowHeight
        var offset = headerExtent
        var fold: CGFloat = 0
        for (index, item) in items.enumerated() {
            if index > 0 {
                offset += item.startsSection ? listInset * 2 + hairline : metrics.size.menuRowSpacing
            }
            if item.sectionTitle != nil {
                offset += metrics.size.menuSectionHeader + metrics.spacing.xxs
                if index > 0 { offset += metrics.spacing.md }
            }
            let midRow = (offset + rowHeight / 2).rounded(.down)
            if midRow <= capacity { fold = midRow }
            offset += rowHeight
        }
        return (offset, offset > capacity ? fold : offset)
    }

    private var headerExtent: CGFloat {
        guard header != nil else { return 0 }
        return metrics.size.menuSectionHeader + metrics.spacing.xs * 1.5
            + metrics.size.menuRowSpacing
    }

    /// 下间距小于上间距，使标题归属其下方的行，而不是夹在两组之间。
    private func sectionLabel(_ title: String, isFirst: Bool) -> some View {
        Text(title)
            .font(metrics.typography.sectionHeader)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(
                maxWidth: .infinity, minHeight: metrics.size.menuSectionHeader,
                maxHeight: metrics.size.menuSectionHeader, alignment: .leading
            )
            // 使用 `md`，与行自身的内边距一致，使标题与图标左对齐于同一条边。
            .padding(.horizontal, metrics.spacing.md)
            .padding(.top, isFirst ? 0 : metrics.spacing.md)
            .padding(.bottom, metrics.spacing.xxs)
    }

    /// 仅在指针自行移动后才生效，因此滚过行时不会点亮相高亮。
    private func hover(_ index: Int) {
        guard palette.hoverHighlightArmed, items[index].isSelectable, index != selection else {
            return
        }
        pointerSelection = index
        selection = index
    }
}

/// 单个菜单行；高亮由选中状态驱动，因此任意时刻只有一行处于激活态。
private struct PopoverMenuRow: View {
    let item: PopoverMenuItem
    let selected: Bool
    let onActivate: () -> Void
    @Environment(\.metrics) private var metrics

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: metrics.spacing.md) {
                if item.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: metrics.size.menuIcon, height: metrics.size.menuIcon)
                } else {
                    switch item.icon {
                    case .blank:
                        EmptyView()
                    case .symbol(let name):
                        Image(systemName: SystemSymbolName.resolve(name))
                            .font(
                                .system(
                                    size: metrics.scaled(Theme.Typography.menuSymbolSize),
                                    weight: Theme.Typography.menuSymbolWeight)
                            )
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(
                                item.isDestructive ? Color.red : Theme.Colors.menuSymbol
                            )
                            .frame(width: metrics.size.menuIcon, height: metrics.size.menuIcon)
                    case .asset(let name):
                        Image(name)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(item.isDestructive ? Color.red : Color.secondary)
                            .frame(width: metrics.size.menuBrandIcon, height: metrics.size.menuBrandIcon)
                            .frame(width: metrics.size.menuIcon, height: metrics.size.menuIcon)
                    case .file(let path):
                        MenuFileIcon(path: path)
                    case .thumbnail(let id, let data):
                        MenuThumbnail(id: id, data: data)
                    case .dot(let color):
                        Circle()
                            .fill(color)
                            .frame(width: metrics.size.menuBrandIcon, height: metrics.size.menuBrandIcon)
                            .frame(width: metrics.size.menuIcon, height: metrics.size.menuIcon)
                    }
                }
                Text(item.title)
                    .font(metrics.typography.menuRow)
                    .foregroundStyle(item.isDestructive ? Color.red : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: metrics.spacing.sm)
                if let detail = item.detail {
                    Text(detail)
                        // 字号小于前面的标题：它是该行的取值，而不是第二个标签。
                        .font(metrics.typography.keyCap)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        // 这类记法最具标识性的部分在前，因此截断从尾部开始。
                        .truncationMode(.tail)
                }
                if let shortcut = item.shortcut {
                    HStack(spacing: metrics.spacing.xxs) {
                        ForEach(Array(shortcut.enumerated()), id: \.offset) { _, glyph in
                            KeyCapChip(text: String(glyph), style: .outline)
                        }
                    }
                }
            }
            .padding(.horizontal, metrics.spacing.md)
            // 直接指定高度而非靠内边距撑开：上面的高度计算按行计数，每行必须是精确高度。
            .frame(
                maxWidth: .infinity, minHeight: metrics.size.menuRowHeight,
                maxHeight: metrics.size.menuRowHeight, alignment: .leading
            )
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.menuRow, style: .continuous)
                    .fill(selected ? Theme.Colors.menuHover : Color.clear)
            )
            .opacity(item.isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!item.isSelectable)
    }
}

/// 菜单行的图片，裁切到图标槽位；task 以 id 为标识，重绘时复用已解码图片。
struct MenuThumbnail: View {
    let id: UUID
    let data: Data
    @State private var image: NSImage?
    @Environment(\.metrics) private var metrics

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Color.clear
            }
        }
        .frame(width: metrics.size.menuIcon, height: metrics.size.menuIcon)
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius.thumbnail, style: .continuous))
        .task(id: id) { image = NSImage(data: data) }
    }
}

/// 菜单行的应用图标；先取缓存作为初始值，使粘贴目标能在首帧就画出来。
struct MenuFileIcon: View {
    let path: String
    @State private var image: NSImage?
    @Environment(\.metrics) private var metrics

    init(path: String) {
        self.path = path
        _image = State(initialValue: IconCache.cached(forFile: path))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                Color.clear
            }
        }
        .frame(width: metrics.size.menuIcon, height: metrics.size.menuIcon)
        .task(id: IconRequest(path)) {
            guard image == nil else { return }
            image = await IconCache.loadAsync(forFile: path)
        }
    }
}
