// 文件职责：定义可读的设置快照（字段全部可选，导入时按字段合并），并提供从 AppCore 采集与写回的实现。
// 分层：Model + main-actor 扩展；采集/写回部分读写实时存储，必须在主线程执行。
import Foundation

/// 可读的配置快照；每个字段都是可选的，因此导入时按字段合并。
struct SettingsBackup: Codable {

    var settings: SettingsData?
    var hotkeys: HotkeyBackup?
    var customCommands: [CustomCommand]?
    var quicklinks: [Quicklink]?
    var windowLayouts: [WindowLayout]?
    var windowRooms: [Room]?
    var customWindowSizes: [CustomWindowSize]?
    var favoriteApps: [String]?
    var hiddenLauncherItems: [String]?
    var hiddenLauncherKinds: [String]?
    var launcherAliases: [String: String]?
    var pinnedEmoji: [String]?

    /// 可备份的常规设置字段集合。
    /// 枚举按 raw value 存储，遇到未知值会忽略而不是报错。
    struct SettingsData: Codable {
        // 在此新增字段必须同时加到 SettingsBackupCoverage，否则测试会失败。
        // 与需要授权的开关不同，这里会被携带：记录自己产生的副本不涉及任何权限类别。
        var clipboardEnabled: Bool?
        var clipboardRetentionDays: Int?
        var clipboardDefaultAction: String?
        var clipboardDisabledApps: [String]?
        var launchAtLogin: Bool?
        var hyperKey: String?
        var hyperKeyIncludesShift: Bool?
        var hyperKeyQuickPress: String?
        var emojiSkinTone: String?
        var emojiGridColumns: Int?
        var showInMenuBar: Bool?
        var automaticallyCheckForUpdates: Bool?
        var popToRootSeconds: Int?
        var escapeKeyBehavior: String?
        var appearance: String?
        var calcNumberStyle: String?
        var interfaceSize: String?
        var compactMode: Bool?
        var showFavoritesInCompactMode: Bool?
        var searchScopes: [String]?
        var launcherShowsSuggestions: Bool?
        var rootSearchSensitivity: String?
        var openOnCursorScreen: Bool?
        // 可安全携带：它不涉及任何权限类别，只是调整窗口位置。
        var paletteDraggable: Bool?
        var fileSearchEnabled: Bool?
        var fileSearchScopes: [String]?
        var fileSearchIgnorePatterns: [String]?
        var notesEnabled: Bool?
        var notesRendersMarkdown: Bool?
        var notesShowsFormattingBar: Bool?
        // 刻意不含 `snippetsEnabled`：导入不得开启按键监听。
        var customCommandsEnabled: Bool?
        var customCommandsShowInLauncher: Bool?
        var snippetsShowInLauncher: Bool?
        // 可安全携带：它不涉及粘贴本身已经会询问的权限之外的任何权限类别。
        var navigationEnabled: Bool?
        var menuSearchDisabledApps: [String]?
        var menuSearchShowsAppleMenu: Bool?
        var windowManagementEnabled: Bool?
        var windowManagementShowInLauncher: Bool?
        var windowGap: Int?
        var windowCycle: String?
        var windowLayoutsShowInLauncher: Bool?
        var windowRoomsShowInLauncher: Bool?
        // 与 `snippetsEnabled` 不同会被携带：打开链接本身不涉及任何权限类别。
        var quicklinksEnabled: Bool?
        var quicklinksShowInLauncher: Bool?
        var extensionsShowInLauncher: Bool?
        var quicklinkOpensNewWindow: Bool?
        var quicklinkSelectionFallback: String?
        var quicklinkConfirmsBeforeDelete: Bool?
        // 与 quicklinks 一样会被携带：运行用户自己构建的快捷指令不涉及任何权限类别。
        var appleShortcutsEnabled: Bool?
        // 刻意不含 `calendarEnabled`：导入不得授予日历访问权限。
        var calendarShowInLauncher: Bool?
        var calendarLauncherLimit: Int?
        // 会被携带：它只收窄读取范围，不会扩大可触及的范围。
        var calendarSpan: Int?
        var joinWindowMinutes: Int?
        // 刻意不含 `autoJoinMeetings` 与 `cameraPreview`：导入不得启用其中任何一个。
        var autoJoinConfirms: Bool?
        var autoJoinNamedProvidersOnly: Bool?
        var menuBarEvents: Int?
        var calendarMenuBarDisplay: Int?
        var menuBarLinkedEventsOnly: Bool?
        var calendarMenuBarHidesWhenEmpty: Bool?
        var hideCurrentEvent: Int?
        // 可安全携带：它只是静默某条提示，并未授予任何东西。
        var supportReminders: Bool?
    }

