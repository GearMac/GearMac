// 文件职责：定义 AppSettings（全部用户偏好的内存模型）、其配套的展示枚举，以及每个属性写回 UserDefaults 的同步逻辑。
// 分层：Settings（Model）；用户偏好的唯一真源，属性写入通过 didSet 同步到 UserDefaults。
import SwiftUI

/// 面板关闭后弹回根界面的延迟时长；键未设置时按 `.immediately` 处理。
enum PopToRootTimeout: Int, CaseIterable, Identifiable, Sendable {
    case immediately = 0
    case afterFive = 5
    case afterFifteen = 15
    case afterThirty = 30
    case afterSixty = 60
    case afterNinety = 90

    var id: Int { rawValue }

    var title: String {
        self == .immediately ? "Immediately" : "After \(rawValue) seconds"
    }

    var interval: TimeInterval { TimeInterval(rawValue) }
}

/// 加入会议卡片提前多久出现，以及会议开始后仍保留多久。参见 UpcomingWindow。
enum JoinWindow: Int, CaseIterable, Identifiable, Sendable {
    case one = 1
    case two = 2
    case five = 5
    case ten = 10
    case fifteen = 15

    var id: Int { rawValue }

    var title: String { rawValue == 1 ? "1 minute" : "\(rawValue) minutes" }
}

/// 菜单栏日历项提前多久开始接管下一场会议。取值 0 表示保留当天剩余时间，而
/// `integer(forKey:)` 在键未设置时同样返回 0。
enum MenuBarEvents: Int, CaseIterable, Identifiable, Sendable {
    case today = 0
    case two = 2
    case five = 5
    case ten = 10
    case thirty = 30

    var id: Int { rawValue }

    var title: String { self == .today ? "Today" : "\(rawValue) minutes before" }
}

/// 日历在菜单栏中的独立显示方式。取值 0 与偏好未设置时的默认值一致。
enum CalendarMenuBarDisplay: Int, CaseIterable, Identifiable, Sendable {
    case disabled = 0
    case meetingIcon = 1
    case meetingTitle = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .disabled: "Disabled"
        case .meetingIcon: "Meeting Icon"
        case .meetingTitle: "Meeting Title"
        }
    }
}

/// 已开始的会议占用菜单栏的时长。默认值 0 表示它在开始时即消失。
enum CalendarLauncherLimit: Int, CaseIterable, Identifiable, Sendable {
    case one = 1
    case three = 3
    case five = 5
    case all = 0

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .one: "1 next"
        case .three: "3 next"
        case .five: "5 next"
        case .all: "All"
        }
    }

    var maximum: Int? { self == .all ? nil : rawValue }
}

/// 已开始的会议是否会在菜单栏中停留足够久，以显示剩余时间。
enum HideCurrentEvent: Int, CaseIterable, Identifiable, Sendable {
    case dontHide = -1
    case automatically = 0
    case afterFive = 5
    case afterTen = 10
    case afterThirty = 30

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .dontHide: "Keep visible — show time left"
        case .automatically: "Automatically"
        default: "After \(rawValue) minutes"
        }
    }

    var hidesAtStart: Bool { self == .automatically }
    var minutes: Int? { rawValue > 0 ? rawValue : nil }
}

/// 用户偏好的唯一内存投影：`init` 从 UserDefaults 还原，属性写入通过 `didSet` 同步回去。
@MainActor
@Observable
final class AppSettings {
    // 直接读写标准 UserDefaults，不参与 @Observable 变更追踪。
    @ObservationIgnored private let defaults = UserDefaults.standard
    private typealias Key = AppSettingsKey

    /// `AppIndex` 的扫描范围，按扫描顺序排列；它被观察，因此修改会触发重建索引。
    var searchScopes: [String] {
        didSet { defaults.set(searchScopes, forKey: Key.searchScopes.rawValue) }
    }

    var launcherShowsSuggestions: Bool {
        didSet {
            defaults.set(launcherShowsSuggestions, forKey: Key.launcherShowsSuggestions.rawValue)
        }
    }

    /// 根搜索模糊命中的宽松程度：低于该相关度阈值的结果不予展示。
    var rootSearchSensitivity: SearchSensitivity {
        didSet {
            defaults.set(rootSearchSensitivity.rawValue, forKey: Key.rootSearchSensitivity.rawValue)
        }
    }

    /// 默认开启（与其他功能开关不同）：启动器本就应当保留历史记录。
    var clipboardEnabled: Bool {
        didSet { defaults.set(clipboardEnabled, forKey: Key.clipboardEnabled.rawValue) }
    }

    var clipboardTextSearchEnabled: Bool {
        didSet { defaults.set(clipboardTextSearchEnabled, forKey: Key.clipboardTextSearchEnabled.rawValue) }
    }

    var clipboardRetention: ClipboardRetention {
        didSet {
            defaults.set(clipboardRetention.rawValue, forKey: Key.clipboardRetention.rawValue)
        }
    }

