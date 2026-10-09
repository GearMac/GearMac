// 文件职责：渲染启动器结果列表：分组标题、前置卡片、收藏/日程/建议/分类分组、兜底区块与行视图。
// 分层：UI；只读 AppEntry 与传入的回调，不直接触发副作用。
import SwiftUI

/// 启动器结果列表：把扁平的结果数组转换为带分组标题的行列表并渲染。
struct LauncherList: View {

    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    let results: [AppEntry]
    /// 界面选中的扁平行 id，而非条目 id：兜底区块可能重复出现某个结果。
    let selectedRowID: String?
    let favoriteCount: Int
    let meetingCount: Int
    let suggestionCount: Int
    let showSections: Bool
    /// 仅当列表需要滚动时才变化，因此鼠标选择不会把它拽动。
    let scroll: ScrollIntent
    /// 位于扁平索引 0 的卡片（当有卡片时）。最多只会有一张。
    var card: LeadCard?
    var cardSelected = false
    var onActivateCard: () -> Void = {}
    var onCardActions: () -> Void = {}
    let onActivate: (AppEntry) -> Void
    let onActions: (AppEntry) -> Void
    let onDropped: () -> Void
    /// 即 `Use "…" with` 区块，始终位于最后；未输入内容时为 nil。
    var fallbacks: FallbackSection?
    @Environment(RunningAppsMonitor.self) private var runningApps

    /// 兜底区块绘制什么、其行去往何处，均以位置索引寻址。
    struct FallbackSection {
        let title: String
        let entries: [AppEntry]
        let onActivate: (Int) -> Void
        let onActions: (Int) -> Void
        let onConfigure: () -> Void
    }

    /// 计算器回应已输入的查询，而卡片回应空查询，因此只会有一张卡片置顶。
    enum LeadCard: Equatable {
        case calc(CalcResult)
        case meeting(MeetingEvent, now: Date)
        case color(ColorValue)

        func sectionTitle(_ language: AppLanguage) -> String {
            switch self {
            case .calc: return L10n.string(LauncherKey.cardCalculator, language: language)
            case .meeting: return L10n.string(LauncherKey.cardMeeting, language: language)
            case .color: return L10n.string(LauncherKey.cardColor, language: language)
            }
        }
        var rowID: String {
            switch self {
            case .calc: return "calc-card"
            case .meeting: return "meeting-card"
            case .color: return "color-card"
            }
        }
    }

    private enum Row: Identifiable {
        case header(String)
        /// 单独一种 case：只有这个标题带有齿轮按钮。
        case fallbackHeader(String)
        case card(LeadCard)
        /// `slot` 是该行的 ⌘ 数字，随分组构建一并传入，而非事后查找。
        case app(AppEntry, slot: Character?)
        case fallback(AppEntry, index: Int)
        var id: String {
            switch self {
            case .header(let title): return "header-" + title
            case .fallbackHeader: return "fallback-header"
            case .card(let card): return card.rowID
            case .app(let app, _): return app.id
            case .fallback(let app, _): return "fallback-" + app.id
            }
        }
    }

    /// 选中项是否位于扁平索引 0：有卡片时为卡片，否则为第一个结果。
    private var firstRowSelected: Bool {
        card != nil ? cardSelected : selectedRowID != nil && selectedRowID == results.first?.id
    }

    /// 兜底区块贡献的所有行，始终排在结果之后。
    private var fallbackRows: [Row] {
        guard let fallbacks else { return [] }
        return [.fallbackHeader(fallbacks.title)]
            + fallbacks.entries.enumerated().map { Row.fallback($1, index: $0) }
    }