    /// 每个可绑定动作对应一个条目。参见 docs/features/hotkeys.md#persistence
    struct HotkeyBackup: Codable {
        /// 单独命名而不并入 `commands`：启动器开关是唯一没有命令行的动作。
        var togglePalette: HotKeyBinding?
        var commands: [String: HotKeyBinding]?
        var apps: [String: HotKeyBinding]?
        var panes: [String: HotKeyBinding]?
        var customCommands: [String: HotKeyBinding]?
        var systemActions: [String: HotKeyBinding]?
        var windowCommands: [String: HotKeyBinding]?
        var quicklinks: [String: HotKeyBinding]?
        var windowLayouts: [String: HotKeyBinding]?
        var windowRooms: [String: HotKeyBinding]?
        var customWindowSizes: [String: HotKeyBinding]?
    }

    /// 统计一次导入所改动的数量，用于向用户确认。
    struct ApplySummary {
        var settingsFields = 0
        var hotkeys = 0
        var favorites = 0
        var hiddenItems = 0
        var aliases = 0
        var pinnedEmoji = 0
        var customCommands = 0
        var quicklinks = 0
        var windowLayouts = 0
        var windowRooms = 0
        var customWindowSizes = 0
    }
}

// MARK: - Gather / apply (main-actor: reads and writes the live stores)

