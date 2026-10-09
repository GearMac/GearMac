// 文件职责：启动器的根搜索界面：计算/日程/颜色卡片置顶，随后是收藏、日程、建议与各类型分组，末尾为兜底区块。
// 分层：UI（PaletteScreen）；自身解析查询结果与卡片，选中/滚动交给 PaletteState，动作通过 AppCore 分派。
import SwiftUI

/// 根搜索界面：先收藏、日程、建议，再按类型分组，可能由一张卡片置顶。
struct LauncherScreen: PaletteScreen {
    let appIndex: AppIndex
    let favorites: FavoritesStore
    let visibility: VisibilityStore
    let core: AppCore
    let vm: PaletteState
    /// 由 `openActions` 采样，使菜单弹出期间 Restart 与 Quit 不会漂移。
    let running: Bool
    /// 加入会议卡片对应的日程，由 Coordinator 解析；没有进行中的会议时为 nil。
    let meeting: MeetingEvent?
    let now: Date
    let openActions: () -> Void
    /// 为 `options=` 字段打开面板自身的菜单，以参数名为键。
    let openArgumentOptions: (String) -> Void
    /// 当某个动作使列表重排时调用，使高亮滚动回可视区域。
    let scrollToFollow: () -> Void

    /// 唯一的有序结果列表；空查询会把收藏固定在排序结果之上。
    private let results: [AppEntry]
    private let calc: CalcResult?
    /// 查询本身拼出的颜色（若确为颜色）；其它查询下为 nil。
    private let color: ColorValue?
    /// 分组区块用于替代排序的 Results 列表，而输入查询时后者会折叠掉。
    private let showSections: Bool
    /// 只有空查询会固定收藏——分类查询展示各自的分组而不另设收藏分组。
    private let pinsFavorites: Bool
    /// `results` 中有多少是固定收藏；分组不显示时为 0。
    private let favoriteCount: Int
    /// 收藏之后作为 Meetings 的数量；输入框非空时为 0。
    private let meetingCount: Int
    /// 日程之后作为 Suggestions 的数量；输入框非空时为 0。
    private let suggestionCount: Int
    /// 即 `Use "…" with` 区块，位于所有结果之下；未输入内容时为空。
    private let fallbacks: [(fallback: Fallback, entry: AppEntry)]
    /// 在 `init` 中解析完成：面板每次事件会多次索引它，因此不能重复计算。
    let rows: [Row]

    /// 解析查询得到排序结果、卡片、兜底与各分组计数，并据此预算出最终行列表。
    init(
        appIndex: AppIndex, favorites: FavoritesStore, visibility: VisibilityStore,
        currencyRates: CurrencyRateStore, core: AppCore, vm: PaletteState, running: Bool,
        meeting: MeetingEvent?, now: Date,
        openActions: @escaping () -> Void, openArgumentOptions: @escaping (String) -> Void,
        scrollToFollow: @escaping () -> Void
    ) {
        self.appIndex = appIndex
        self.favorites = favorites
        self.visibility = visibility
        self.core = core
        self.vm = vm
        self.running = running
        self.now = now
        self.openActions = openActions
        self.openArgumentOptions = openArgumentOptions
        self.scrollToFollow = scrollToFollow

        // 即便已从搜索中隐藏也仍要列出：打开它的快捷键仍需得到响应。
        let pinned = vm.argumentEntryID.flatMap(core.customCommands.command(entryID:))
            .map(AppEntry.init).flatMap { $0.name == vm.query ? $0 : nil }
        let ordered =
            pinned.map { AppIndex.Results(entries: [$0]) }
            ?? appIndex.orderedResults(
                query: vm.query, visibility: visibility, favorites: favorites, hotKeys: core.hotKeys)
        var results = ordered.entries
        // 输入的网址置于最前：索引中没有任何条目能更好地回应它。
        if pinned == nil, let browser = CommandCatalog.openInBrowser(for: vm.query),
            visibility.isVisible(browser)
        {
            results.insert(browser, at: 0)
        }
        // 固定行之上不放卡片：它的字段依附于选中项，而选中必须从它开始。
        let calc =
            pinned == nil
            ? CalcMemo.evaluate(vm.query, rates: currencyRates.rates, format: core.calcNumberFormat) : nil
        // 排在计算器之后：`#FF5733` 不是算术，因此两者不会同时回应。
        let color = calc == nil && pinned == nil ? ColorValue.parse(vm.query) : nil
        let fallbacks = core.fallbackCoordinator.entries(for: vm.query)
        let entries = results.map(Row.entry) + fallbacks.map { Row.fallback($0.fallback, $0.entry) }
        let pinsFavorites = vm.query.trimmingCharacters(in: .whitespaces).isEmpty
        // 最多只有一个置顶，因此扁平索引只保留一行偏移。
        let meeting = pinsFavorites ? meeting : nil
        self.meeting = meeting
        self.results = results
        self.calc = calc
        self.fallbacks = fallbacks
        self.color = color
        self.showSections = pinsFavorites || AppEntry.Kind.named(by: vm.query) != nil
        self.pinsFavorites = pinsFavorites
        self.favoriteCount = pinsFavorites ? ordered.favoriteCount : 0
        self.meetingCount = pinsFavorites ? ordered.meetingCount : 0
        self.suggestionCount = pinsFavorites ? ordered.suggestionCount : 0
        if let calc {
            self.rows = [.calc(calc)] + entries
        } else if let color {
            self.rows = [.color(color)] + entries
        } else if let meeting {
            self.rows = [.meeting(meeting)] + entries
        } else {
            self.rows = entries
        }
    }