    /// 把结果按收藏/日程/建议/类型分组，拼上卡片行与兜底行，构成最终的行列表。
    private var rows: [Row] {
        var cardRows: [Row] = []
        if let card { cardRows = [.header(card.sectionTitle(settings.language)), .card(card)] }
        guard showSections else {
            guard !results.isEmpty else { return cardRows + fallbackRows }
            return cardRows + [.header(settings.text(LauncherKey.sectionResults))]
                + results.map { .app($0, slot: nil) }
                + fallbackRows
        }
        var rows: [Row] = cardRows
        let favorites = results.prefix(favoriteCount)
        let meetings = results.dropFirst(favoriteCount).prefix(meetingCount)
        let suggestions = results.dropFirst(favoriteCount + meetingCount).prefix(suggestionCount)
        let rest = results.dropFirst(favoriteCount + meetingCount + suggestionCount)
        var grouped: [AppEntry.Kind: [AppEntry]] = [:]
        for app in rest { grouped[app.kind, default: []].append(app) }
        if !favorites.isEmpty {
            rows.append(.header(settings.text(LauncherKey.sectionFavorites)))
            rows.append(
                contentsOf: favorites.enumerated().map {
                    .app($1, slot: FavoriteSlots.digit(at: $0))
                })
        }
        if !meetings.isEmpty {
            rows.append(.header(settings.text(LauncherKey.kindMeetingSection)))
            rows.append(contentsOf: meetings.map { .app($0, slot: nil) })
        }
        if !suggestions.isEmpty {
            rows.append(.header(settings.text(LauncherKey.sectionSuggestions)))
            rows.append(contentsOf: suggestions.map { .app($0, slot: nil) })
        }
        // 按发布顺序排列，使行与其扁平索引一致。
        let kinds: [AppEntry.Kind] = [
            .meeting, .application, .systemSettings, .extensionCommand, .quicklink, .appleShortcut,
            .snippet, .systemAction, .windowLayout, .windowRoom, .windowCommand, .customCommand,
            .quickAction, .command
        ]
        for kind in kinds {
            guard let group = grouped[kind], !group.isEmpty else { continue }
            rows.append(.header(settings.text(kind.sectionTitleKey)))
            rows.append(contentsOf: group.map { .app($0, slot: nil) })
        }
        // 若有类型遗漏，其后每一行的激活都会落到相邻行上，因此这里用断言代替静默。
        assert(
            grouped.keys.allSatisfy(kinds.contains),
            "kind missing from the launcher's section order: "
                + grouped.keys.filter { !kinds.contains($0) }.map(\.rawValue).joined(separator: ", "))
        return rows + fallbackRows
    }