    /// 永不记录其内容的 App Bundle ID；有序保存，以保证设置列表顺序稳定。
    var clipboardDisabledApps: [String] {
        didSet { defaults.set(clipboardDisabledApps, forKey: Key.clipboardDisabledApps.rawValue) }
    }

    /// 在剪贴板条目上按 ↵ 的默认动作；选择「粘贴」时会占用该动作让出的快捷键组合。
    var clipboardDefaultAction: ClipboardDefaultAction {
        didSet {
            defaults.set(
                clipboardDefaultAction.rawValue, forKey: Key.clipboardDefaultAction.rawValue)
        }
    }

    var launchAtLogin: Bool {
        didSet { LaunchAtLogin.set(launchAtLogin) }
    }

    /// 启动器图标是否可见；把图标拖出菜单栏会把它关闭。
    var showInMenuBar: Bool {
        didSet { defaults.set(showInMenuBar, forKey: Key.showInMenuBar.rawValue) }
    }

    var automaticallyCheckForUpdates: Bool {
        didSet {
            defaults.set(
                automaticallyCheckForUpdates, forKey: Key.automaticallyCheckForUpdates.rawValue)
        }
    }

    /// 被映射为 Hyper 组合键的物理按键；`HyperKeyTap` 通过观察者响应其变化。
    var hyperKey: HyperKeyPhysicalKey {
        didSet { defaults.set(hyperKey.rawValue, forKey: Key.hyperKey.rawValue) }
    }

    /// Hyper 是否包含 ⇧：开启为 ⌃⌥⇧⌘，关闭为 ⌃⌥⌘。
    var hyperKeyIncludesShift: Bool {
        didSet { defaults.set(hyperKeyIncludesShift, forKey: Key.hyperKeyIncludesShift.rawValue) }
    }

    var hyperKeyQuickPress: HyperKeyQuickPress {
        didSet {
            defaults.set(hyperKeyQuickPress.rawValue, forKey: Key.hyperKeyQuickPress.rawValue)
        }
    }

    /// 渲染与复制支持肤色修饰的 emoji 时所使用的首选肤色。
    var emojiSkinTone: EmojiSkinTone {
        didSet { defaults.set(emojiSkinTone.rawValue, forKey: Key.emojiSkinTone.rawValue) }
    }

    /// emoji 选择器打开时使用的网格密度；会话内的缩放仅临时生效。
    var emojiGridColumns: EmojiGridColumns {
        didSet { defaults.set(emojiGridColumns.rawValue, forKey: Key.emojiGridColumns.rawValue) }
    }

    /// 面板关闭后保留自身状态、在弹回根启动器之前等待的时长。
    var popToRootTimeout: PopToRootTimeout {
        didSet { defaults.set(popToRootTimeout.rawValue, forKey: Key.popToRootTimeout.rawValue) }
    }

    /// 按 Escape 是逐级返回面板打开过的界面，还是直接关闭窗口。
    var escapeKeyBehavior: EscapeKeyBehavior {
        didSet { defaults.set(escapeKeyBehavior.rawValue, forKey: Key.escapeKeyBehavior.rawValue) }
    }

