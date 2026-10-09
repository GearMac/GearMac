// 文件职责：快捷链接列表与其右侧详情预览的 SwiftUI 视图，包括置顶/普通分组标题、行图标与快捷键胶囊、以及「信息」区块。
// 分层：UI；仅读取 `Quicklink` 与 `HotKeyManager`/`AppIndex` 环境依赖，不写任何持久状态。
import AppKit
import SwiftUI

/// 「搜索快捷链接」屏幕的列表视图：完整链接库，置顶条目优先。
struct QuicklinkList: View {
    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    let results: [Quicklink]
    let selectedID: Quicklink.ID?
    /// 仅在列表需要滚动时才变化，因此鼠标选择不会抽动滚动位置。
    let scroll: ScrollIntent
    let onSelect: (Quicklink) -> Void
    let onActivate: () -> Void
    let onActions: (Quicklink) -> Void

    /// 列表渲染项：分组标题或快捷链接行，二者共用基于字符串的 id。
    private enum Row: Identifiable {
        case header(String)
        case item(Quicklink)
        var id: String {
            switch self {
            case .header(let title): return "header-" + title
            case .item(let quicklink): return quicklink.id.uuidString
            }
        }
    }

    /// 选中项是否位于扁平索引 0，此时其分组标题应保持可见。
    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == results.first?.id
    }

    /// store 按置顶优先的顺序发布数据，因此这里只在唯一的边界处输出一个分组标题。
    private var rows: [Row] {
        var rows: [Row] = []
        var currentTitle: String?
        for quicklink in results {
            let title =
                quicklink.isPinned
                ? settings.text(QuicklinksKey.listPinned) : settings.text(QuicklinksKey.listQuicklinks)
            if title != currentTitle {
                rows.append(.header(title))
                currentTitle = title
            }
            rows.append(.item(quicklink))
        }
        return rows
    }

    var body: some View {
        let rows = rows
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        switch row {
                        case .header(let title):
                            SectionHeader(title: title, isFirst: row.id == rows.first?.id)
                        case .item(let quicklink):
                            QuicklinkRow(
                                quicklink: quicklink, selected: quicklink.id == selectedID
                            )
                            .selectionFrame(quicklink.id == selectedID)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(quicklink) }
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    onSelect(quicklink)
                                    onActivate()
                                }
                            )
                            .onRightClick { onActions(quicklink) }
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
                scroll, row: selectedID?.uuidString, atOrigin: firstRowSelected, proxy: proxy)
        }
    }
}

private struct QuicklinkRow: View {

    @Environment(\.metrics) private var metrics
    let quicklink: Quicklink
    let selected: Bool
    @Environment(HotKeyManager.self) private var hotKeys
    @State private var hovered = false

    /// 行同时处于选中与悬停时以选中优先；否则悬停显示更浅的一层背景。
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        IconCache.observeStyle()
        return HStack(spacing: metrics.spacing.lg) {
            Image(nsImage: IconCache.symbolIcon(named: quicklink.symbol))
                .resizable()
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            VStack(alignment: .leading, spacing: metrics.spacing.xxs) {
                Text(quicklink.name)
                    .font(metrics.typography.rowTitle)
                    .lineLimit(1)
                Text(quicklink.link)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: metrics.spacing.lg)
            if !quicklink.showsInRootSearch {
                Image(systemName: "eye.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            if let keycaps = hotKeys.binding(for: .quicklink(id: quicklink.id))?.keycaps {
                HStack(spacing: metrics.spacing.xxs) {
                    ForEach(Array(keycaps.enumerated()), id: \.offset) { _, cap in
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
    }
}

/// 列表旁的详情面板，与「搜索代码片段」预览高亮片段的方式一致。
struct QuicklinkPreview: View {
    @Environment(\.metrics) private var metrics
    let quicklink: Quicklink?

    var body: some View {
        if let quicklink {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                SymbolImage(name: quicklink.symbol, size: Self.glyphSize)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, metrics.spacing.xl)
                Spacer(minLength: 0)
                QuicklinkInfoSection(quicklink: quicklink)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 12)
        } else {
            Color.clear
        }
    }

    /// 尺寸足以当作图示阅读，而不会被误认为放大的行图标。
    private static let glyphSize: CGFloat = 64
}

/// 「信息」区块；其中内容都已在内存中，因此无需在主线程之外收集数据。
private struct QuicklinkInfoSection: View {
    @Environment(\.metrics) private var metrics
    let quicklink: Quicklink
    @Environment(HotKeyManager.self) private var hotKeys
    @Environment(AppIndex.self) private var appIndex
    @Environment(AppSettings.self) private var settings

    /// 详情面板中的一行：标签与值，以标签作为 id。
    private struct InfoRow: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    /// 相对日期加精确时间；因 `DateFormatter` 构建开销大而共享同一实例。
    @MainActor private static let createdFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    /// 详情面板展示的信息行；随「打开方式」「快捷键」等可选数据动态增减。
    private var rows: [InfoRow] {
        var rows = [
            InfoRow(label: settings.text(QuicklinksKey.infoName), value: quicklink.name),
            InfoRow(label: settings.text(QuicklinksKey.infoLink), value: quicklink.link)
        ]
        if let bundleID = quicklink.openWithBundleID {
            rows.append(
                InfoRow(
                    label: settings.text(QuicklinksKey.infoOpenWith),
                    value: AppPresentation.resolve(bundleID: bundleID, in: appIndex).name))
        }
        if let keycaps = hotKeys.binding(for: .quicklink(id: quicklink.id))?.keycaps {
            rows.append(InfoRow(label: settings.text(QuicklinksKey.infoShortcut), value: keycaps.joined()))
        }
        rows.append(
            InfoRow(
                label: settings.text(QuicklinksKey.infoCreated),
                value: Self.createdFormatter.string(from: quicklink.createdAt)))
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            Text(settings.text(QuicklinksKey.infoTitle))
                .font(metrics.typography.sectionHeader)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                let rows = self.rows
                ForEach(rows) { row in
                    if row.id != rows.first?.id { Divider() }
                    HStack(spacing: metrics.spacing.sm) {
                        Text(row.label).foregroundStyle(.secondary)
                        Spacer(minLength: metrics.spacing.lg)
                        Text(row.value).lineLimit(1).truncationMode(.middle)
                    }
                    .font(metrics.typography.keyCap)
                    .padding(.vertical, metrics.spacing.xs)
                }
            }
        }
        .padding(.vertical, metrics.spacing.md)
    }
}