    /// 卡片与其它行一样也是一行，因此扁平选中可直接索引 `rows` 而无需偏移。
    enum Row: Equatable, Identifiable {
        case calc(CalcResult)
        case meeting(MeetingEvent)
        case color(ColorValue)
        case entry(AppEntry)
        /// 加前缀，因为同一条命令也可能作为排序命中出现在其兜底行之上。
        case fallback(Fallback, AppEntry)

        var id: String {
            switch self {
            case .calc: return "calc-card"
            case .meeting: return "meeting-card"
            case .color: return "color-card"
            case .entry(let app): return app.id
            case .fallback(let fallback, _): return "fallback-" + fallback.id
            }
        }
    }

    /// 胶囊按钮不携带选中项，因此此处套用与面板相同的钳制。
    private var clampedSelection: Int {
        let count = rows.count
        return count == 0 ? 0 : min(max(vm.selection, 0), count - 1)
    }

    /// 当前选中行的主操作标题，用于底部胶囊按钮。
    var primaryActionTitle: String {
        switch row(at: clampedSelection) {
        case .calc: return core.settings.text(LauncherKey.copyAnswer)
        case .color: return core.settings.text(LauncherKey.copyColor)
        case .meeting(let meeting):
            return core.settings.text(
                meeting.link == nil ? LauncherKey.openInCalendar : LauncherKey.joinMeeting)
        case .entry(let app): return core.settings.text(app.kind.openVerbKey)
        case .fallback(let fallback, _): return fallback.openVerb(core.settings.language)
        case nil: return core.settings.text(LauncherKey.openApplication)
        }
    }

    private func row(at selection: Int) -> Row? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    /// 具体控件由对应功能决定；此处只做转发。
    func headerAccessory(
        at selection: Int, focus: FocusState<String?>.Binding
    )
        -> PaletteHeaderAccessory?
    {
        guard let entry = entry(at: selection) else { return nil }
        // 快捷链接在根搜索中同样需要填写取值，因此兜底始终不会离开它。
        if entry.kind == .quicklink {
            return QuicklinkArgumentsAccessory.make(
                quicklink: quicklink(for: entry), core: core, vm: vm, focus: focus,
                placement: .afterQuery, onOpenOptions: openArgumentOptions,
                onSubmit: { activate(at: selection) })
        }
        if entry.kind == .customCommand {
            return CustomCommandArgumentsAccessory.make(
                command: core.customCommands.command(entryID: entry.id), vm: vm,
                metrics: core.settings.interfaceSize.metrics, focus: focus,
                onSubmit: { activate(at: selection) })
        }
        return ExtensionArgumentsAccessory.make(
            entry: entry, coordinator: core.extensionCoordinator,
            values: { name in headerFieldBinding(entry: entry, name: name) },
            focus: focus, metrics: core.settings.interfaceSize.metrics,
            onSubmit: { activate(at: selection) })
    }

    /// 该行某个参数对应的输入框绑定，写回 `vm.commandArguments`。
    private func headerFieldBinding(entry: AppEntry, name: String) -> Binding<String> {
        let key = PaletteState.argumentKey(entry.id, name)
        return Binding(get: { vm.commandArguments[key] ?? "" }, set: { vm.commandArguments[key] = $0 })
    }

