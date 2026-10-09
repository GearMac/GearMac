// 文件职责：剪贴板底部横条——类型标签行与横向滚动的条目卡片，以及跨功能复用的日期分组与缩略图加载。
// 分层：UI；SwiftUI 视图，读取 ClipboardStore，除统计与缩略图外不产生副作用。
import AppKit
import SwiftUI

/// 剪贴板浏览界面本体：标签行切换类型筛选，卡片按时间从新到旧横向排列。
struct ClipboardBar: View {
    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    @Environment(PaletteState.self) private var vm
    @Environment(ClipboardStore.self) private var store

    let results: [ClipboardItem]
    let selectedID: ClipboardItem.ID?
    let scroll: ScrollIntent
    let onSelectFilter: (ClipboardFilter) -> Void
    /// 处于类型或标签筛选时，在标签行首显示返回箭头。
    let filterActive: Bool
    /// 清除类型和标签筛选，回到全部历史。
    let onClearFilters: () -> Void
    /// 打开「标签」筛选菜单；仅在未选中标签时调用。
    let openTagFilterMenu: () -> Void
    /// 最右侧的剪贴板设置菜单。
    let openSettingsMenu: () -> Void
    /// 真实搜索框，惰性求值后展示在设置按钮左侧；闭包形式切断 screen↔headerField 的相互构建。
    let searchField: () -> AnyView
    let onSelect: (ClipboardItem) -> Void
    let onActivate: () -> Void
    let onActions: (ClipboardItem, CGRect) -> Void
    /// 条目无可交付内容时返回 nil，此时给出提示而不是发起拖拽。
    let onDragPayload: (ClipboardItem) -> ClipDragPayload?
    let onDropped: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            tabs
            ClipboardCardRow(
                results: results, selectedID: selectedID, scroll: scroll, onSelect: onSelect,
                onActivate: onActivate, onActions: onActions, onDragPayload: onDragPayload,
                onDropped: onDropped)
        }
        // 不恢复旧 header；通过更宽的四周留白把卡片收敛为正方形。
        .padding(.top, metrics.spacing.xxl)
        .padding(.bottom, metrics.spacing.xxl)
    }

    /// 类型标签行；选中标签高亮，筛选时箭头居首，搜索框与设置按钮靠右。
    private var tabs: some View {
        HStack(spacing: metrics.spacing.md) {
            if filterActive {
                BarButton(chrome: .rounded, isCompact: true, action: onClearFilters) {
                    SymbolImage(name: "chevron.left", size: metrics.size.barBrandIcon)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            ForEach(ClipboardFilter.allCases, id: \.self) { filter in
                BarButton(chrome: .rounded, isSelected: filter == vm.clipboardFilter) {
                    onSelectFilter(filter)
                } label: {
                    Text(tabTitle(filter))
                        .font(metrics.typography.bar)
                        .foregroundStyle(
                            filter == vm.clipboardFilter
                                ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                }
            }
            tagTab
            Spacer(minLength: 0)
            searchField()
                .padding(.horizontal, metrics.spacing.md)
                .frame(width: metrics.size.clipboardSearchEntry, height: metrics.size.barButtonHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.radius.barControl, style: .continuous)
                        .strokeBorder(Theme.Colors.border, lineWidth: 1))
            BarButton(chrome: .rounded, isCompact: true, action: openSettingsMenu) {
                SymbolImage(name: "gearshape", size: metrics.size.barBrandIcon)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(.horizontal, metrics.spacing.xl)
        .padding(.vertical, metrics.spacing.xxs)
    }

    /// 「标签」筛选项：位于邮箱之后；已选中时再点一次取消。
    private var tagTab: some View {
        let active = vm.clipboardTagFilter
        let tag = store.tag(named: active)
        return BarButton(chrome: .rounded, isSelected: active != nil) {
            if active != nil {
                vm.clipboardTagFilter = nil
            } else {
                openTagFilterMenu()
            }
        } label: {
            HStack(spacing: metrics.spacing.xxs) {
                if let tag {
                    ColorDot(color: tagColor(tag.colorHex))
                } else {
                    SymbolImage(name: "tag", size: metrics.size.barBrandIcon)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Text(active ?? settings.text(ClipboardKey.tabTag))
                    .font(metrics.typography.bar)
                    .foregroundStyle(
                        active != nil
                            ? Theme.Colors.textPrimary : Theme.Colors.textSecondary
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private func tabTitle(_ filter: ClipboardFilter) -> String {
        let key: ClipboardKey =
            switch filter {
            case .all: .tabAll
            case .text: .tabText
            case .image: .tabImage
            case .file: .tabFile
            case .color: .tabColor
            case .link: .tabLink
            case .email: .tabEmail
            }
        return settings.text(key)
    }
}

/// 从 hex 记法取色；解析失败时退回卡片自身的底色。
func tagColor(_ hex: String) -> Color {
    ColorValue.parse(hex).map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
        ?? Theme.Colors.cardFill
}

/// 横向滚动的卡片行；键盘导航时把选中卡片滚回可见区。
private struct ClipboardCardRow: View {
    @Environment(\.metrics) private var metrics
    @Environment(ClipboardStore.self) private var store

    let results: [ClipboardItem]
    let selectedID: ClipboardItem.ID?
    /// 只在键盘导航时变化，因此鼠标选择不会强行滚动卡片行。
    let scroll: ScrollIntent
    let onSelect: (ClipboardItem) -> Void
    let onActivate: () -> Void
    let onActions: (ClipboardItem, CGRect) -> Void
    let onDragPayload: (ClipboardItem) -> ClipDragPayload?
    let onDropped: () -> Void

    /// 内容原点锚点；`scrollOriginAnchor()` 的横向对应物。
    private static let originID = "clipboard-bar-origin"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: metrics.spacing.md) {
                    ForEach(results) { item in
                        ClipboardCard(
                            item: item,
                            selected: item.id == selectedID,
                            slot: slot(for: item),
                            tagColor: store.tag(named: item.tag).map { tagColor($0.colorHex) },
                            imageURL: store.imageURL(for: item),
                            onSelect: { onSelect(item) },
                            onActivate: {
                                onSelect(item)
                                onActivate()
                            },
                            onActions: { frame in onActions(item, frame) },
                            drag: RowDrag(
                                item: { onDragPayload(item)?.dragItem }, dropped: onDropped)
                        )
                    }
                }
                .padding(.horizontal, metrics.spacing.xl)
                .padding(.vertical, metrics.spacing.xs)
                .hideNativeScrollers()
                .overlay(alignment: .leading) {
                    Color.clear.frame(width: 0).id(Self.originID)
                }
            }
            .onChange(of: scroll) { _, intent in
                switch intent.kind {
                case .top:
                    proxy.scrollTo(Self.originID, anchor: .leading)
                case .follow, .center:
                    if let selectedID { proxy.scrollTo(selectedID, anchor: .center) }
                }
            }
        }
    }

    /// ⌘ 数字槽位按 Pinned 顺序排列，只有按住 ⌘ 时才显示。
    private func slot(for item: ClipboardItem) -> Character? {
        guard item.isPinned else { return nil }
        let index = results.filter(\.isPinned).firstIndex(where: { $0.id == item.id }) ?? 0
        return FavoriteSlots.digit(at: index)
    }
}

/// 单张条目卡片：来源图标、相对时间、内容预览与元信息脚注。
private struct ClipboardCard: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.displayScale) private var displayScale
    @Environment(PaletteState.self) private var palette
    @Environment(AppSettings.self) private var settings

    let item: ClipboardItem
    let selected: Bool
    let slot: Character?
    /// 带色标签的卡片整张底色换成标签色。
    let tagColor: Color?
    let imageURL: URL?
    let onSelect: () -> Void
    let onActivate: () -> Void
    let onActions: (CGRect) -> Void
    let drag: RowDrag

    @State private var hovered = false
    @State private var characterCount: Int?
    /// 右键时菜单要悬挂的位置：卡片自身的全局坐标。
    @State private var frame: CGRect = .zero

    /// 带色标签接管整张底色；选中态由描边表达。
    private var fill: Color {
        if let tagColor { return tagColor }
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return Theme.Colors.cardFill
    }

    var body: some View {
        IconCache.observeStyle()
        return VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            header
            preview
            Spacer(minLength: 0)
            footer
        }
        .padding(metrics.spacing.md)
        .frame(width: metrics.size.clipboardCard.width, height: metrics.size.clipboardCard.height)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous).fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                .strokeBorder(
                    selected ? Theme.Colors.border : Theme.Colors.cardStroke, lineWidth: 1)
        )
        // 缩略图 fill 放大后的溢出在这里被卡片自身兜住，绝不超出瓷片。
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous))
        .armedHover($hovered)
        .contentShape(RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous))
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: {
            frame = $0
        }
        // 轻量右键捕获：`.contextMenu` 会卡顿。
        .onRightClick { onActions(frame) }
        .onRowClick(select: onSelect, activate: onActivate, drag: drag)
        .task(id: item.id) { await loadCount() }
        .accessibilityElement(children: .combine)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: metrics.spacing.xs) {
            leadingIcon
            Spacer(minLength: 0)
            if item.isPinned {
                SymbolImage(name: "pin.fill", size: metrics.size.clipboardCardIcon)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            if let slot, palette.commandHeld {
                KeyCapChip(text: String(slot), style: .outline, scale: .compact)
            }
            Text(CardTime.text(for: item.createdAt, language: settings.resolvedLanguage))
                .font(metrics.typography.cardMeta)
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)
        }
        .frame(height: metrics.size.clipboardCardIcon)
    }

    private enum CardIcon {
        case swatch(ColorValue)
        case app(NSImage)
        case symbol(String)
    }

    private var iconContent: CardIcon {
        // 颜色可自我表达，因此占据原本由图标填充的位置。
        if let color = item.colorValue { return .swatch(color) }
        if let icon = ClipSourceIcons.icon(for: item.sourceBundleID) { return .app(icon) }
        return .symbol(kindSymbol)
    }

    private var kindSymbol: String {
        switch item.kind {
        case .text:
            switch item.textForm {
            case .link: return "link"
            case .email: return "at"
            default: return "doc.text"
            }
        case .image: return "photo"
        case .file:
            return ClipboardFileKind.of(path: item.filePath ?? "").systemImage
        }
    }

    @ViewBuilder
    private var leadingIcon: some View {
        let side = metrics.size.clipboardCardIcon
        switch iconContent {
        case .swatch(let color):
            ColorSwatch(color: color).frame(width: side, height: side)
        case .app(let image):
            Image(nsImage: image).resizable().frame(width: side, height: side)
        case .symbol(let name):
            Image(nsImage: IconCache.symbolIcon(named: name))
                .resizable()
                .frame(width: side, height: side)
        }
    }

    // MARK: - 预览

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .text:
            if let color = item.colorValue {
                ColorSwatch(color: color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(previewText)
                    .font(metrics.typography.cardText)
                    .lineLimit(7)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        case .image:
            thumbnail(url: imageURL, source: .image, placeholder: "photo")
        case .file:
            thumbnail(
                url: fileURL, source: .file,
                placeholder: ClipboardFileKind.of(path: item.filePath ?? "").systemImage)
        }
    }

    /// 图片与文件共用一整块预览区；显式 frame + 裁剪，保证 fill 放大后绝不超出卡片。
    /// 解码预算随显示框与像素密度变化：长图按宽高比抬高长边，避免放大发虚。
    @ViewBuilder
    private func thumbnail(url: URL?, source: ThumbnailSource, placeholder: String) -> some View {
        GeometryReader { proxy in
            AsyncThumbnail(
                url: url, box: proxy.size, pixelScale: displayScale, source: source
            ) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: metrics.radius.thumbnail, style: .continuous))
            } placeholder: {
                Image(nsImage: IconCache.symbolIcon(named: placeholder))
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: metrics.size.clipboardCardIcon * 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// 行的预览文本：文本取其前 200 字符，避免为每张卡片遍历数 MB 的复制内容。
    private var previewText: String {
        String((item.text ?? "").prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // 不用 `fileURLWithPath:`，它会 stat 路径：在网络挂载上会拖住渲染。
    private var fileURL: URL? {
        item.filePath.map { URL(filePath: $0, directoryHint: .inferFromPath) }
    }

    // MARK: - 脚注

    @ViewBuilder
    private var footer: some View {
        if let tag = item.tag {
            // 标签是用户自己写的，比任何统计都更该占据脚注。
            HStack(spacing: metrics.spacing.xxs) {
                SymbolImage(name: "tag", size: metrics.size.clipboardCardIcon * 0.625)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(tag)
                    .font(metrics.typography.cardMeta)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } else if let text = footerText {
            Text(text)
                .font(metrics.typography.cardMeta)
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var footerText: String? {
        switch item.kind {
        case .text:
            if item.colorValue != nil { return item.text }
            if let host = linkHost { return host }
            guard let characterCount else { return nil }
            return String(format: settings.text(ClipboardKey.cardCharacters), characterCount)
        // 图片以预览自我表达，无需脚注。
        case .image: return nil
        case .file:
            return item.filePath.map {
                URL(filePath: $0, directoryHint: .inferFromPath).lastPathComponent
            } ?? settings.text(ClipboardKey.fileKindOther)
        }
    }

    /// 链接卡片以主机名作脚注；无 scheme 的裸域名把主机名留在路径首段。
    private var linkHost: String? {
        guard item.textForm == .link, let text = item.text else { return nil }
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let host = URL(string: token)?.host() { return host }
        return token.split(separator: "/").first.map(String.init)
    }

    /// 字符数在主 actor 之外统计：数 MB 的复制内容不该卡住卡片渲染。
    private func loadCount() async {
        guard item.kind == .text, item.colorValue == nil, let text = item.text else { return }
        characterCount = await Task.detached(priority: .utility) { text.count }.value
    }
}

/// 卡片的相对时间；格式化器按语言构建一次后复用。
@MainActor
private enum CardTime {
    private static var formatter: RelativeDateTimeFormatter?
    private static var cachedIdentifier: String?

    static func text(for date: Date, language: AppLanguage) -> String {
        let identifier = language.localeIdentifier
        if formatter == nil || cachedIdentifier != identifier {
            let built = RelativeDateTimeFormatter()
            built.unitsStyle = .abbreviated
            built.locale = Locale(identifier: identifier)
            formatter = built
            cachedIdentifier = identifier
        }
        return formatter!.localizedString(for: date, relativeTo: Date())
    }
}

/// 来源 App 图标：bundle ID 到路径的 Launch Services 查询每个应用只做一次。
@MainActor
private enum ClipSourceIcons {
    private static var paths: [String: String] = [:]
    /// 解析不到的也记住，避免逐帧重试同一个失效的 bundle ID。
    private static var unresolved: Set<String> = []

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID, let path = resolvedPath(bundleID) else { return nil }
        return IconCache.icon(forFile: path)
    }

    private static func resolvedPath(_ bundleID: String) -> String? {
        if let path = paths[bundleID] { return path }
        if unresolved.contains(bundleID) { return nil }
        guard
            let path = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleID
            )?.path
        else {
            unresolved.insert(bundleID)
            return nil
        }
        paths[bundleID] = path
        return path
    }
}

/// 对自有数据块使用 ImageIO；对引用的文件使用 QuickLook，其类型可能任意。
enum ThumbnailSource {
    case image
    case file

    /// 从缓存读取覆盖式缩略图，未命中（含宽高比未知的首帧）返回 nil。
    func cached(_ url: URL, box: CGSize, scale: CGFloat) -> NSImage? {
        switch self {
        case .image: return ImageThumbnail.cachedCovering(url, box: box, scale: scale)
        case .file: return FilePreviewThumbnail.cachedCovering(url, box: box, scale: scale)
        }
    }

    /// 异步加载覆盖式缩略图。
    func loadAsync(_ url: URL, box: CGSize, scale: CGFloat) async -> NSImage? {
        switch self {
        case .image: return await ImageThumbnail.loadCovering(url, box: box, scale: scale)
        case .file: return await FilePreviewThumbnail.loadCovering(url, box: box, scale: scale)
        }
    }
}

/// 降采样缩略图，未命中缓存时在主线程之外解码；解码长边由显示框、像素密度与宽高比决定。
struct AsyncThumbnail<Content: View, Placeholder: View>: View {
    let url: URL?
    /// 覆盖式显示框（pt）；长图的解码预算随宽高比在此基准上抬高。
    let box: CGSize
    let pixelScale: CGFloat
    /// 不在此处嵌套：主线程外的解码会带上该视图隔离的 `View` 一致性。
    var source: ThumbnailSource = .image
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: NSImage?

    /// 解码请求身份：跨屏移动或界面缩放改变框与密度时重新取图。
    private struct Request: Hashable {
        let url: URL?
        let box: CGSize
        let scale: CGFloat
    }

    var body: some View {
        Group {
            if let image {
                content(Image(nsImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: Request(url: url, box: box, scale: pixelScale)) {
            guard let url, box.width > 0, box.height > 0 else {
                image = nil
                return
            }
            if let hit = source.cached(url, box: box, scale: pixelScale) {
                image = hit
                return
            }
            image = nil  // 新图片解码期间先显示占位图
            image = await source.loadAsync(url, box: box, scale: pixelScale)
        }
    }
}

/// 用于分区的粗略日期分组，按原始值从新到旧排列。
enum DateBucket: Int {
    case today, yesterday, thisWeek, thisMonth, earlier

    /// 该日期分组的显示标题（英文）；保留给尚未迁移的调用点，界面请改用 `localizedTitle(_:)`。
    var title: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "This Week"
        case .thisMonth: return "This Month"
        case .earlier: return "Earlier"
        }
    }

    /// 按界面语言给出的分组标题。
    func localizedTitle(_ language: AppLanguage) -> String {
        let key: ClipboardKey =
            switch self {
            case .today: .bucketToday
            case .yesterday: .bucketYesterday
            case .thisWeek: .bucketThisWeek
            case .thisMonth: .bucketThisMonth
            case .earlier: .bucketEarlier
            }
        return L10n.string(key, language: language)
    }

    /// 按给定日期与参考时间计算所属的日期分组。
    init(for date: Date, now: Date = Date(), calendar: Calendar = .current) {
        if calendar.isDateInToday(date) {
            self = .today
        } else if calendar.isDateInYesterday(date) {
            self = .yesterday
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            self = .thisWeek
        } else if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            self = .thisMonth
        } else {
            self = .earlier
        }
    }
}
