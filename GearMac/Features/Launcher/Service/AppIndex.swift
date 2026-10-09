// 文件职责：定义启动器条目模型 AppEntry 与全局索引 AppIndex，负责扫描应用/设置面板、命名、排名并产出启动器行结果。
// 分层：Model + Service（扫描与排名不依赖 UI）；非主线程扫描、主线程发布，条目以 Sendable 跨隔离域传递。
import AppKit

/// 启动器中的一条可搜索条目：应用、系统设置面板、命令、快捷动作、片段等统一表示。
struct AppEntry: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case application
        case systemSettings
        case command
        case quickAction
        case customCommand
        case snippet
        case systemAction
        case windowCommand
        case windowLayout
        case windowRoom
        case quicklink
        case appleShortcut
        case extensionCommand
        case meeting

        var descriptor: KindDescriptor {
            switch self {
            case .application:
                return KindDescriptor(
                    label: "Application", sectionTitle: "Applications",
                    openVerb: "Open Application", canHideFromSearch: true,
                    canRevealInFinder: true, canDragOut: true, isSymbolIcon: false, rankPriority: 4)
            case .systemSettings:
                return KindDescriptor(
                    label: "System Setting", sectionTitle: "System Settings",
                    openVerb: "Open System Setting", canHideFromSearch: true,
                    canRevealInFinder: true, canDragOut: false, isSymbolIcon: false, rankPriority: 1)
            case .command:
                return KindDescriptor(
                    label: "Command", sectionTitle: "Commands",
                    openVerb: "Run Command", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .quickAction:
                return KindDescriptor(
                    label: "Quick Action", sectionTitle: "Quick Actions",
                    openVerb: "Run Quick Action", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .customCommand:
                return KindDescriptor(
                    label: "Custom Command", sectionTitle: "Custom Commands",
                    openVerb: "Run Custom Command", canHideFromSearch: false,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .snippet:
                return KindDescriptor(
                    label: "Snippet", sectionTitle: "Snippets",
                    openVerb: "Paste Snippet", canHideFromSearch: false,
                    canRevealInFinder: true, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .systemAction:
                return KindDescriptor(
                    label: "System Action", sectionTitle: "System Actions",
                    openVerb: "Run System Action", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .windowCommand:
                return KindDescriptor(
                    label: "Window Command", sectionTitle: "Window Management",
                    openVerb: "Move Window", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .windowLayout:
                return KindDescriptor(
                    label: "Window Layout", sectionTitle: "Window Layouts",
                    openVerb: "Arrange Windows", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .windowRoom:
                return KindDescriptor(
                    label: "Room", sectionTitle: "Rooms", openVerb: "Enter Room",
                    canHideFromSearch: true, canRevealInFinder: false, canDragOut: false,
                    isSymbolIcon: true, rankPriority: 3)
            case .quicklink:
                return KindDescriptor(
                    label: "Quicklink", sectionTitle: "Quicklinks",
                    openVerb: "Open Quicklink", canHideFromSearch: false,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 2)
            case .appleShortcut:
                // 由文件支撑，因此每一行都绘制「快捷指令」应用自己的图标。
                return KindDescriptor(
                    label: "Apple Shortcut", sectionTitle: "Apple Shortcuts",
                    openVerb: "Run Shortcut", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: false, rankPriority: 3)
            case .extensionCommand:
                // 标签是逐条目的，即所属扩展的标题；此处只是兜底值。
                return KindDescriptor(
                    label: "Extension", sectionTitle: "Extensions",
                    openVerb: "Run Command", canHideFromSearch: true,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 3)
            case .meeting:
                return KindDescriptor(
                    label: "Meeting", sectionTitle: "Meetings",
                    openVerb: "Join Meeting", canHideFromSearch: false,
                    canRevealInFinder: false, canDragOut: false, isSymbolIcon: true, rankPriority: 1)
            }
        }
    }

    /// 每种 kind 的固定描述；新增 `Kind` case 时若未给出全部字段将无法编译。
    struct KindDescriptor: Sendable {
        let label: String
        let sectionTitle: String
        let openVerb: String
        /// 仅当设置界面提供逐项复选框可将其恢复时才为 true：隐藏永远不是单向不可逆的。
        let canHideFromSearch: Bool
        let canRevealInFinder: Bool
        /// 仅应用为 true：把设置面板或快捷指令拖到别的应用上不会打开任何东西。
        let canDragOut: Bool
        let isSymbolIcon: Bool
        /// 用于打破完全同分的排序，应用优先：如 Calculator 排在 Calculator History 之前。
        let rankPriority: Int
    }

    let id: String  // 文件路径（或 "command:…" 形式的 id）——始终唯一
    let name: String  // 干净的展示名，从不包含 ".app"
    let url: URL
    let bundleID: String?
    let kind: Kind
    /// 当某功能面板（而非该条目所属类别的面板）列出并控制它时设置。
    var settingsOwner: SettingsTab?
    /// 名称旁的次级标签，用于名称本身无法说明作用对象的条目。
    var subtitle: String?
    /// 定时执行的扩展命令的后台刷新状态点；其余情况均为 nil。
    var backgroundRefresh: ExtensionRefreshState?
    /// 与名称一样参与排名：翻译名、重命名、`CFBundleAlternateNames`。
    var alternateTitles: [String] = []
    /// 条目级符号名，仅用于图标由用户选择的种类；其余情况为 nil。
    var symbolName: String?
    /// 只用于命中搜索、不参与排名：如声明的名称、扩展的关键词。
    var keywords: [String] = []
    /// 当磁盘上 bundle 图标变化时随之变化，使缓存的位图作废。仅用于应用。
    var iconStamp: Int = 0
    /// 当图标无法由 `kind` 推导时，由产出该条目的功能设置。
    var iconOverride: EntryIcon?
    /// 条目的来源——如扩展的标题。用作行标签，并按 subtitle 参与排名。
    var ownerName: String?
    /// 落盘时间，使新安装的应用在首次打开前也能被推荐。
    var installedAt: Date?
    /// 上述所有字段的可搜索形式，由 `buildSearchProfile` 在发布时构建。
    var search = SearchProfile.unnamed

    /// 用于学习排名、收藏及其他条目级偏好的稳定标识。
    var preferenceKey: String { bundleID ?? id }

    /// 该条目的名称信息，采用 `EntryNaming` 可读取的结构。
    var naming: EntryNaming.Sources {
        var sources = EntryNaming.Sources(name: name)
        sources.alternateTitles = alternateTitles
        // 行上展示的 subtitle 优先；被它替换掉的 owner 依然能命中该条目。
        sources.subtitle = subtitle ?? ownerName
        sources.keywords = keywords + (subtitle == nil ? [] : [ownerName].compactMap { $0 })
        return sources
    }

    /// 每次索引变化时构建一次，绝不随每次按键构建；仅 `AppIndex.named` 调用它。
    mutating func buildSearchProfile() { search = EntryNaming.profile(for: naming) }

    /// 只有条目尚未拥有的名称才真正起作用；bundle 通常对同一个名字给出重复项。
    mutating func addAlternateTitle(_ candidate: String) {
        let existing = [name] + alternateTitles
        guard !candidate.isEmpty,
            !existing.contains(where: {
                FuzzyMatch.normalized($0) == FuzzyMatch.normalized(candidate)
            })
        else { return }
        alternateTitles.append(candidate)
    }

    /// 该条目对应的热键动作，条目没有可寻址动作时为 nil。
    var hotKeyAction: HotKeyAction? {
        switch kind {
        case .command:
            return CommandCatalog.command(for: self)?.hotKeyAction
        case .quickAction:
            if let command = CommandCatalog.command(for: self) { return command.hotKeyAction }
            return CustomQuickAction.id(fromEntryID: id).map { .quickAction(id: $0) }
        case .application:
            return bundleID.map { .app(bundleID: $0) }
        case .systemSettings:
            return bundleID.map { .settingsPane(bundleID: $0) }
        case .customCommand:
            return CustomCommand.id(fromEntryID: id).map { .customCommand(id: $0) }
        case .systemAction:
            return SystemActionCatalog.action(forEntryID: id).map { .systemAction(id: $0.id) }
        case .windowCommand:
            if let command = WindowCommandCatalog.command(forEntryID: id) {
                return .windowCommand(id: command.id)
            }
            return CustomWindowSize.id(fromEntryID: id).map { .customWindowSize(id: $0) }
        case .windowLayout:
            return WindowLayout.id(fromEntryID: id).map { .windowLayout(id: $0) }
        case .windowRoom:
            return Room.id(fromEntryID: id).map { .windowRoom(id: $0) }
        case .quicklink:
            return Quicklink.id(fromEntryID: id).map { .quicklink(id: $0) }
        case .appleShortcut:
            return AppleShortcut.id(fromEntryID: id).map { .appleShortcut(id: $0) }
        case .snippet:
            return StoredSnippet.id(fromEntryID: id).map { .snippet(id: $0) }
        case .extensionCommand, .meeting:
            return nil
        }
    }

    /// 合成条目没有可显示的文件；目标本身就是其记录自身的动作。
    var canRevealInFinder: Bool { kind.descriptor.canRevealInFinder }

    var canHideFromSearch: Bool { kind.descriptor.canHideFromSearch }

    var canDragOut: Bool { kind.descriptor.canDragOut }

    /// 该行绘制的图标来源，也是所有图标路径唯一需要查询的东西。
    var iconSource: EntryIcon { iconOverride ?? defaultIcon }

    /// 仅由 kind 推导：合成条目使用符号图标，其余使用其文件图标。
    private var defaultIcon: EntryIcon {
        guard kind.descriptor.isSymbolIcon else { return .file(stamp: iconStamp) }
        return .symbol(symbolName ?? kindSymbol)
    }

    private var kindSymbol: String {
        switch kind {
        case .quicklink: return Quicklink.sfSymbol
        case .snippet: return "text.quote"
        case .customCommand: return CustomCommand.sfSymbol
        case .command: return CommandCatalog.command(for: self)?.sfSymbol ?? "questionmark"
        case .quickAction:
            return CommandCatalog.command(for: self)?.sfSymbol ?? CustomQuickAction.sfSymbol
        case .systemAction: return SystemActionCatalog.action(forEntryID: id)?.sfSymbol ?? "questionmark"
        case .windowCommand:
            return WindowCommandCatalog.command(forEntryID: id)?.sfSymbol
                ?? CustomWindowSize.sfSymbol
        case .windowLayout: return WindowLayout.sfSymbol
        case .windowRoom: return Room.sfSymbol
        case .meeting: return "video.fill"
        case .application, .systemSettings, .appleShortcut, .extensionCommand: return "questionmark"
        }
    }

    /// 限定在主 actor，因为它会为调用视图注册观察；所有调用方都是 `body`。
    @MainActor var icon: NSImage {
        IconCache.observeStyle()
        return IconCache.icon(for: iconSource, fileURL: url)
    }

    /// 行异步加载图标时的身份标识：换肤会改变字形而 `id` 保持不变。
    var iconKey: String { "\(id)|\(iconSource)" }
}

extension AppEntry {
    /// 布局在任何入口展示时对应的唯一一行。
    init(_ layout: WindowLayout) {
        self.init(
            id: layout.entryID, name: layout.name,
            url: URL(string: "gearmac://window-layout/" + layout.id.uuidString)!,
            bundleID: nil, kind: .windowLayout, symbolName: layout.iconSymbol)
    }

    /// Room 在任何入口展示时对应的唯一一行。
    init(_ room: Room) {
        self.init(
            id: room.entryID, name: room.name,
            url: URL(string: "gearmac://window-room/" + room.id.uuidString)!,
            bundleID: nil, kind: .windowRoom)
    }

    /// 自定义尺寸与窗口命令共用 kind 和分组，与自定义 Quick Action 的做法一致。
    init(_ size: CustomWindowSize) {
        self.init(
            id: size.entryID, name: size.name,
            url: URL(string: "gearmac://window-size/" + size.id.uuidString)!,
            bundleID: nil, kind: .windowCommand)
    }

    /// 自定义 Quick Action 在任何入口展示时对应的唯一一行。
    init(_ action: CustomQuickAction) {
        self.init(
            id: action.entryID, name: action.name,
            url: URL(string: "gearmac://quick-action/" + action.id.uuidString)!,
            bundleID: nil, kind: .quickAction, symbolName: action.iconSymbol)
    }

    /// 自定义命令在任何入口展示时对应的唯一一行。
    init(_ command: CustomCommand) {
        self.init(
            id: command.entryID, name: command.name,
            url: URL(string: "gearmac://custom-command/" + command.id.uuidString)!,
            bundleID: nil, kind: .customCommand, symbolName: command.iconSymbol)
    }

    /// Quicklink 在任何入口展示时对应的唯一一行。
    init(_ quicklink: Quicklink) {
        self.init(
            id: quicklink.entryID, name: quicklink.name,
            url: URL(string: "gearmac://quicklink/" + quicklink.id.uuidString)!,
            bundleID: nil, kind: .quicklink,
            symbolName: quicklink.iconSymbol
                ?? QuicklinkDestination.detect(quicklink.link)?.defaultSymbol)
    }

    /// 不设 bundle id：否则每条快捷指令的别名与排名都会被绑定到「快捷指令」应用上。
    init(_ shortcut: AppleShortcut, applicationURL: URL) {
        self.init(
            id: shortcut.entryID, name: shortcut.name, url: applicationURL, bundleID: nil,
            kind: .appleShortcut)
    }
}

extension AppEntry.Kind {
    /// 各 descriptor 自身的词，预先统一小写，使每次按键只需查表而不必遍历扫描。
    private static let byCategoryName: [String: AppEntry.Kind] = allCases.reduce(into: [:]) {
        $0[$1.descriptor.sectionTitle.lowercased()] = $1
        $0[$1.descriptor.label.lowercased()] = $1
    }

    /// 查询直接命名的类别。仅精确匹配——前缀匹配会从条目名中抢走单词。
    static func named(by query: String) -> AppEntry.Kind? {
        byCategoryName[query.trimmingCharacters(in: .whitespaces).lowercased()]
    }
}

@MainActor
@Observable
final class AppIndex {
    /// 当前发布给 UI 的全部条目，按分组顺序排列。
    private(set) var apps: [AppEntry] = []

    private var snippetEntries: [AppEntry] = []

    /// 启动器一次查询的结果：按顺序排列的条目及各固定分组的条目数。
    struct Results: Equatable {
        var entries: [AppEntry] = []
        var favoriteCount = 0
        var meetingCount = 0
        var suggestionCount = 0
    }

    /// 匹配缓存的键，覆盖查询、条目/排名/别名 revision 与搜索灵敏度。
    private struct MatchKey: Equatable {
        let query: String
        let entriesRevision: Int
        let rankingRevision: Int
        let aliasRevision: Int
        let sensitivity: SearchSensitivity
    }

    /// 结果缓存的键，在匹配键之外再加上可见性、收藏、热键与推荐开关等状态。
    private struct ResultsKey: Equatable {
        let match: MatchKey
        let visibilityRevision: Int
        let favoritesRevision: Int
        let hotKeysRevision: Int
        let showsSuggestions: Bool
        /// 推荐与使用频率排序会随时间老化，没有任何 revision 能追踪这一点。
        let minute: Int
    }

    /// 同一查询的重复渲染复用已有排名，而不是每帧重新匹配。
    @ObservationIgnored private var matchMemo = Memo<MatchKey, [AppEntry]>()
    @ObservationIgnored private var resultsMemo = Memo<ResultsKey, Results>()
    /// `apps` 每次变化时递增，使上面两个 memo 都记录其构建所依据的条目集合。
    private var entriesRevision = 0

    /// 系统动作目录对应的条目，按名称排序的静态列表。
    private static let systemActionEntries: [AppEntry] = SystemActionCatalog.all
        .map { command in
            AppEntry(
                id: command.entryID, name: command.name,
                url: URL(string: "gearmac://system-action/" + command.id.rawValue)!,
                bundleID: nil, kind: .systemAction)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    /// 窗口命令目录对应的条目，按名称排序的静态列表。
    private static let allWindowCommandEntries: [AppEntry] = WindowCommandCatalog.all
        .map { command in
            AppEntry(
                id: command.entryID, name: command.name,
                url: URL(string: "gearmac://window-command/" + command.id.rawValue)!,
                bundleID: nil, kind: .windowCommand)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    /// 已发现的应用与设置面板条目（由磁盘扫描产生）。
    private var discoveredEntries: [AppEntry] = []
    private var customCommandEntries: [AppEntry] = []
    private var windowCommandEntries: [AppEntry] = []
    private var customWindowSizeEntries: [AppEntry] = []
    private var windowLayoutEntries: [AppEntry] = []
    private var windowRoomEntries: [AppEntry] = []
    private var quicklinkEntries: [AppEntry] = []
    private var appleShortcutEntries: [AppEntry] = []
    private var customQuickActionEntries: [AppEntry] = []
    private var extensionEntries: [AppEntry] = []
    private var meetingEntries: [AppEntry] = []
    /// 被关闭的功能所隐藏的目录命令；Commands 分组会依据它重新计算。
    private var hiddenCommands: Set<CommandID> = []
    /// 因「在启动器中显示」开关而排除在启动器搜索外，但仍可通过快捷键运行。
    private var unlistedCommands: Set<CommandID> = []
    private var nameCache = BundleNameCache()
    private var paneCache: SettingsPaneScanner.Cache?
    private var isRefreshing = false
    /// 在扫描过程中又收到刷新请求时置位，确保搜索范围编辑不会被静默丢弃。
    private var refreshPending = false
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    private var settings: AppSettings?
    /// 每次扫描后都触发，即使结果未变：LaunchServices 可能滞后删除好几秒。
    @ObservationIgnored var onScan: (() -> Void)?

    /// 注入排名与别名存储；扫描到的条目会依据二者计算排序。
    init(ranking: LauncherRankingStore, aliases: AliasStore) {
        self.ranking = ranking
        self.aliases = aliases
    }

    /// 始终相关的内置命令，加上未被已关闭功能隐藏的部分。
    private var commandEntries: [AppEntry] {
        visibleCatalogEntries.filter { $0.kind == .command }
    }

    /// 可见的快捷动作命令与自定义快捷动作合并后的条目。
    private var quickActionEntries: [AppEntry] {
        visibleCatalogEntries.filter { $0.kind == .quickAction } + customQuickActionEntries
    }

    /// 目录中未被关闭功能隐藏、也未被排除出搜索的命令条目。
    private var visibleCatalogEntries: [AppEntry] {
        CommandCatalog.all.filter {
            guard let command = CommandCatalog.command(for: $0) else { return true }
            return !hiddenCommands.contains(command) && !unlistedCommands.contains(command)
        }
    }

    /// 命令所属功能是否开启，其快捷键同样必须遵守该状态。
    func isCommandEnabled(_ command: CommandID) -> Bool {
        !hiddenCommands.contains(command)
    }

    /// 功能关闭时其命令会离开 Commands 分组；`visible` 为 true 时恢复。
    func setCommandsVisible(_ commands: Set<CommandID>, _ visible: Bool) {
        let updated = visible ? hiddenCommands.subtracting(commands) : hiddenCommands.union(commands)
        guard updated != hiddenCommands else { return }
        hiddenCommands = updated
        publishEntries()
    }

    /// 控制命令是否进入启动器搜索列表（对应「在启动器中显示」开关）。
    func setCommandsListed(_ commands: Set<CommandID>, _ listed: Bool) {
        let updated =
            listed ? unlistedCommands.subtracting(commands) : unlistedCommands.union(commands)
        guard updated != unlistedCommands else { return }
        unlistedCommands = updated
        publishEntries()
    }

    /// 不重新扫描即替换命令切片，使设置中的修改立即生效。
    func setCustomCommands(_ commands: [CustomCommand]) {
        let entries = commands.filter(\.isEnabled).map(AppEntry.init)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard entries != customCommandEntries else { return }
        customCommandEntries = entries
        publishEntries()
    }

    /// 替换自定义快捷动作切片，它与内置的四个共用同一分组。
    func setCustomQuickActions(_ actions: [CustomQuickAction]) {
        let entries = actions.sorted(by: CustomQuickAction.precedes).map(AppEntry.init)
        guard entries != customQuickActionEntries else { return }
        customQuickActionEntries = entries
        publishEntries()
    }

    /// 替换 quicklink 切片；开关无法把其条目从所属分组中拆出。
    func setQuicklinks(_ quicklinks: [Quicklink]) {
        let entries =
            quicklinks
            .filter { $0.isEnabled && $0.showsInRootSearch }
            .sorted(by: Quicklink.precedes)
            .map(AppEntry.init)
        guard entries != quicklinkEntries else { return }
        quicklinkEntries = entries
        publishEntries()
    }

    /// 从「快捷指令」应用中发现，因此传入时已构建并排序完毕。
    func setAppleShortcuts(_ entries: [AppEntry]) {
        guard entries != appleShortcutEntries else { return }
        appleShortcutEntries = entries
        publishEntries()
    }

    /// 事件自身会变化，因此由数据存储的变更回调驱动，而非用户编辑。
    func setMeetings(_ entries: [AppEntry]) {
        guard entries != meetingEntries else { return }
        meetingEntries = entries
        publishEntries()
    }

    /// 已安装集合或所选外观变化时由 `ExtensionManager` 调用。
    func setExtensionCommands(_ entries: [AppEntry]) {
        guard entries != extensionEntries else { return }
        extensionEntries = entries
        publishEntries()
    }

    /// 显示或隐藏窗口命令切片；目录本身是静态的。
    func setWindowCommandsVisible(_ visible: Bool) {
        let entries = visible ? Self.allWindowCommandEntries : []
        guard entries != windowCommandEntries else { return }
        windowCommandEntries = entries
        publishEntries()
    }

    /// 替换自定义尺寸切片，它与窗口命令共用同一分组。
    func setCustomWindowSizes(_ sizes: [CustomWindowSize]) {
        let entries = sizes.sorted(by: CustomWindowSize.precedes).map(AppEntry.init)
        guard entries != customWindowSizeEntries else { return }
        customWindowSizeEntries = entries
        publishEntries()
    }

    /// 替换布局切片；开关无法把其条目从所属分组中拆出。
    func setWindowLayouts(_ layouts: [WindowLayout]) {
        let entries = layouts.sorted(by: WindowLayout.precedes).map(AppEntry.init)
        guard entries != windowLayoutEntries else { return }
        windowLayoutEntries = entries
        publishEntries()
    }

    /// 替换 Room 切片，它发布在布局与窗口命令之间。
    func setWindowRooms(_ rooms: [Room]) {
        let entries = rooms.sorted(by: Room.precedes).map(AppEntry.init)
        guard entries != windowRoomEntries else { return }
        windowRoomEntries = entries
        publishEntries()
    }

    /// 由已启用的片段记录重建片段切片，关键词作为备用标题参与搜索。
    func updateSnippets(_ records: [StoredSnippet]) {
        let entries =
            records
            .filter { $0.snippet.isEnabled }
            .map { record in
                AppEntry(
                    id: record.entryID,
                    name: record.snippet.name,
                    url: record.fileURL,
                    bundleID: nil,
                    kind: .snippet,
                    alternateTitles: [record.snippet.keyword].compactMap { $0 })
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard entries != snippetEntries else { return }
        snippetEntries = entries
        publishEntries()
    }

    /// 接入搜索范围观察，编辑后立即重新索引，而不是等到下次打开。
    func start(settings: AppSettings) {
        self.settings = settings
        observeSearchScopes()
    }

    /// 在主 actor 写入落盘前同步触发，因此重新注册观察后再执行重扫。
    private func observeSearchScopes() {
        withObservationTracking {
            _ = settings?.searchScopes
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeSearchScopes()
                await self.refresh()
            }
        }
    }

    /// 每次打开都重扫；重复请求会合并，结果不变时不做任何 UI 工作。
    func refresh() async {
        guard !isRefreshing else {
            refreshPending = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            refreshPending = false
            let scopes = settings?.searchScopes ?? SearchScopes.defaults
            let reusingPanes = paneCache
            let languages = BundleLocalization.indexedLanguages(Locale.preferredLanguages)
            let reusing = BundleNameCache(reusing: nameCache, languages: languages)
            let (found, cache, panes) = await Task.detached(priority: .utility) {
                AppIndex.scan(
                    scopes: scopes, languages: languages, cache: reusing, paneCache: reusingPanes)
            }.value
            nameCache = cache
            paneCache = panes
            guard found != discoveredEntries else { continue }
            discoveredEntries = found
            publishEntries()
        } while refreshPending
        onScan?()
    }

    /// 既不在索引中、LaunchServices 也不认识，因此移出搜索范围不等于删除。
    func isUninstalled(bundleID: String) -> Bool {
        !discoveredEntries.contains { $0.kind == .application && $0.bundleID == bundleID }
            && NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) == nil
    }

    /// 在后台线程扫描搜索范围内的应用 bundle 与设置面板，返回条目、名称缓存与面板缓存。
    nonisolated private static func scan(
        scopes: [String], languages: [String], cache: BundleNameCache,
        paneCache: SettingsPaneScanner.Cache?
    ) -> ([AppEntry], BundleNameCache, SettingsPaneScanner.Cache?) {
        Signposts.interval("AppIndex.scan") {
            var cache = cache
            var indexByBundleID: [String: Int] = [:]
            var result: [AppEntry] = []
            for url in SearchScopes.appBundles(in: scopes) {
                let bundle = Bundle(url: url)
                let bundleID = bundle?.bundleIdentifier
                let fileName = EntryNaming.strippingAppExtension(url.lastPathComponent)
                // 按 bundle id 去重；先出现的范围优先，但重命名的副本会贡献其名称。
                if let bundleID, let first = indexByBundleID[bundleID] {
                    result[first].addAlternateTitle(fileName)
                    continue
                }

                // Finder 的规则：当文件名与展示名冲突时，LaunchServices 忽略该展示名。
                let names = cache.names(
                    for: url, base: fileName, developmentRegion: bundle?.developmentLocalization)
                // 原样读取：日历的 strings 文件会用名称替换其 `iCal` 数组。
                let alternates = bundle?.infoDictionary?["CFBundleAlternateNames"] as? [String] ?? []
                // 仍可被搜索到，但不会作为标签：输入 `code` 必须仍能找到 Visual Studio Code。
                let declared = [bundle?.installedAppName].compactMap { $0 }
                var entry = AppEntry(
                    id: url.path, name: names.first ?? fileName, url: url, bundleID: bundleID,
                    kind: .application, alternateTitles: Array(names.dropFirst()) + alternates,
                    keywords: declared, iconStamp: FileIconStamp.value(for: url),
                    installedAt: try? url.resourceValues(forKeys: [.addedToDirectoryDateKey])
                        .addedToDirectoryDate)
                entry.addAlternateTitle(fileName)
                if let bundleID { indexByBundleID[bundleID] = result.count }
                result.append(entry)
            }
            // 切片顺序即分组顺序，因此扁平的选择索引与行一一对应。
            let apps = result.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            // 设置面板是 `.appex` bundle，不携带 Spotlight 备用名称。
            let (panes, panesCache) = SettingsPaneScanner.scan(languages: languages, cache: paneCache)
            // 在此处而非发布时命名：对中日韩索引做罗马化会占用约 50 ms 的主 actor 时间。
            return (AppIndex.named(apps + panes), cache, panesCache)
        }
    }

    /// 条目所携带全部名称的可搜索形式。应用切片由 `scan` 自行命名。
    nonisolated private static func named(_ entries: [AppEntry]) -> [AppEntry] {
        entries.map { entry in
            var entry = entry
            entry.buildSearchProfile()
            return entry
        }
    }

    /// 由各切片拼接出发布顺序，若有变化则更新 `apps` 并递增 `entriesRevision`。
    private func publishEntries() {
        // 每个切片按各自的展示顺序传入；切片顺序即分组顺序。
        let updated =
            Self.named(meetingEntries) + discoveredEntries
            + Self.named(
                extensionEntries + quicklinkEntries + appleShortcutEntries + snippetEntries
                    + Self.systemActionEntries + windowLayoutEntries + windowRoomEntries
                    + windowCommandEntries
                    + customWindowSizeEntries + customCommandEntries + quickActionEntries
                    + commandEntries)
        guard updated != apps else { return }
        apps = updated
        entriesRevision &+= 1
    }

    /// 返回排序后的匹配项；当查询直接命名某个类别时返回整个类别；查询为空时返回全部。
    func matches(_ query: String, limit: Int = 200) -> [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return apps }
        return matchMemo.value(for: matchKey(q)) {
            guard let kind = AppEntry.Kind.named(by: q) else { return rank(q, limit: limit) }
            return categoryListing(kind, query: q)
        }
    }

    /// 切片顺序即分组顺序，因此过滤后分组与选中项仍保持对齐。
    private func categoryListing(_ kind: AppEntry.Kind, query: String) -> [AppEntry] {
        let listed = apps.filter {
            $0.kind == kind || FuzzyMatch.normalized($0.name) == FuzzyMatch.normalized(query)
        }
        return byUsage(listed, usage: ranking.snapshot())
    }

    /// 启动器最终的行：排序后的匹配项，或查询为空时的收藏、推荐及按使用频率排序的各类条目。
    func orderedResults(
        query: String, visibility: VisibilityStore, favorites: FavoritesStore, hotKeys: HotKeyManager
    ) -> Results {
        let q = query.trimmingCharacters(in: .whitespaces)
        let showsSuggestions = settings?.launcherShowsSuggestions ?? true
        let usage = ranking.snapshot()
        let key = ResultsKey(
            match: matchKey(q), visibilityRevision: visibility.revision,
            favoritesRevision: favorites.revision, hotKeysRevision: hotKeys.revision,
            showsSuggestions: showsSuggestions, minute: Int(usage.now.timeIntervalSince1970 / 60))
        return resultsMemo.value(for: key) {
            // 过滤保持在 `matches` 之后，使该 memo 的键永不依赖隐藏状态。
            let visible = matches(q).filter(visibility.isVisible)
            guard q.isEmpty else { return Results(entries: visible) }
            let split = favorites.ordered(visible)
            let suggested =
                showsSuggestions ? suggestions(from: split.rest, usage: usage, hotKeys: hotKeys) : []
            let shown = Set(suggested.map(\.id))
            let rest = byUsage(split.rest.filter { !shown.contains($0.id) }, usage: usage)
            // 排在推荐之上：会议只在其结束前值得打开。
            let meetings = rest.filter { $0.kind == .meeting }
            return Results(
                entries: split.favorites + meetings + suggested + rest.filter { $0.kind != .meeting },
                favoriteCount: split.favorites.count, meetingCount: meetings.count,
                suggestionCount: suggested.count)
        }
    }

    /// 当前设置下的根搜索灵敏度。
    private var sensitivity: SearchSensitivity { settings?.rootSearchSensitivity ?? .default }

    /// 构造匹配缓存的键，涵盖查询、各 revision 与搜索灵敏度。
    private func matchKey(_ query: String) -> MatchKey {
        MatchKey(
            query: query, entriesRevision: entriesRevision, rankingRevision: ranking.revision,
            aliasRevision: aliases.revision, sensitivity: sensitivity)
    }

    /// 调用 LauncherOrder 对全部条目做模糊匹配与排名。
    private func rank(_ q: String, limit: Int) -> [AppEntry] {
        Signposts.interval("AppIndex.rank") {
            let usage = ranking.snapshot()
            return LauncherOrder.ranked(
                apps, query: LauncherOrder.Query(q), sensitivity: sensitivity, limit: limit,
                profile: \.search, signals: { self.signals(for: $0, usage: usage) })
        }
    }

    /// 按使用频率对条目排序，同时细分出 kind 分组以保持分组连续（会议保持原有顺序）。
    private func byUsage(_ entries: [AppEntry], usage: LauncherRankingStore.Snapshot) -> [AppEntry] {
        var ordered: [AppEntry] = []
        ordered.reserveCapacity(entries.count)
        var start = entries.startIndex
        while start < entries.endIndex {
            let kind = entries[start].kind
            let end = entries[start...].firstIndex { $0.kind != kind } ?? entries.endIndex
            if kind == .meeting {
                ordered.append(contentsOf: entries[start..<end])
            } else {
                ordered += LauncherOrder.byUsage(
                    Array(entries[start..<end]), signals: { self.signals(for: $0, usage: usage) })
            }
            start = end
        }
        return ordered
    }

    /// 会议保留独立卡片，不推荐 AI 相关项，且 GearMac 打开自身没有任何意义。
    private func suggestions(
        from entries: [AppEntry], usage: LauncherRankingStore.Snapshot, hotKeys: HotKeyManager
    ) -> [AppEntry] {
        let eligible = entries.filter {
            $0.kind != .meeting && $0.settingsOwner != .ai
                && !($0.bundleID?.hasPrefix(Self.ownBundlePrefix) ?? false)
        }
        return LauncherSuggestions.select(from: eligible, now: usage.now) { entry in
            // 扩展命令的 `hotKeyAction` 为 nil，其快捷键以条目 ID 为键。
            let action: HotKeyAction? =
                entry.kind == .extensionCommand ? .extensionCommand(entryID: entry.id) : entry.hotKeyAction
            return LauncherSuggestions.Traits(
                signals: signals(for: entry, usage: usage), installedAt: entry.installedAt,
                hasHotKey: action.flatMap(hotKeys.binding(for:)) != nil,
                priority: CommandCatalog.command(for: entry)?.suggestionPriority)
        }
    }

    /// GearMac 自身 bundle id 前缀，用于排除自我推荐。
    private static let ownBundlePrefix = "com.gearmac."

    /// 汇总单个条目的排名信号：别名、使用频率、类别优先级、标题与加权词。
    private func signals(
        for entry: AppEntry, usage: LauncherRankingStore.Snapshot
    ) -> LauncherOrder.Signals {
        LauncherOrder.Signals(
            alias: aliases.alias(for: entry.preferenceKey).map { SearchText($0, transliterated: false) },
            usage: usage.usage(for: entry.preferenceKey),
            priority: entry.kind.descriptor.rankPriority, title: entry.name,
            boostedTerms: CommandCatalog.command(for: entry)?.boostedTerms ?? [])
    }
}