    /// 某一行已输入的参数值（剔除空值）——即将交给命令的内容。
    private func argumentValues(for entry: AppEntry) -> [String: String] {
        if entry.kind == .quicklink {
            guard let quicklink = quicklink(for: entry) else { return [:] }
            return QuicklinkArgumentsAccessory.values(for: quicklink, core: core, vm: vm)
        }
        if entry.kind == .customCommand {
            guard let command = core.customCommands.command(entryID: entry.id) else { return [:] }
            return CustomCommandArgumentsAccessory.values(for: command, vm: vm)
        }
        var values: [String: String] = [:]
        for argument in core.extensionCoordinator.commandArguments(for: entry) ?? [] {
            let typed = vm.commandArguments[PaletteState.argumentKey(entry.id, argument.name)] ?? ""
            if !typed.isEmpty { values[argument.name] = typed }
        }
        return values
    }

    /// 由条目 id 反查其快捷链接。
    private func quicklink(for entry: AppEntry) -> Quicklink? {
        Quicklink.id(fromEntryID: entry.id).flatMap(core.quicklinks.quicklink)
    }

    /// 取出该扁平索引处的条目；非条目的行返回 nil。
    private func entry(at selection: Int) -> AppEntry? {
        guard case .entry(let app) = row(at: selection) else { return nil }
        return app
    }

    /// 该扁平索引是否落在卡片上。
    private func isCardSelected(_ selection: Int) -> Bool {
        switch row(at: selection) {
        case .calc, .meeting, .color: return true
        case .entry, .fallback, nil: return false
        }
    }

    /// 当前置顶的卡片，按列表绘制它时所需的类型表示。
    private var leadCard: LauncherList.LeadCard? {
        if let calc { return .calc(calc) }
        if let color { return .color(color) }
        return meeting.map { .meeting($0, now: now) }
    }

    /// 错误卡片可被选中但没有动作：它既不应驱动底部胶囊，也不应驱动 ⌘K。
    func hasPrimaryAction(at selection: Int) -> Bool {
        guard case .calc(let result) = row(at: selection) else { return true }
        return result.isActionable
    }

    /// 当前选中行的操作菜单内容；错误卡片与空选中返回 nil。
    func actions(at selection: Int) -> PopoverMenuContent? {
        switch row(at: selection) {
        case .calc(let result):
            return result.isActionable ? CalcActionsMenu.content(result: result, core: core) : nil
        case .color(let color):
            return ColorActionsMenu.content(color: color, core: core)
        case .meeting(let meeting):
            return MeetingActionsMenu.content(meeting: meeting, core: core)
        case .entry(let app):
            return AppActionsMenu.content(
                app: app, searchQuery: vm.query, core: core, running: running,
                favorites: favoriteActions(for: app, at: selection),
                onResetRanking: {
                    core.launcherCoordinator.resetRanking(for: app)
                    // 重置可能移动该条目；让高亮留在执行该动作的条目上。
                    if let index = rows.firstIndex(of: .entry(app)) { vm.selection = index }
                },
                onHideFromSearch: { _ = hideFromSearch(at: selection) })
        case .fallback(let fallback, let app):
            return FallbackActionsMenu.content(
                fallback: fallback, entry: app, query: vm.query, core: core)
        case nil:
            return nil
        }
    }

    /// 激活当前选中行：按行类型复制/打开/启动或运行兜底。
    func activate(at selection: Int) {
        switch row(at: selection) {
        // 错误卡片无操作——copyCalculatorResult 只作用于数值载荷。
        case .calc(let result): core.calculatorCoordinator.copyCalculatorResult(result)
        case .color(let color):
            core.clipboardCoordinator.copyColor(color, as: ColorFormat.primary(for: color))
        case .meeting(let meeting): core.calendarCoordinator.activateMeeting(id: meeting.id)
        case .entry(let app):
            core.launcherCoordinator.launch(
                app, searchQuery: vm.query, arguments: argumentValues(for: app))
        case .fallback(let fallback, _):
            core.fallbackCoordinator.run(fallback, query: vm.query)
        case nil: break
        }
    }

    /// 卡片对应的日程或日程行的日程；两者都响应日程菜单的快捷键。
    private func meeting(at selection: Int) -> MeetingEvent? {
        switch row(at: selection) {
        case .meeting(let meeting): return meeting
        case .entry(let app) where app.kind == .meeting:
            return core.calendarCoordinator.meeting(entryID: app.id)
        default: return nil
        }
    }