@MainActor
extension SettingsBackup {
    /// 从 AppCore 采集当前配置，生成可序列化的设置快照。
    static func gather(from core: AppCore) -> SettingsBackup {
        let s = core.settings
        var backup = SettingsBackup()
        backup.settings = SettingsData(
            clipboardEnabled: s.clipboardEnabled,
            clipboardRetentionDays: s.clipboardRetention.rawValue,
            clipboardDefaultAction: s.clipboardDefaultAction.rawValue,
            clipboardDisabledApps: s.clipboardDisabledApps,
            launchAtLogin: s.launchAtLogin,
            hyperKey: s.hyperKey.rawValue,
            hyperKeyIncludesShift: s.hyperKeyIncludesShift,
            hyperKeyQuickPress: s.hyperKeyQuickPress.rawValue,
            emojiSkinTone: s.emojiSkinTone.rawValue,
            emojiGridColumns: s.emojiGridColumns.rawValue,
            showInMenuBar: s.showInMenuBar,
            automaticallyCheckForUpdates: s.automaticallyCheckForUpdates,
            popToRootSeconds: s.popToRootTimeout.rawValue,
            escapeKeyBehavior: s.escapeKeyBehavior.rawValue,
            appearance: s.appearance.rawValue,
            calcNumberStyle: s.calcNumberStyle.rawValue,
            interfaceSize: s.interfaceSize.rawValue,
            compactMode: s.compactMode,
            showFavoritesInCompactMode: s.showFavoritesInCompactMode,
            searchScopes: s.searchScopes,
            launcherShowsSuggestions: s.launcherShowsSuggestions,
            rootSearchSensitivity: s.rootSearchSensitivity.rawValue,
            openOnCursorScreen: s.openOnCursorScreen,
            paletteDraggable: s.paletteDraggable,
            fileSearchEnabled: s.fileSearchEnabled,
            fileSearchScopes: s.fileSearchScopes,
            fileSearchIgnorePatterns: s.fileSearchIgnorePatterns,
            notesEnabled: s.notesEnabled,
            notesRendersMarkdown: s.notesRendersMarkdown,
            notesShowsFormattingBar: s.notesShowsFormattingBar,
            customCommandsEnabled: s.customCommandsEnabled,
            customCommandsShowInLauncher: s.customCommandsShowInLauncher,
            snippetsShowInLauncher: s.snippetsShowInLauncher,
            navigationEnabled: s.navigationEnabled,
            menuSearchDisabledApps: s.menuSearchDisabledApps,
            menuSearchShowsAppleMenu: s.menuSearchShowsAppleMenu,
            windowManagementEnabled: s.windowManagementEnabled,
            windowManagementShowInLauncher: s.windowManagementShowInLauncher,
            windowGap: s.windowGap,
            windowCycle: s.windowCycle.rawValue,
            windowLayoutsShowInLauncher: s.windowLayoutsShowInLauncher,
            windowRoomsShowInLauncher: s.windowRoomsShowInLauncher,
            quicklinksEnabled: s.quicklinksEnabled,
            quicklinksShowInLauncher: s.quicklinksShowInLauncher,
            extensionsShowInLauncher: s.extensionsShowInLauncher,
            quicklinkOpensNewWindow: s.quicklinkOpensNewWindow,
            quicklinkSelectionFallback: s.quicklinkSelectionFallback.rawValue,
            quicklinkConfirmsBeforeDelete: s.quicklinkConfirmsBeforeDelete,
            appleShortcutsEnabled: s.appleShortcutsEnabled,
            calendarShowInLauncher: s.calendarShowInLauncher,
            calendarLauncherLimit: s.calendarLauncherLimit.rawValue,
            calendarSpan: s.calendarSpan.rawValue,
            joinWindowMinutes: s.joinWindowMinutes.rawValue,
            autoJoinConfirms: s.autoJoinConfirms,
            autoJoinNamedProvidersOnly: s.autoJoinNamedProvidersOnly,
            menuBarEvents: s.menuBarEvents.rawValue,
            calendarMenuBarDisplay: s.calendarMenuBarDisplay.rawValue,
            menuBarLinkedEventsOnly: s.menuBarLinkedEventsOnly,
            calendarMenuBarHidesWhenEmpty: s.calendarMenuBarHidesWhenEmpty,
            hideCurrentEvent: s.hideCurrentEvent.rawValue,
            supportReminders: s.supportRemindersEnabled)

        let hk = core.hotKeys
        var hotkeys = HotkeyBackup()
        hotkeys.togglePalette = hk.binding(for: .togglePalette)
        hotkeys.commands = Dictionary(
            uniqueKeysWithValues: CommandID.allCases.compactMap { id in
                id.hotKeyAction.flatMap(hk.binding(for:)).map { (id.rawValue, $0) }
            })
        hotkeys.apps = Dictionary(
            uniqueKeysWithValues: hk.boundBundleIDs.compactMap { id in
                hk.binding(for: .app(bundleID: id)).map { (id, $0) }
            })
        hotkeys.panes = Dictionary(
            uniqueKeysWithValues: hk.boundPaneBundleIDs.compactMap { id in
                hk.binding(for: .settingsPane(bundleID: id)).map { (id, $0) }
            })
        hotkeys.customCommands = Dictionary(
            uniqueKeysWithValues: hk.boundCustomCommandIDs.compactMap { id in
                hk.binding(for: .customCommand(id: id)).map { (id.uuidString.lowercased(), $0) }
            })
        hotkeys.systemActions = Dictionary(
            uniqueKeysWithValues: SystemAction.ID.allCases.compactMap { id in
                hk.binding(for: .systemAction(id: id)).map { (id.rawValue, $0) }
            })
        hotkeys.windowCommands = Dictionary(
            uniqueKeysWithValues: WindowCommand.ID.allCases.compactMap { id in
                hk.binding(for: .windowCommand(id: id)).map { (id.rawValue, $0) }
            })
        hotkeys.quicklinks = Dictionary(
            uniqueKeysWithValues: hk.boundQuicklinkIDs.compactMap { id in
                hk.binding(for: .quicklink(id: id)).map { (id.uuidString.lowercased(), $0) }
            })
        hotkeys.windowLayouts = Dictionary(
            uniqueKeysWithValues: hk.boundWindowLayoutIDs.compactMap { id in
                hk.binding(for: .windowLayout(id: id)).map { (id.uuidString.lowercased(), $0) }
            })
        hotkeys.windowRooms = Dictionary(
            uniqueKeysWithValues: hk.boundWindowRoomIDs.compactMap { id in
                hk.binding(for: .windowRoom(id: id)).map { (id.uuidString.lowercased(), $0) }
            })
        hotkeys.customWindowSizes = Dictionary(
            uniqueKeysWithValues: hk.boundCustomWindowSizeIDs.compactMap { id in
                hk.binding(for: .customWindowSize(id: id)).map { (id.uuidString.lowercased(), $0) }
            })
        backup.hotkeys = hotkeys

        backup.customCommands = core.customCommands.commands
        backup.quicklinks = core.quicklinks.quicklinks
        backup.windowLayouts = core.windowLayouts.layouts
        backup.windowRooms = core.rooms.rooms
        backup.customWindowSizes = core.customWindowSizes.sizes
        backup.favoriteApps = core.favorites.keys
        backup.hiddenLauncherItems = Array(core.visibility.hiddenItemKeys)
        backup.hiddenLauncherKinds = Array(core.visibility.disabledKinds)
        backup.launcherAliases = core.aliases.aliases
        backup.pinnedEmoji = core.pinnedEmoji.glyphs
        return backup
    }

