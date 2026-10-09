// 文件职责：命令面板（Palette）的本地化键与中英词表：各模式占位文案、应用菜单、筛选提示与后退说明。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 命令面板外壳的文案键。
enum PaletteKey: String, LocalizableKey {
    // 各模式的搜索框占位文案（对应 `PaletteMode`）。
    case placeholderLauncher = "palette.placeholder.launcher"
    case placeholderClipboard = "palette.placeholder.clipboard"
    case placeholderAI = "palette.placeholder.ai"
    case placeholderAIHistory = "palette.placeholder.aiHistory"
    case placeholderCalculatorHistory = "palette.placeholder.calculatorHistory"
    case placeholderEmoji = "palette.placeholder.emoji"
    case placeholderFileSearch = "palette.placeholder.fileSearch"
    case placeholderMenuSearch = "palette.placeholder.menuSearch"
    case placeholderSwitchWindows = "palette.placeholder.switchWindows"
    case placeholderRooms = "palette.placeholder.rooms"
    case placeholderRoomWindows = "palette.placeholder.roomWindows"
    case placeholderSchedule = "palette.placeholder.schedule"
    case placeholderMeetingDetails = "palette.placeholder.meetingDetails"
    case placeholderUninstall = "palette.placeholder.uninstall"
    case placeholderQuicklinks = "palette.placeholder.quicklinks"
    case placeholderSnippets = "palette.placeholder.snippets"
    case placeholderDictionary = "palette.placeholder.dictionary"
    case placeholderExtensionCommand = "palette.placeholder.extensionCommand"

    // 应用菜单
    case appMenuHeaderFormat = "palette.appMenu.headerFormat"
    case appMenuChangelog = "palette.appMenu.changelog"
    case appMenuAbout = "palette.appMenu.about"
    case appMenuSupport = "palette.appMenu.support"
    case appMenuSettings = "palette.appMenu.settings"
    case appMenuQuitFormat = "palette.appMenu.quitFormat"

    // 菜单与筛选
    case menuSearchPlaceholder = "palette.menu.searchPlaceholder"
    case searchActionsPlaceholder = "palette.menu.searchActionsPlaceholder"
    case helpFilterByType = "palette.help.filterByType"
    case helpFilterByCategory = "palette.help.filterByCategory"

    // 底部栏
    case quickAI = "palette.bar.quickAI"
    case quickAIHelp = "palette.bar.quickAIHelp"
    case actions = "palette.bar.actions"

    // 后退说明
    case backEscapeBack = "palette.back.escapeBack"
    case backEscapeClose = "palette.back.escapeClose"
    case backToRootFormat = "palette.back.toRootFormat"

    static let table: [String: L10nEntry] = [
        PaletteKey.placeholderLauncher.rawValue: L10nEntry(
            "Search for apps and commands…", "搜索应用和命令…"),
        PaletteKey.placeholderClipboard.rawValue: L10nEntry(
            "Type to filter entries…", "输入以筛选记录…"),
        PaletteKey.placeholderAI.rawValue: L10nEntry("Ask anything…", "问点什么…"),
        PaletteKey.placeholderAIHistory.rawValue: L10nEntry("Search chats…", "搜索对话…"),
        PaletteKey.placeholderCalculatorHistory.rawValue: L10nEntry(
            "Do math, convert units, or search your past calculations…",
            "做计算、换算单位，或搜索历史计算…"),
        PaletteKey.placeholderEmoji.rawValue: L10nEntry(
            "Search emoji and symbols…", "搜索表情和符号…"),
        PaletteKey.placeholderFileSearch.rawValue: L10nEntry(
            "Search files and folders…", "搜索文件和文件夹…"),
        PaletteKey.placeholderMenuSearch.rawValue: L10nEntry(
            "Search menu bar items…", "搜索菜单栏项目…"),
        PaletteKey.placeholderSwitchWindows.rawValue: L10nEntry(
            "Search open windows…", "搜索已打开的窗口…"),
        PaletteKey.placeholderRooms.rawValue: L10nEntry(
            "Search rooms, or name a new one…", "搜索房间，或为新房间命名…"),
        PaletteKey.placeholderRoomWindows.rawValue: L10nEntry(
            "Search windows, or type an app to add…", "搜索窗口，或输入要添加的应用…"),
        PaletteKey.placeholderSchedule.rawValue: L10nEntry(
            "Search your schedule…", "搜索你的日程…"),
        PaletteKey.placeholderMeetingDetails.rawValue: L10nEntry("Meeting details", "会议详情"),
        PaletteKey.placeholderUninstall.rawValue: L10nEntry(
            "Filter files and folders by name…", "按名称筛选文件和文件夹…"),
        PaletteKey.placeholderQuicklinks.rawValue: L10nEntry(
            "Search quicklinks…", "搜索快速链接…"),
        PaletteKey.placeholderSnippets.rawValue: L10nEntry("Search snippets…", "搜索片段…"),
        PaletteKey.placeholderDictionary.rawValue: L10nEntry("Look up a word…", "查询单词…"),
        PaletteKey.placeholderExtensionCommand.rawValue: L10nEntry("Search…", "搜索…"),

        PaletteKey.appMenuHeaderFormat.rawValue: L10nEntry("%@ v%@", "%@ v%@"),
        PaletteKey.appMenuChangelog.rawValue: L10nEntry("Changelog", "更新日志"),
        PaletteKey.appMenuAbout.rawValue: L10nEntry("About GearMac", "关于 GearMac"),
        PaletteKey.appMenuSupport.rawValue: L10nEntry("Support GearMac", "支持 GearMac"),
        PaletteKey.appMenuSettings.rawValue: L10nEntry("Settings", "设置"),
        PaletteKey.appMenuQuitFormat.rawValue: L10nEntry("Quit %@", "退出 %@"),

        PaletteKey.menuSearchPlaceholder.rawValue: L10nEntry("Search…", "搜索…"),
        PaletteKey.searchActionsPlaceholder.rawValue: L10nEntry(
            "Search for actions…", "搜索操作…"),
        PaletteKey.helpFilterByType.rawValue: L10nEntry("Filter by type  ⌘P", "按类型筛选  ⌘P"),
        PaletteKey.helpFilterByCategory.rawValue: L10nEntry(
            "Filter by category  ⌘P", "按类别筛选  ⌘P"),

        PaletteKey.quickAI.rawValue: L10nEntry("Quick AI", "Quick AI"),
        PaletteKey.quickAIHelp.rawValue: L10nEntry(
            "Ask Quick AI what you typed  ⇥", "把输入内容交给 Quick AI  ⇥"),
        PaletteKey.actions.rawValue: L10nEntry("Actions", "操作"),

        PaletteKey.backEscapeBack.rawValue: L10nEntry("Esc to go back", "Esc 返回"),
        PaletteKey.backEscapeClose.rawValue: L10nEntry("Esc to close", "Esc 关闭"),
        PaletteKey.backToRootFormat.rawValue: L10nEntry(
            "%@ or ⌘ Esc to go to root search", "%@，或 ⌘ Esc 回到根搜索"),
    ]
}