    /// 跟随 macOS，或把 GearMac 固定在某种外观。由 `AppCore.applyAppearance()` 应用。
    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance.rawValue) }
    }

    /// 计算器读写数字时使用的分隔符；`.system` 跟随「语言与地区」设置。
    var calcNumberStyle: CalcNumberStyle {
        didSet { defaults.set(calcNumberStyle.rawValue, forKey: Key.calcNumberStyle.rawValue) }
    }

    /// 只缩放面板及其浮动附属界面。通过 `InterfaceSize.metrics` 读取。
    var interfaceSize: InterfaceSize {
        didSet {
            defaults.set(interfaceSize.rawValue, forKey: Key.interfaceSize.rawValue)
            let shift = Double(
                (oldValue.metrics.size.panelWidth - interfaceSize.metrics.size.panelWidth) / 2)
            if shift != 0 {
                palettePositions = palettePositions.mapValues { offset in
                    offset.count == 2 ? [offset[0] + shift, offset[1]] : offset
                }
            }
        }
    }

    /// 界面语言偏好；读取 `language` 会登记 Observation 依赖，因此切换语言可即时重渲染。
    var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Key.language.rawValue) }
    }

    /// 当前生效的具体语言（`.system` 已按系统首选语言解析）。
    var resolvedLanguage: AppLanguage { language.resolved() }

    /// 受语言影响的 `Locale`，供日期与数字格式化使用。
    var localizedLocale: Locale { Locale(identifier: resolvedLanguage.localeIdentifier) }

    /// 取本地化文案；读取 `language` 形成观察依赖，视图在语言切换后自动更新。
    func text<K: LocalizableKey>(_ key: K) -> String { L10n.string(key, language: language) }

    /// 以细长搜索栏的形式唤起启动器，输入时展开为完整列表。
    var compactMode: Bool {
        didSet { defaults.set(compactMode, forKey: Key.compactMode.rawValue) }
    }

    /// 在紧凑搜索栏右侧固定常用 App 图标（⌘1–⌘5 可直接启动）。
    var showFavoritesInCompactMode: Bool {
        didSet {
            defaults.set(
                showFavoritesInCompactMode, forKey: Key.showFavoritesInCompactMode.rawValue)
        }
    }

    /// 在指针所在显示器上唤出面板，而不是在菜单栏所在的显示器上。
    var openOnCursorScreen: Bool {
        didSet { defaults.set(openOnCursorScreen, forKey: Key.openOnCursorScreen.rawValue) }
    }

    var autoSwitchInputSourceID: String? {
        didSet {
            guard let autoSwitchInputSourceID else {
                defaults.removeObject(forKey: Key.autoSwitchInputSource.rawValue)
                return
            }
            defaults.set(autoSwitchInputSourceID, forKey: Key.autoSwitchInputSource.rawValue)
        }
    }

    /// 允许通过面板上边缘拖动面板；默认关闭，因此大多数唤起操作不会抓取鼠标。
    var paletteDraggable: Bool {
        didSet { defaults.set(paletteDraggable, forKey: Key.paletteDraggable.rawValue) }
    }

    /// 面板左上角被拖到何处：按显示器分别记录，取相对该显示器的坐标。
    var palettePositions: [String: [Double]] {
        didSet { defaults.set(palettePositions, forKey: Key.palettePosition.rawValue) }
    }

    var paletteExpandedCenterDisplays: Set<String> {
        didSet {
            defaults.set(
                Array(paletteExpandedCenterDisplays),
                forKey: Key.paletteExpandedCenterDisplays.rawValue)
        }
    }

    /// 读取指定显示器上记录的调色板位置；无记录或数据不完整时返回 nil。
    func palettePosition(on display: String) -> CGPoint? {
        palettePositions[display].flatMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
    }

    /// 记录或清除某显示器上的调色板位置，并按需标记「居中展开」。
    func setPalettePosition(_ offset: CGPoint?, on display: String, expandedCenter: Bool) {
        if offset != nil && expandedCenter {
            paletteExpandedCenterDisplays.insert(display)
        } else {
            paletteExpandedCenterDisplays.remove(display)
        }
        guard let offset else {
            palettePositions.removeValue(forKey: display)
            return
        }
        palettePositions[display] = [offset.x, offset.y]
    }

    // 以下功能开关默认关闭，且「关闭」意味着彻底关闭。
    var fileSearchEnabled: Bool {
        didSet { defaults.set(fileSearchEnabled, forKey: Key.fileSearchEnabled.rawValue) }
    }

    /// 使用 `~` 缩写的路径，因此在某台机器上做的备份在另一台机器上依然有效。
    var fileSearchScopes: [String] {
        didSet { defaults.set(fileSearchScopes, forKey: Key.fileSearchScopes.rawValue) }
    }

    /// 仅包含用户自行添加的规则；内置规则已编译进 `FileSearchIgnoreList`。
    var fileSearchIgnorePatterns: [String] {
        didSet {
            defaults.set(fileSearchIgnorePatterns, forKey: Key.fileSearchIgnorePatterns.rawValue)
        }
    }

    var notesEnabled: Bool {
        didSet { defaults.set(notesEnabled, forKey: Key.notesEnabled.rawValue) }
    }

    var dictationEnabled: Bool {
        didSet { defaults.set(dictationEnabled, forKey: Key.dictationEnabled.rawValue) }
    }

    var dictationMode: DictationMode {
        didSet { defaults.set(dictationMode.rawValue, forKey: Key.dictationMode.rawValue) }
    }

    var dictationModel: DictationModel {
        didSet { defaults.set(dictationModel.rawValue, forKey: Key.dictationModel.rawValue) }
    }

    /// 为 nil 时由 macOS 跟随系统输入设备的变化。
    var dictationMicrophone: String? {
        didSet { defaults.set(dictationMicrophone, forKey: Key.dictationMicrophone.rawValue) }
    }

    var dictationDestination: DictationDestination {
        didSet { defaults.set(dictationDestination.rawValue, forKey: Key.dictationDestination.rawValue) }
    }

    var dictationAdaptsCapitalization: Bool {
        didSet {
            defaults.set(dictationAdaptsCapitalization, forKey: Key.dictationAdaptsCapitalization.rawValue)
        }
    }

    var dictationIdleRelease: DictationIdleRelease {
        didSet { defaults.set(dictationIdleRelease.rawValue, forKey: Key.dictationIdleRelease.rawValue) }
    }

    var dictationLanguage: String? {
        didSet { defaults.set(dictationLanguage, forKey: Key.dictationLanguage.rawValue) }
    }

    var notesRendersMarkdown: Bool {
        didSet { defaults.set(notesRendersMarkdown, forKey: Key.notesRendersMarkdown.rawValue) }
    }

    var notesShowsFormattingBar: Bool {
        didSet { defaults.set(notesShowsFormattingBar, forKey: Key.notesShowsFormattingBar.rawValue) }
    }

    /// 用户填写的笔记文件夹路径，允许使用 `~`；为 nil 时保在 Application Support 中。
    var notesFolder: String? {
        didSet { defaults.set(notesFolder, forKey: Key.notesFolder.rawValue) }
    }

    /// 默认关闭：连接服务器即表示同意运行并非 GearMac 编写的代码。
    var mcpEnabled: Bool {
        didSet { defaults.set(mcpEnabled, forKey: Key.mcpEnabled.rawValue) }
    }
    var aiEnabled: Bool {
        didSet { defaults.set(aiEnabled, forKey: Key.aiEnabled.rawValue) }
    }

    var customCommandsEnabled: Bool {
        didSet { defaults.set(customCommandsEnabled, forKey: Key.customCommandsEnabled.rawValue) }
    }

    /// 在功能已开启的前提下，仅控制其启动器分区是否显示。
    var customCommandsShowInLauncher: Bool {
        didSet {
            defaults.set(
                customCommandsShowInLauncher, forKey: Key.customCommandsShowInLauncher.rawValue)
        }
    }

    /// 同时作为关键词展开的授权，因此先弹确认，且绝不随备份迁移。
    var snippetsEnabled: Bool {
        didSet { defaults.set(snippetsEnabled, forKey: Key.snippetsEnabled.rawValue) }
    }

    /// 默认关闭：开启后 GearMac 可以在任意位置读取选中内容并覆盖输入。
    var quickActionsEnabled: Bool {
        didSet { defaults.set(quickActionsEnabled, forKey: Key.quickActionsEnabled.rawValue) }
    }

    var snippetsShowInLauncher: Bool {
        didSet { defaults.set(snippetsShowInLauncher, forKey: Key.snippetsShowInLauncher.rawValue) }
    }

    /// 用户填写的片段文件夹路径，允许使用 `~`；为 nil 时保在 Application Support 中。
    var snippetsFolder: String? {
        didSet { defaults.set(snippetsFolder, forKey: Key.snippetsFolder.rawValue) }
    }

    var navigationEnabled: Bool {
        didSet { defaults.set(navigationEnabled, forKey: Key.navigationEnabled.rawValue) }
    }

    /// 菜单栏「搜索菜单栏项目」完全拒绝读取其菜单的 App Bundle ID。
    var menuSearchDisabledApps: [String] {
        didSet { defaults.set(menuSearchDisabledApps, forKey: Key.menuSearchDisabledApps.rawValue) }
    }

    /// 默认关闭：Apple 菜单在每个 App 中都一样，收录只会让每份快照变冗余。
    var menuSearchShowsAppleMenu: Bool {
        didSet {
            defaults.set(menuSearchShowsAppleMenu, forKey: Key.menuSearchShowsAppleMenu.rawValue)
        }
    }

    /// 运行第三方 JavaScript 的授权：需要确认、默认关闭、不随备份迁移。
    var extensionsEnabled: Bool {
        didSet { defaults.set(extensionsEnabled, forKey: Key.extensionsEnabled.rawValue) }
    }

    var extensionsShowInLauncher: Bool {
        didSet {
            defaults.set(extensionsShowInLauncher, forKey: Key.extensionsShowInLauncher.rawValue)
        }
    }

    /// 只有从 GitHub 安装时才需要包管理器——商店提供的扩展已构建好。
    var extensionPackageManager: ExtensionPackageManager {
        didSet {
            defaults.set(
                extensionPackageManager.rawValue, forKey: Key.extensionPackageManager.rawValue)
        }
    }

    /// 用于 GearMac 不认识的工具链——常见的是 mise 或 Nix 的 shim。
    var extensionCustomSearchPaths: [String] {
        didSet {
            defaults.set(
                extensionCustomSearchPaths, forKey: Key.extensionCustomSearchPaths.rawValue)
        }
    }

    /// 同时作为日历访问授权，因此只能由 `CalendarCoordinator` 写入。
    var calendarEnabled: Bool {
        didSet { defaults.set(calendarEnabled, forKey: Key.calendarEnabled.rawValue) }
    }

    var calendarShowInLauncher: Bool {
        didSet {
            defaults.set(calendarShowInLauncher, forKey: Key.calendarShowInLauncher.rawValue)
        }
    }

    var calendarLauncherLimit: CalendarLauncherLimit {
        didSet {
            defaults.set(calendarLauncherLimit.rawValue, forKey: Key.calendarLauncherLimit.rawValue)
        }
    }

    /// 收窄的是实际抓取范围而非展示范围，因此所有界面读取的日期区间一致。
    var calendarSpan: MeetingSpan {
        didSet { defaults.set(calendarSpan.rawValue, forKey: Key.calendarSpan.rawValue) }
    }

    var joinWindowMinutes: JoinWindow {
        didSet { defaults.set(joinWindowMinutes.rawValue, forKey: Key.joinWindowMinutes.rawValue) }
    }

    /// 让 App 可以无人值守地打开会议链接，因此只能由「日历」设置页的开关写入。
    var autoJoinMeetings: Bool {
        didSet { defaults.set(autoJoinMeetings, forKey: Key.autoJoinMeetings.rawValue) }
    }

    var autoJoinConfirms: Bool {
        didSet { defaults.set(autoJoinConfirms, forKey: Key.autoJoinConfirms.rawValue) }
    }

    var autoJoinNamedProvidersOnly: Bool {
        didSet {
            defaults.set(
                autoJoinNamedProvidersOnly, forKey: Key.autoJoinNamedProvidersOnly.rawValue)
        }
    }

    /// 同时作为摄像头授权，因此只能由「日历」设置页的开关写入。
    var cameraPreview: Bool {
        didSet { defaults.set(cameraPreview, forKey: Key.cameraPreview.rawValue) }
    }

    /// 为 nil 时用默认浏览器打开会议链接。
    var meetingBrowserBundleID: String? {
        didSet {
            guard let meetingBrowserBundleID else {
                defaults.removeObject(forKey: Key.meetingBrowser.rawValue)
                return
            }
            defaults.set(meetingBrowserBundleID, forKey: Key.meetingBrowser.rawValue)
        }
    }

    var menuBarEvents: MenuBarEvents {
        didSet { defaults.set(menuBarEvents.rawValue, forKey: Key.menuBarEvents.rawValue) }
    }

    var calendarMenuBarDisplay: CalendarMenuBarDisplay {
        didSet {
            defaults.set(
                calendarMenuBarDisplay.rawValue, forKey: Key.calendarMenuBarDisplay.rawValue)
        }
    }

    var menuBarLinkedEventsOnly: Bool {
        didSet {
            defaults.set(
                menuBarLinkedEventsOnly, forKey: Key.menuBarLinkedEventsOnly.rawValue)
        }
    }

    var calendarMenuBarHidesWhenEmpty: Bool {
        didSet {
            defaults.set(
                calendarMenuBarHidesWhenEmpty, forKey: Key.calendarMenuBarHidesWhenEmpty.rawValue)
        }
    }

    var hideCurrentEvent: HideCurrentEvent {
        didSet { defaults.set(hideCurrentEvent.rawValue, forKey: Key.hideCurrentEvent.rawValue) }
    }

    /// 「关闭」表示彻底关闭：启动器中没有条目，已注册的快捷键也不会移动任何窗口。
    var windowManagementEnabled: Bool {
        didSet {
            defaults.set(windowManagementEnabled, forKey: Key.windowManagementEnabled.rawValue)
        }
    }

    var windowManagementShowInLauncher: Bool {
        didSet {
            defaults.set(
                windowManagementShowInLauncher,
                forKey: Key.windowManagementShowInLauncher.rawValue)
        }
    }

    /// 平铺窗口之间以及与屏幕边缘之间的间距（点）；上限由 `WindowPlacementEngine` 限制。
    var windowGap: Int {
        didSet { defaults.set(windowGap, forKey: Key.windowGap.rawValue) }
    }

    /// 独立开关：隐藏 34 个命令行不应连带隐藏用户自建的布局。
    var windowLayoutsShowInLauncher: Bool {
        didSet {
            defaults.set(
                windowLayoutsShowInLauncher, forKey: Key.windowLayoutsShowInLauncher.rawValue)
        }
    }

    var windowRoomsShowInLauncher: Bool {
        didSet {
            defaults.set(windowRoomsShowInLauncher, forKey: Key.windowRoomsShowInLauncher.rawValue)
        }
    }

    /// 重复触发某个半屏快捷键时的行为：无操作、逐步改变尺寸，或在各显示器之间轮转。
    var windowCycle: WindowCycle {
        didSet { defaults.set(windowCycle.rawValue, forKey: Key.windowCycle.rawValue) }
    }

    /// 「关闭」表示彻底关闭：即使快捷键仍已注册，也不会打开任何内容。
    var quicklinksEnabled: Bool {
        didSet { defaults.set(quicklinksEnabled, forKey: Key.quicklinksEnabled.rawValue) }
    }

    var quicklinksShowInLauncher: Bool {
        didSet {
            defaults.set(quicklinksShowInLauncher, forKey: Key.quicklinksShowInLauncher.rawValue)
        }
    }

    /// 「关闭」表示绝不运行「快捷指令」工具：即使绑定了快捷键也不会执行。
    var appleShortcutsEnabled: Bool {
        didSet { defaults.set(appleShortcutsEnabled, forKey: Key.appleShortcutsEnabled.rawValue) }
    }

    /// 请求打开新窗口而非新标签页；关闭时采用 macOS 默认行为。
    var quicklinkOpensNewWindow: Bool {
        didSet {
            defaults.set(quicklinkOpensNewWindow, forKey: Key.quicklinkOpensNewWindow.rawValue)
        }
    }

    /// 没有可读取的选中内容可传时，`{selection}` 占位符的行为。
    var quicklinkSelectionFallback: QuicklinkSelectionFallback {
        didSet {
            defaults.set(
                quicklinkSelectionFallback.rawValue,
                forKey: Key.quicklinkSelectionFallback.rawValue)
        }
    }

    var quicklinkConfirmsBeforeDelete: Bool {
        didSet {
            defaults.set(
                quicklinkConfirmsBeforeDelete, forKey: Key.quicklinkConfirmsBeforeDelete.rawValue)
        }
    }

    /// 支持窗口是否允许再次自行弹出；关闭表示不再询问。
    var supportRemindersEnabled: Bool {
        didSet { defaults.set(supportRemindersEnabled, forKey: Key.supportReminders.rawValue) }
    }

    /// settings.json 是否镜像这些设置；由 `AppCore` 启动和停止镜像。
    var settingsFileEnabled: Bool {
        didSet { defaults.set(settingsFileEnabled, forKey: Key.settingsFileEnabled.rawValue) }
    }

    /// 从 UserDefaults 还原全部偏好；键不存在或取值非法时回落到各自的默认值。
    init() {
        // 唯一默认开启的功能开关，因此「键不存在」必须优先于存储的 `false`。
        clipboardEnabled =
            defaults.object(forKey: Key.clipboardEnabled.rawValue) == nil
            || defaults.bool(forKey: Key.clipboardEnabled.rawValue)
        // `integer(forKey:)` 在未设置时返回 0，不会匹配到任何 case。
        clipboardTextSearchEnabled = defaults.bool(forKey: Key.clipboardTextSearchEnabled.rawValue)
        clipboardRetention =
            ClipboardRetention(rawValue: defaults.integer(forKey: Key.clipboardRetention.rawValue))
            ?? .threeMonths
        // 默认排除密码管理器，直到用户首次编辑该列表为止。
        clipboardDisabledApps =
            defaults.stringArray(forKey: Key.clipboardDisabledApps.rawValue)
            ?? ["com.apple.keychainaccess", "com.apple.Passwords"]
        clipboardDefaultAction =
            defaults.string(forKey: Key.clipboardDefaultAction.rawValue)
            .flatMap(ClipboardDefaultAction.init) ?? .paste
        launchAtLogin = LaunchAtLogin.isEnabled
        showInMenuBar =
            defaults.object(forKey: Key.showInMenuBar.rawValue) == nil
            || defaults.bool(forKey: Key.showInMenuBar.rawValue)
        automaticallyCheckForUpdates =
            defaults.object(forKey: Key.automaticallyCheckForUpdates.rawValue) == nil
            || defaults.bool(forKey: Key.automaticallyCheckForUpdates.rawValue)
        hyperKey =
            defaults.string(forKey: Key.hyperKey.rawValue).flatMap(HyperKeyPhysicalKey.init)
            ?? .none
        // 默认值为 true，因此必须区分「键不存在」与存储的 `false`。
        hyperKeyIncludesShift =
            defaults.object(forKey: Key.hyperKeyIncludesShift.rawValue) == nil
            || defaults.bool(forKey: Key.hyperKeyIncludesShift.rawValue)
        hyperKeyQuickPress =
            defaults.string(forKey: Key.hyperKeyQuickPress.rawValue)
            .flatMap(HyperKeyQuickPress.init)
            ?? .none
        emojiSkinTone =
            defaults.string(forKey: Key.emojiSkinTone.rawValue).flatMap(EmojiSkinTone.init) ?? .none
        emojiGridColumns =
            EmojiGridColumns(rawValue: defaults.integer(forKey: Key.emojiGridColumns.rawValue))
            ?? .default
        popToRootTimeout =
            PopToRootTimeout(rawValue: defaults.integer(forKey: Key.popToRootTimeout.rawValue))
            ?? .immediately
        escapeKeyBehavior =
            defaults.string(forKey: Key.escapeKeyBehavior.rawValue).flatMap(EscapeKeyBehavior.init)
            ?? .navigateBackOrClose
        language =
            defaults.string(forKey: Key.language.rawValue).flatMap(AppLanguage.init) ?? .system
        appearance =
            defaults.string(forKey: Key.appearance.rawValue).flatMap(AppAppearance.init) ?? .system
        calcNumberStyle =
            defaults.string(forKey: Key.calcNumberStyle.rawValue).flatMap(CalcNumberStyle.init)
            ?? .system
        interfaceSize =
            defaults.string(forKey: Key.interfaceSize.rawValue).flatMap(InterfaceSize.init)
            ?? .standard
        compactMode = defaults.bool(forKey: Key.compactMode.rawValue)
        // 默认值为 true，因此必须区分「键不存在」与存储的 `false`。
        showFavoritesInCompactMode =
            defaults.object(forKey: Key.showFavoritesInCompactMode.rawValue) == nil
            || defaults.bool(forKey: Key.showFavoritesInCompactMode.rawValue)
        // 未设置时填入默认范围；存储的空数组表示用户有意清空列表。
        searchScopes =
            defaults.stringArray(forKey: Key.searchScopes.rawValue) ?? SearchScopes.defaults
        launcherShowsSuggestions =
            defaults.object(forKey: Key.launcherShowsSuggestions.rawValue) == nil
            || defaults.bool(forKey: Key.launcherShowsSuggestions.rawValue)
        rootSearchSensitivity =
            defaults.string(forKey: Key.rootSearchSensitivity.rawValue)
            .flatMap(SearchSensitivity.init) ?? .default
        openOnCursorScreen =
            defaults.object(forKey: Key.openOnCursorScreen.rawValue) == nil
            || defaults.bool(forKey: Key.openOnCursorScreen.rawValue)
        autoSwitchInputSourceID = defaults.string(forKey: Key.autoSwitchInputSource.rawValue)
        paletteDraggable = defaults.bool(forKey: Key.paletteDraggable.rawValue)
        palettePositions =
            defaults.dictionary(forKey: Key.palettePosition.rawValue)
            as? [String: [Double]] ?? [:]
        paletteExpandedCenterDisplays =
            Set(defaults.stringArray(forKey: Key.paletteExpandedCenterDisplays.rawValue) ?? [])
        fileSearchEnabled = defaults.bool(forKey: Key.fileSearchEnabled.rawValue)
        // 未设置时填入用户主目录；存储的空数组表示清空列表、不搜索任何位置。
        fileSearchScopes =
            defaults.stringArray(forKey: Key.fileSearchScopes.rawValue)
            ?? FileSearchScope.defaultScopes
        fileSearchIgnorePatterns =
            defaults.stringArray(forKey: Key.fileSearchIgnorePatterns.rawValue) ?? []
        notesEnabled = defaults.bool(forKey: Key.notesEnabled.rawValue)
        dictationEnabled = defaults.bool(forKey: Key.dictationEnabled.rawValue)
        dictationMode =
            defaults.string(forKey: Key.dictationMode.rawValue)
            .flatMap(DictationMode.init) ?? .toggle
        dictationModel =
            defaults.string(forKey: Key.dictationModel.rawValue)
            .flatMap(DictationModel.init) ?? .redux
        dictationMicrophone = defaults.string(forKey: Key.dictationMicrophone.rawValue)
        dictationDestination =
            defaults.string(forKey: Key.dictationDestination.rawValue)
            .flatMap(DictationDestination.init) ?? .paste
        dictationAdaptsCapitalization =
            defaults.object(forKey: Key.dictationAdaptsCapitalization.rawValue) == nil
            || defaults.bool(forKey: Key.dictationAdaptsCapitalization.rawValue)
        dictationIdleRelease =
            defaults.object(forKey: Key.dictationIdleRelease.rawValue)
            .flatMap { $0 as? Int }
            .flatMap(DictationIdleRelease.init(rawValue:)) ?? .oneMinute
        dictationLanguage =
            defaults.string(forKey: Key.dictationLanguage.rawValue)
            .flatMap(DictationLanguage.init(rawValue:))?.rawValue
        notesRendersMarkdown =
            defaults.object(forKey: Key.notesRendersMarkdown.rawValue) == nil
            || defaults.bool(forKey: Key.notesRendersMarkdown.rawValue)
        notesShowsFormattingBar =
            defaults.object(forKey: Key.notesShowsFormattingBar.rawValue) == nil
            || defaults.bool(forKey: Key.notesShowsFormattingBar.rawValue)
        notesFolder = defaults.string(forKey: Key.notesFolder.rawValue)
        aiEnabled = defaults.bool(forKey: Key.aiEnabled.rawValue)
        mcpEnabled = defaults.bool(forKey: Key.mcpEnabled.rawValue)
        customCommandsEnabled = defaults.bool(forKey: Key.customCommandsEnabled.rawValue)
        // 这些开关默认开启，因此必须区分「键不存在」与存储的 `false`。
        customCommandsShowInLauncher =
            defaults.object(forKey: Key.customCommandsShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.customCommandsShowInLauncher.rawValue)
        snippetsEnabled = defaults.bool(forKey: Key.snippetsEnabled.rawValue)
        quickActionsEnabled = defaults.bool(forKey: Key.quickActionsEnabled.rawValue)
        snippetsShowInLauncher =
            defaults.object(forKey: Key.snippetsShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.snippetsShowInLauncher.rawValue)
        snippetsFolder = defaults.string(forKey: Key.snippetsFolder.rawValue)
        // 与同级开关不同，这里是主动选择加入：在用户要求之前不会加载任何扩展相关内容。
        extensionsEnabled = defaults.bool(forKey: Key.extensionsEnabled.rawValue)
        extensionsShowInLauncher =
            defaults.object(forKey: Key.extensionsShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.extensionsShowInLauncher.rawValue)
        extensionPackageManager =
            defaults.string(forKey: Key.extensionPackageManager.rawValue)
            .flatMap(ExtensionPackageManager.init(rawValue:)) ?? .automatic
        extensionCustomSearchPaths =
            defaults.stringArray(forKey: Key.extensionCustomSearchPaths.rawValue) ?? []
        // 与扩展一样是主动选择加入：在用户要求之前不会加载 EventKit。
        calendarEnabled = defaults.bool(forKey: Key.calendarEnabled.rawValue)
        calendarShowInLauncher =
            defaults.object(forKey: Key.calendarShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.calendarShowInLauncher.rawValue)
        calendarLauncherLimit =
            defaults.object(forKey: Key.calendarLauncherLimit.rawValue)
            .flatMap { $0 as? Int }
            .flatMap(CalendarLauncherLimit.init(rawValue:)) ?? .five
        // 没有 case 取值为 0，因此未设置的键会落到默认值。
        calendarSpan =
            MeetingSpan(rawValue: defaults.integer(forKey: Key.calendarSpan.rawValue))
            ?? .todayAndTomorrow
        joinWindowMinutes =
            JoinWindow(rawValue: defaults.integer(forKey: Key.joinWindowMinutes.rawValue)) ?? .five
        autoJoinMeetings = defaults.bool(forKey: Key.autoJoinMeetings.rawValue)
        autoJoinConfirms =
            defaults.object(forKey: Key.autoJoinConfirms.rawValue) == nil
            || defaults.bool(forKey: Key.autoJoinConfirms.rawValue)
        autoJoinNamedProvidersOnly = defaults.bool(forKey: Key.autoJoinNamedProvidersOnly.rawValue)
        cameraPreview = defaults.bool(forKey: Key.cameraPreview.rawValue)
        meetingBrowserBundleID = defaults.string(forKey: Key.meetingBrowser.rawValue)
        // 两者的默认值都是各自的 0 值 case，因此未设置的键无需额外做存在性检查。
        menuBarEvents =
            MenuBarEvents(rawValue: defaults.integer(forKey: Key.menuBarEvents.rawValue)) ?? .today
        calendarMenuBarDisplay =
            CalendarMenuBarDisplay(
                rawValue: defaults.integer(forKey: Key.calendarMenuBarDisplay.rawValue))
            ?? .disabled
        menuBarLinkedEventsOnly =
            defaults.object(forKey: Key.menuBarLinkedEventsOnly.rawValue) == nil
            || defaults.bool(forKey: Key.menuBarLinkedEventsOnly.rawValue)
        calendarMenuBarHidesWhenEmpty =
            defaults.bool(forKey: Key.calendarMenuBarHidesWhenEmpty.rawValue)
        hideCurrentEvent =
            defaults.object(forKey: Key.hideCurrentEvent.rawValue)
            .flatMap { $0 as? Int }
            .flatMap(HideCurrentEvent.init(rawValue:)) ?? .dontHide
        navigationEnabled = defaults.bool(forKey: Key.navigationEnabled.rawValue)
        menuSearchDisabledApps =
            defaults.stringArray(forKey: Key.menuSearchDisabledApps.rawValue) ?? []
        menuSearchShowsAppleMenu = defaults.bool(forKey: Key.menuSearchShowsAppleMenu.rawValue)
        windowManagementEnabled = defaults.bool(forKey: Key.windowManagementEnabled.rawValue)
        windowManagementShowInLauncher =
            defaults.object(forKey: Key.windowManagementShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.windowManagementShowInLauncher.rawValue)
        // 未设置时读作 0，而 0 本就是预期默认值——不存在空缺。
        windowGap = defaults.integer(forKey: Key.windowGap.rawValue)
        windowCycle =
            defaults.string(forKey: Key.windowCycle.rawValue).flatMap(WindowCycle.init) ?? .off
        windowLayoutsShowInLauncher =
            defaults.object(forKey: Key.windowLayoutsShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.windowLayoutsShowInLauncher.rawValue)
        windowRoomsShowInLauncher =
            defaults.object(forKey: Key.windowRoomsShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.windowRoomsShowInLauncher.rawValue)
        quicklinksEnabled = defaults.bool(forKey: Key.quicklinksEnabled.rawValue)
        quicklinksShowInLauncher =
            defaults.object(forKey: Key.quicklinksShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.quicklinksShowInLauncher.rawValue)
        appleShortcutsEnabled = defaults.bool(forKey: Key.appleShortcutsEnabled.rawValue)
        quicklinkOpensNewWindow = defaults.bool(forKey: Key.quicklinkOpensNewWindow.rawValue)
        quicklinkSelectionFallback =
            defaults.string(forKey: Key.quicklinkSelectionFallback.rawValue)
            .flatMap(QuicklinkSelectionFallback.init) ?? .ask
        quicklinkConfirmsBeforeDelete =
            defaults.object(forKey: Key.quicklinkConfirmsBeforeDelete.rawValue) == nil
            || defaults.bool(forKey: Key.quicklinkConfirmsBeforeDelete.rawValue)
        supportRemindersEnabled =
            defaults.object(forKey: Key.supportReminders.rawValue) == nil
            || defaults.bool(forKey: Key.supportReminders.rawValue)
        settingsFileEnabled = defaults.bool(forKey: Key.settingsFileEnabled.rawValue)
    }
}