    /// 把快照按字段合并写回 AppCore，并返回改动统计。
    @discardableResult
    func apply(to core: AppCore) -> ApplySummary {
        var summary = ApplySummary()
        if let s = settings { summary.settingsFields = applySettings(s, to: core) }
        if let customCommands {
            summary.customCommands = core.customCommandCoordinator.replaceCustomCommands(customCommands)
        }
        // 放在 hotkeys 之前，使还原后的快捷键有对应的 quicklink 可挂载。
        if let quicklinks {
            summary.quicklinks = core.quicklinkCoordinator.replaceQuicklinks(quicklinks)
        }
        // 同样放在 hotkeys 之前：快捷键需要对应的布局才能挂载。
        if let windowLayouts {
            summary.windowLayouts =
                core.windowLayoutCoordinator.replaceWindowLayouts(windowLayouts)
        }
        if let windowRooms {
            summary.windowRooms = core.roomCoordinator.replaceRooms(windowRooms)
        }
        if let customWindowSizes {
            summary.customWindowSizes =
                core.customWindowSizeCoordinator.replaceCustomWindowSizes(customWindowSizes)
        }
        if let hotkeys { summary.hotkeys = applyHotkeys(hotkeys, to: core) }
        if let favoriteApps {
            core.favorites.replace(keys: favoriteApps)
            summary.favorites = favoriteApps.count
        }
        if hiddenLauncherItems != nil || hiddenLauncherKinds != nil {
            let items = hiddenLauncherItems ?? Array(core.visibility.hiddenItemKeys)
            let kinds = hiddenLauncherKinds ?? Array(core.visibility.disabledKinds)
            core.visibility.replace(hiddenItems: items, disabledKinds: kinds)
            summary.hiddenItems = items.count
        }
        if let launcherAliases {
            core.aliases.replace(launcherAliases)
            // 在写入存储之后再计数，因为存储会丢弃文件中可能存在的空项。
            summary.aliases = core.aliases.aliases.count
        }
        if let pinnedEmoji {
            core.pinnedEmoji.replace(pinnedEmoji)
            summary.pinnedEmoji = core.pinnedEmoji.glyphs.count
        }
        return summary
    }