    /// 结果为空且无卡片与兜底时显示空态，否则渲染可滚动、随选中项滚动的行列表。
    var body: some View {
        let rows = rows
        return Group {
            if results.isEmpty && card == nil && fallbacks == nil {
                EmptyResults(text: settings.text(LauncherKey.emptyNoApps))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { row in
                                switch row {
                                case .header(let title):
                                    SectionHeader(title: title, isFirst: row.id == rows.first?.id)
                                case .fallbackHeader(let title):
                                    SectionHeader(
                                        title: title, isFirst: row.id == rows.first?.id,
                                        configure: fallbacks?.onConfigure,
                                        configureHelp: settings.text(LauncherKey.configureFallbacks))
                                case .card(let card):
                                    LeadCardView(card: card, selected: cardSelected)
                                        .contentShape(Rectangle())
                                        .onTapGesture(perform: onActivateCard)
                                        .onRightClick(perform: onCardActions)
                                        .padding(.bottom, metrics.spacing.xs)
                                        .selectionFrame(cardSelected)
                                case .app(let app, let slot):
                                    AppRow(
                                        app: app,
                                        selected: app.id == selectedRowID,
                                        running: runningApps.isRunning(app),
                                        slot: slot
                                    )
                                    .contentShape(Rectangle())
                                    .onRowTap(drag: drag(for: app)) { onActivate(app) }
                                    .onRightClick { onActions(app) }
                                    .selectionFrame(app.id == selectedRowID)
                                case .fallback(let app, let index):
                                    AppRow(
                                        app: app, selected: row.id == selectedRowID, running: false,
                                        slot: nil
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture { fallbacks?.onActivate(index) }
                                    .onRightClick { fallbacks?.onActions(index) }
                                    .selectionFrame(row.id == selectedRowID)
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
                    // 选中第一行时吸附到顶部原点，以便其分组标题也可见。
                    .scrollFollowsSelection(
                        scroll, row: selectedRowID, atOrigin: firstRowSelected, proxy: proxy)
                }
            }
        }
    }

    /// 仅用缓存的图标：行自带较小的位图，而解码会阻塞拖拽。
    private func drag(for app: AppEntry) -> RowDrag? {
        guard app.canDragOut else { return nil }
        return RowDrag(
            item: { .file(app.url, image: IconCache.cached(app.iconSource, fileURL: app.url)) },
            dropped: onDropped)
    }
}

/// 绘制当前置顶的卡片；每种卡片的外观仍由其对应功能自行决定。
private struct LeadCardView: View {
    let card: LauncherList.LeadCard
    let selected: Bool

    /// 按卡片类型转发到对应的卡片视图。
    var body: some View {
        switch card {
        case .calc(let result):
            CalculatorCard(result: result, selected: selected)
        case .meeting(let meeting, let now):
            MeetingCard(meeting: meeting, now: now, selected: selected)
        case .color(let color):
            ColorCard(color: color, selected: selected)
        }
    }
}

/// 结果列表中的单行：图标、名称、副标题、别名、快捷键键帽与运行/刷新指示。
private struct AppRow: View {

    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    let app: AppEntry
    let selected: Bool
    let running: Bool
    /// 该行的 ⌘ 数字；没有任何快捷键启动的行此处为 nil。
    let slot: Character?
    /// 监听它以便在设置中新增/清除快捷键时立即重绘本行的键帽。
    @Environment(HotKeyManager.self) private var hotKeys
    /// 出于同样原因监听：别名修改后立即重绘本行的徽标。
    @Environment(AliasStore.self) private var aliases
    /// 在此处而非列表上层监听，使按下 ⌘ 只重绘行而不重绘整个面板。
    @Environment(PaletteState.self) private var palette
    @State private var hovered = false

    /// 同时选中与悬停时选中优先；否则悬停显示更浅的一层。
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    /// 该条目热键的键帽；未绑定任何热键时为 `nil`。
    private var shortcutCaps: [String]? {
        guard let action = app.hotKeyAction else { return nil }
        return hotKeys.binding(for: action)?.keycaps
    }

    /// 渲染单行内容：图标、名称、副标题、别名键帽与尾部状态。
    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            AppIconView(app: app, pointSize: metrics.size.resultRowIcon)
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
                .overlay(alignment: .bottom) {
                    if running {
                        Circle()
                            .fill(.secondary)
                            .frame(width: 3, height: 3)
                            .offset(y: 3)
                    }
                }
            if app.kind == .meeting {
                MeetingEntryContent(entryID: app.id) { meeting, _ in
                    CalendarBar(color: meeting.calendarColor)
                }
            }
            Text(app.name)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
            if let subtitle = app.subtitle {
                Text(subtitle)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let alias = aliases.alias(for: app.preferenceKey) {
                Text(alias)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, metrics.spacing.sm)
                    .padding(.vertical, metrics.spacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: metrics.radius.menu, style: .continuous)
                            .fill(Theme.Colors.controlSurface))
            }
            if let caps = shortcutCaps {
                HStack(spacing: metrics.spacing.xxs) {
                    ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                        KeyCapChip(text: cap, style: .outline)
                    }
                }
            }
            Spacer()
            if let refresh = app.backgroundRefresh {
                ExtensionRefreshIndicator(state: refresh)
                    .font(metrics.typography.rowTrailing)
            }
            // 按住 ⌘ 时，尾部文案会变成启动该行的快捷键组合。
            if let slot, palette.commandHeld {
                HStack(spacing: metrics.spacing.xxs) {
                    KeyCapChip(text: "⌘", style: .outline)
                    KeyCapChip(text: String(slot), style: .outline)
                }
            } else if app.kind == .meeting {
                MeetingEntryContent(entryID: app.id) { MeetingTiming(meeting: $0, now: $1) }
            } else {
                Text(app.kindLabel(settings.language))
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
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