    /// ⌘↵——日程复制其链接，答案回填为查询，磁盘上的条目则在 Finder 中显示。
    func secondary(at selection: Int) -> Bool {
        if let meeting = meeting(at: selection) {
            return MeetingActionsMenu.secondary(meeting: meeting, core: core)
        }
        if case .calc(let result) = row(at: selection) {
            return core.calculatorCoordinator.putAnswerInSearchBar(result)
        }
        guard let app = entry(at: selection), app.canRevealInFinder else { return false }
        core.launcherCoordinator.showInFinder(app)
        return true
    }

    /// 仅当 `.application` 条目被 `RunningAppsMonitor` 报告为运行中时才提供。
    private func runningApplication(at selection: Int) -> AppEntry? {
        guard let app = entry(at: selection), app.kind == .application,
            core.runningApps.isRunning(app)
        else { return nil }
        return app
    }

    /// 处理面板快捷键：收藏、隐藏、退出、重启、收藏位启动与复制计算等。
    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .toggleFavorite: return toggleFavorite(at: selection)
        case .hideFromSearch: return hideFromSearch(at: selection)
        case .quit, .forceQuit: return quit(at: selection, force: shortcut == .forceQuit)
        case .restart: return restart(at: selection)
        case .favoriteSlot(let index): return launchFavorite(at: index)
        case .copyCalculation: return copyCalculation(at: selection)
        case .openInApp, .showDetails:
            guard let meeting = meeting(at: selection) else { return false }
            return MeetingActionsMenu.perform(shortcut, meeting: meeting, core: core)
        default: return false
        }
    }

    /// ⌘C——复制计算结果连同其表达式；错误卡片返回 false。
    private func copyCalculation(at selection: Int) -> Bool {
        guard case .calc(let result) = row(at: selection), result.isActionable else { return false }
        core.calculatorCoordinator.copyCalculationWithExpression(result)
        return true
    }

    /// ⌃⇧Q 或 ⌃⌥⇧Q——组合键由本界面处理，但只有运行中的应用才可退出。
    private func quit(at selection: Int, force: Bool) -> Bool {
        guard let app = runningApplication(at: selection) else { return false }
        core.launcherCoordinator.quit(app, force: force)
        return true
    }

    /// ⌘R——等价于菜单中的 Restart Application。
    private func restart(at selection: Int) -> Bool {
        guard let app = runningApplication(at: selection) else { return false }
        core.launcherCoordinator.restart(app)
        return true
    }

    /// 高亮保持在 Favorites 内：新增时停在顶部，移除时上移到前一个邻居。
    private func toggleFavorite(at selection: Int) -> Bool {
        guard let app = entry(at: selection), !CommandCatalog.isQueryDriven(app) else { return false }
        let removed = favoriteIndex(of: app)
        favorites.toggle(app)
        // 输入查询时不固定收藏，因此没有移动，高亮保持不变。
        guard pinsFavorites else { return true }
        selectFavorite(at: removed.map { $0 - 1 } ?? 0)
        return true
    }

    /// ⌘1–⌘9/⌘0——按位置启动收藏，适用于两种面板尺寸。
    private func launchFavorite(at index: Int) -> Bool {
        guard let app = pinnedFavorites.dropFirst(index).first else { return false }
        core.launcherCoordinator.launch(app)
        return true
    }

    /// 输入查询时为空，这也是该分组唯一离屏的状态。
    private var pinnedFavorites: ArraySlice<AppEntry> { results.prefix(favoriteCount) }

    /// ⌥⌘↑/↓——与相邻收藏交换；分组的首尾没有可交换的方向。
    func moveFavorite(_ delta: Int, at selection: Int) -> Bool {
        guard let app = entry(at: selection), let index = favoriteIndex(of: app) else { return false }
        let target = index + delta
        guard target >= 0, target < favoriteCount else { return false }
        favorites.exchange(favorites.key(for: app), with: favorites.key(for: results[target]))
        follow(app)
        return true
    }

    /// 首尾会丢弃无法执行的移动；两个方向的行都回到此处，永不漂移。
    private func favoriteActions(
        for app: AppEntry, at selection: Int
    )
        -> AppActionsMenu.FavoriteActions
    {
        let index = favoriteIndex(of: app)
        return AppActionsMenu.FavoriteActions(
            isFavorite: favorites.isFavorite(app),
            canMoveUp: index.map { $0 > 0 } ?? false,
            canMoveDown: index.map { $0 < favoriteCount - 1 } ?? false,
            toggle: { _ = toggleFavorite(at: selection) },
            move: { _ = moveFavorite($0, at: selection) })
    }

    /// 在 Favorites 分组中的位置；该条目在此不可重排时为 nil。
    private func favoriteIndex(of app: AppEntry) -> Int? {
        guard let index = results.firstIndex(of: app), index < favoriteCount else { return nil }
        return index
    }

    /// ⇧⌘H——该行将永久离开列表，因此高亮接管它空出的位置。
    private func hideFromSearch(at selection: Int) -> Bool {
        guard let app = entry(at: selection), app.canHideFromSearch,
            !CommandCatalog.isQueryDriven(app), let index = results.firstIndex(of: app)
        else { return false }
        visibility.setItemVisible(false, for: app)
        select(row: min(index, max(reorderedResults().entries.count - 1, 0)))
        return true
    }

    /// 动作会让列表重排；把高亮与滚动都保持在移动后的那一行上。
    private func follow(_ app: AppEntry) {
        guard let index = reorderedResults().entries.firstIndex(of: app) else { return }
        select(row: index)
    }

    /// 高亮 Favorites 分组中的某一行，并钳制到该分组当前的范围。
    private func selectFavorite(at index: Int) {
        let count = reorderedResults().favoriteCount
        select(row: min(max(index, 0), max(count - 1, 0)))
    }

    /// 重新读取刚被改动失效的顺序；这也会预热下次渲染将读取的键。
    private func reorderedResults() -> AppIndex.Results {
        appIndex.orderedResults(
            query: vm.query, visibility: visibility, favorites: favorites, hotKeys: core.hotKeys)
    }

    /// 设置选中项并请求滚动跟随；有卡片时整体偏移一行。
    private func select(row index: Int) {
        vm.selection = index + (leadCard == nil ? 0 : 1)
        scrollToFollow()
    }

    /// `openActions` 采样所用的值；只有应用行才可能带有仅运行时可用的动作。
    func isRunning(at selection: Int) -> Bool {
        guard let app = entry(at: selection) else { return false }
        return core.runningApps.isRunning(app)
    }

    /// 紧凑栏的图标：前五个收藏。紧随其后的「…」不算在内。
    var compactFavorites: [AppEntry] { Array(pinnedFavorites.prefix(5)) }

    /// 紧凑栏的「…」是否还有可展开的内容。
    var hasUnshownFavorites: Bool { favoriteCount > compactFavorites.count }

    /// PaletteScreen 入口：返回以 AnyView 包装的内容视图。
    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    /// 组装 LauncherList 并接线卡片、行与兜底的各类回调。
    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        LauncherList(
            results: results,
            selectedRowID: row(at: selection)?.id,
            favoriteCount: favoriteCount,
            meetingCount: meetingCount,
            suggestionCount: suggestionCount,
            showSections: showSections,
            scroll: scroll,
            card: leadCard,
            cardSelected: isCardSelected(selection),
            onActivateCard: {
                vm.selection = 0
                activate(at: 0)
            },
            onCardActions: {
                guard hasPrimaryAction(at: 0) else { return }
                vm.selection = 0
                openActions()
            },
            onActivate: {
                core.launcherCoordinator.launch(
                    $0, searchQuery: vm.query, arguments: argumentValues(for: $0))
            },
            onActions: { app in
                if let index = rows.firstIndex(of: .entry(app)) { vm.selection = index }
                openActions()
            },
            onDropped: { core.paletteCoordinator.dragLanded() },
            fallbacks: fallbackSection
        )
    }

    /// 未输入内容时为 nil，这是该区块唯一没有输入来源的状态。
    private var fallbackSection: LauncherList.FallbackSection? {
        guard !fallbacks.isEmpty else { return nil }
        return LauncherList.FallbackSection(
            title: Fallback.sectionTitle(query: vm.query, language: core.settings.language),
            entries: fallbacks.map(\.entry),
            onActivate: { activate(at: fallbackRow(at: $0)) },
            onActions: {
                vm.selection = fallbackRow(at: $0)
                openActions()
            },
            onConfigure: core.fallbackCoordinator.showSettings)
    }

    /// 兜底位于 `rows` 的尾部，因此点击可直接映射到其扁平索引而无需查找。
    private func fallbackRow(at index: Int) -> Int { rows.count - fallbacks.count + index }
}