    /// 写回常规设置字段，返回实际生效的字段数。
    private func applySettings(_ s: SettingsData, to core: AppCore) -> Int {
        let settings = core.settings
        var count = 0
        if let flag = s.clipboardEnabled {
            settings.clipboardEnabled = flag
            count += 1
        }
        if let days = s.clipboardRetentionDays, let retention = ClipboardRetention(rawValue: days) {
            settings.clipboardRetention = retention
            count += 1
        }
        if let apps = s.clipboardDisabledApps {
            settings.clipboardDisabledApps = apps
            count += 1
        }
        if let raw = s.clipboardDefaultAction, let action = ClipboardDefaultAction(rawValue: raw) {
            settings.clipboardDefaultAction = action
            count += 1
        }
        if let launch = s.launchAtLogin {
            settings.launchAtLogin = launch
            count += 1
        }
        if let raw = s.hyperKey, let key = HyperKeyPhysicalKey(rawValue: raw) {
            settings.hyperKey = key
            count += 1
        }
        if let flag = s.hyperKeyIncludesShift {
            settings.hyperKeyIncludesShift = flag
            count += 1
        }
        if let raw = s.hyperKeyQuickPress, let quick = HyperKeyQuickPress(rawValue: raw) {
            settings.hyperKeyQuickPress = quick
            count += 1
        }
        if let raw = s.emojiSkinTone, let tone = EmojiSkinTone(rawValue: raw) {
            settings.emojiSkinTone = tone
            count += 1
        }
        if let raw = s.emojiGridColumns, let columns = EmojiGridColumns(rawValue: raw) {
            settings.emojiGridColumns = columns
            count += 1
        }
        if let show = s.showInMenuBar {
            settings.showInMenuBar = show
            count += 1
        }
        if let automaticallyCheck = s.automaticallyCheckForUpdates {
            settings.automaticallyCheckForUpdates = automaticallyCheck
            count += 1
        }
        if let secs = s.popToRootSeconds, let timeout = PopToRootTimeout(rawValue: secs) {
            settings.popToRootTimeout = timeout
            count += 1
        }
        if let raw = s.escapeKeyBehavior, let behavior = EscapeKeyBehavior(rawValue: raw) {
            settings.escapeKeyBehavior = behavior
            count += 1
        }
        if let raw = s.interfaceSize, let size = InterfaceSize(rawValue: raw) {
            settings.interfaceSize = size
            count += 1
        }
        if let raw = s.appearance, let appearance = AppAppearance(rawValue: raw) {
            settings.appearance = appearance
            count += 1
        }
        if let raw = s.calcNumberStyle, let style = CalcNumberStyle(rawValue: raw) {
            settings.calcNumberStyle = style
            count += 1
        }
        if let flag = s.compactMode {
            settings.compactMode = flag
            count += 1
        }
        if let flag = s.showFavoritesInCompactMode {
            settings.showFavoritesInCompactMode = flag
            count += 1
        }
        if let scopes = s.searchScopes {
            settings.searchScopes = SearchScopes.normalize(scopes)
            count += 1
        }
        if let flag = s.launcherShowsSuggestions {
            settings.launcherShowsSuggestions = flag
            count += 1
        }
        if let raw = s.rootSearchSensitivity, let sensitivity = SearchSensitivity(rawValue: raw) {
            settings.rootSearchSensitivity = sensitivity
            count += 1
        }
        if let flag = s.openOnCursorScreen {
            settings.openOnCursorScreen = flag
            count += 1
        }
        if let flag = s.paletteDraggable {
            settings.paletteDraggable = flag
            count += 1
        }
        // 通过 AppSettings 写入即可；其余投影由 AppCore 的 sink 重新同步。
        if let flag = s.fileSearchEnabled {
            settings.fileSearchEnabled = flag
            count += 1
        }
        if let scopes = s.fileSearchScopes {
            settings.fileSearchScopes = scopes
            count += 1
        }
        if let patterns = s.fileSearchIgnorePatterns {
            settings.fileSearchIgnorePatterns = patterns
            count += 1
        }
        if let flag = s.notesEnabled {
            settings.notesEnabled = flag
            count += 1
        }
        if let flag = s.notesRendersMarkdown {
            settings.notesRendersMarkdown = flag
            count += 1
        }
        if let flag = s.notesShowsFormattingBar {
            settings.notesShowsFormattingBar = flag
            count += 1
        }
        if let flag = s.customCommandsEnabled {
            settings.customCommandsEnabled = flag
            count += 1
        }
        if let flag = s.customCommandsShowInLauncher {
            settings.customCommandsShowInLauncher = flag
            count += 1
        }
        if let flag = s.snippetsShowInLauncher {
            settings.snippetsShowInLauncher = flag
            count += 1
        }
        if let flag = s.navigationEnabled {
            settings.navigationEnabled = flag
            count += 1
        }
        if let apps = s.menuSearchDisabledApps {
            settings.menuSearchDisabledApps = apps
            count += 1
        }
        if let flag = s.menuSearchShowsAppleMenu {
            settings.menuSearchShowsAppleMenu = flag
            count += 1
        }
        if let flag = s.windowManagementEnabled {
            settings.windowManagementEnabled = flag
            count += 1
        }
        if let flag = s.windowManagementShowInLauncher {
            settings.windowManagementShowInLauncher = flag
            count += 1
        }
        if let gap = s.windowGap {
            settings.windowGap = gap
            count += 1
        }
        if let raw = s.windowCycle, let cycle = WindowCycle(rawValue: raw) {
            settings.windowCycle = cycle
            count += 1
        }
        if let flag = s.windowLayoutsShowInLauncher {
            settings.windowLayoutsShowInLauncher = flag
            count += 1
        }
        if let flag = s.windowRoomsShowInLauncher {
            settings.windowRoomsShowInLauncher = flag
            count += 1
        }
        if let flag = s.quicklinksEnabled {
            settings.quicklinksEnabled = flag
            count += 1
        }
        if let flag = s.extensionsShowInLauncher {
            settings.extensionsShowInLauncher = flag
            count += 1
        }
        if let flag = s.quicklinksShowInLauncher {
            settings.quicklinksShowInLauncher = flag
            count += 1
        }
        if let flag = s.appleShortcutsEnabled {
            settings.appleShortcutsEnabled = flag
            count += 1
        }
        if let flag = s.quicklinkOpensNewWindow {
            settings.quicklinkOpensNewWindow = flag
            count += 1
        }
        if let raw = s.quicklinkSelectionFallback,
            let fallback = QuicklinkSelectionFallback(rawValue: raw)
        {
            settings.quicklinkSelectionFallback = fallback
            count += 1
        }
        if let flag = s.quicklinkConfirmsBeforeDelete {
            settings.quicklinkConfirmsBeforeDelete = flag
            count += 1
        }
        if let flag = s.calendarShowInLauncher {
            settings.calendarShowInLauncher = flag
            count += 1
        }
        if let raw = s.calendarLauncherLimit, let limit = CalendarLauncherLimit(rawValue: raw) {
            settings.calendarLauncherLimit = limit
            count += 1
        }
        if let raw = s.calendarSpan, let span = MeetingSpan(rawValue: raw) {
            settings.calendarSpan = span
            count += 1
        }
        if let raw = s.joinWindowMinutes, let window = JoinWindow(rawValue: raw) {
            settings.joinWindowMinutes = window
            count += 1
        }
        if let flag = s.autoJoinConfirms {
            settings.autoJoinConfirms = flag
            count += 1
        }
        if let flag = s.autoJoinNamedProvidersOnly {
            settings.autoJoinNamedProvidersOnly = flag
            count += 1
        }
        if let raw = s.menuBarEvents, let lead = MenuBarEvents(rawValue: raw) {
            settings.menuBarEvents = lead
            count += 1
        }
        if let raw = s.calendarMenuBarDisplay,
            let display = CalendarMenuBarDisplay(rawValue: raw)
        {
            settings.calendarMenuBarDisplay = display
            count += 1
        }
        if let flag = s.menuBarLinkedEventsOnly {
            settings.menuBarLinkedEventsOnly = flag
            count += 1
        }
        if let flag = s.calendarMenuBarHidesWhenEmpty {
            settings.calendarMenuBarHidesWhenEmpty = flag
            count += 1
        }
        if let raw = s.hideCurrentEvent, let hide = HideCurrentEvent(rawValue: raw) {
            settings.hideCurrentEvent = hide
            count += 1
        }
        if let flag = s.supportReminders {
            settings.supportRemindersEnabled = flag
            count += 1
        }
        return count
    }

    /// 写回快捷键绑定，返回成功注册的数量。
    private func applyHotkeys(_ hotkeys: HotkeyBackup, to core: AppCore) -> Int {
        let hk = core.hotKeys
        var count = 0
        // 跳过已被占用的快捷键：第二次注册会静默失败。
        func apply(_ binding: HotKeyBinding, _ action: HotKeyAction) {
            guard hk.conflictOwner(of: binding, excluding: action) == nil else { return }
            hk.setBinding(binding, for: action)
            count += 1
        }
        if let b = hotkeys.togglePalette { apply(b, .togglePalette) }
        for (rawID, b) in hotkeys.commands ?? [:] {
            guard let action = CommandID(rawValue: rawID)?.hotKeyAction else { continue }
            apply(b, action)
        }
        for (id, b) in hotkeys.apps ?? [:] { apply(b, .app(bundleID: id)) }
        for (id, b) in hotkeys.panes ?? [:] { apply(b, .settingsPane(bundleID: id)) }
        for (rawID, b) in hotkeys.customCommands ?? [:] {
            guard let id = UUID(uuidString: rawID), core.customCommands.command(id: id) != nil else {
                continue
            }
            apply(b, .customCommand(id: id))
        }
        for (rawID, b) in hotkeys.systemActions ?? [:] {
            guard let id = SystemAction.ID(rawValue: rawID) else { continue }
            apply(b, .systemAction(id: id))
        }
        for (rawID, b) in hotkeys.windowCommands ?? [:] {
            guard let id = WindowCommand.ID(rawValue: rawID) else { continue }
            apply(b, .windowCommand(id: id))
        }
        for (rawID, b) in hotkeys.windowLayouts ?? [:] {
            guard let id = UUID(uuidString: rawID), core.windowLayouts.layout(id: id) != nil
            else { continue }
            apply(b, .windowLayout(id: id))
        }
        for (rawID, b) in hotkeys.windowRooms ?? [:] {
            guard let id = UUID(uuidString: rawID), core.rooms.room(id: id) != nil else { continue }
            apply(b, .windowRoom(id: id))
        }
        for (rawID, b) in hotkeys.customWindowSizes ?? [:] {
            guard let id = UUID(uuidString: rawID), core.customWindowSizes.size(id: id) != nil
            else { continue }
            apply(b, .customWindowSize(id: id))
        }
        for (rawID, b) in hotkeys.quicklinks ?? [:] {
            guard let id = UUID(uuidString: rawID), core.quicklinks.quicklink(id: id) != nil else {
                continue
            }
            apply(b, .quicklink(id: id))
        }
        return count
    }
}

// MARK: - Serialization

extension SettingsBackup {
    /// 编码为 JSON 数据（美化输出、按键排序）。
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// 从 JSON 数据解码出设置快照。
    init(json: Data) throws {
        self = try JSONDecoder().decode(SettingsBackup.self, from: json)
    }
}
