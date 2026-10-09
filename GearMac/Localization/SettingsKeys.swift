// 文件职责：设置外壳与语言选择器的本地化键及中英词表。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 设置外壳（标签页、分区）与语言选择器的文案键。
enum SettingsKey: String, LocalizableKey {
    // 语言选择器
    case languageTitle = "settings.language.title"
    case languageCaption = "settings.language.caption"
    case languageSystem = "settings.language.system"
    case languageEnglish = "settings.language.english"
    case languageChinese = "settings.language.chinese"

    // 侧边栏分区
    case sectionGeneral = "settings.section.general"
    case sectionLauncher = "settings.section.launcher"
    case sectionFeatures = "settings.section.features"
    case sectionAdvanced = "settings.section.advanced"

    // 标签页标题
    case tabGeneral = "settings.tab.general"
    case tabApplications = "settings.tab.applications"
    case tabSystemSettings = "settings.tab.systemSettings"
    case tabSystemActions = "settings.tab.systemActions"
    case tabCommands = "settings.tab.commands"
    case tabQuicklinks = "settings.tab.quicklinks"
    case tabAppleShortcuts = "settings.tab.appleShortcuts"
    case tabFallbacks = "settings.tab.fallbacks"
    case tabClipboard = "settings.tab.clipboard"
    case tabSnippets = "settings.tab.snippets"
    case tabFileSearch = "settings.tab.fileSearch"
    case tabWindowManagement = "settings.tab.windowManagement"
    case tabNavigation = "settings.tab.navigation"
    case tabNotes = "settings.tab.notes"
    case tabCalendar = "settings.tab.calendar"
    case tabEmoji = "settings.tab.emoji"
    case tabDictation = "settings.tab.dictation"
    case tabAI = "settings.tab.ai"
    case tabQuickActions = "settings.tab.quickActions"
    case tabExtensions = "settings.tab.extensions"
    case tabPermissions = "settings.tab.permissions"
    case tabBackup = "settings.tab.backup"
    case tabAbout = "settings.tab.about"

    // 侧边栏
    case sidebarSearchPrompt = "settings.sidebar.searchPrompt"

    static let table: [String: L10nEntry] = [
        SettingsKey.languageTitle.rawValue: L10nEntry("Language", "语言"),
        SettingsKey.languageCaption.rawValue: L10nEntry(
            "Applied immediately across the app.", "切换后立即在整个应用内生效。"),
        SettingsKey.languageSystem.rawValue: L10nEntry("Follow System", "跟随系统"),
        SettingsKey.languageEnglish.rawValue: L10nEntry("English", "English"),
        SettingsKey.languageChinese.rawValue: L10nEntry("简体中文", "简体中文"),

        SettingsKey.sectionGeneral.rawValue: L10nEntry("General", "通用"),
        SettingsKey.sectionLauncher.rawValue: L10nEntry("Launcher", "启动器"),
        SettingsKey.sectionFeatures.rawValue: L10nEntry("Features", "功能"),
        SettingsKey.sectionAdvanced.rawValue: L10nEntry("Advanced", "高级"),

        SettingsKey.tabGeneral.rawValue: L10nEntry("General", "通用"),
        SettingsKey.tabApplications.rawValue: L10nEntry("Applications", "应用程序"),
        SettingsKey.tabSystemSettings.rawValue: L10nEntry("System Settings", "系统设置"),
        SettingsKey.tabSystemActions.rawValue: L10nEntry("System Actions", "系统操作"),
        SettingsKey.tabCommands.rawValue: L10nEntry("Commands", "命令"),
        SettingsKey.tabQuicklinks.rawValue: L10nEntry("Quicklinks", "快速链接"),
        SettingsKey.tabAppleShortcuts.rawValue: L10nEntry("Apple Shortcuts", "快捷指令"),
        SettingsKey.tabFallbacks.rawValue: L10nEntry("Fallbacks", "回退项"),
        SettingsKey.tabClipboard.rawValue: L10nEntry("Clipboard", "剪贴板"),
        SettingsKey.tabSnippets.rawValue: L10nEntry("Snippets", "片段"),
        SettingsKey.tabFileSearch.rawValue: L10nEntry("File Search", "文件搜索"),
        SettingsKey.tabWindowManagement.rawValue: L10nEntry("Window Management", "窗口管理"),
        SettingsKey.tabNavigation.rawValue: L10nEntry("Navigation", "导航"),
        SettingsKey.tabNotes.rawValue: L10nEntry("Notes", "笔记"),
        SettingsKey.tabCalendar.rawValue: L10nEntry("Calendar", "日历"),
        SettingsKey.tabEmoji.rawValue: L10nEntry("Emoji & Symbols", "表情与符号"),
        SettingsKey.tabDictation.rawValue: L10nEntry("Dictation", "语音输入"),
        SettingsKey.tabAI.rawValue: L10nEntry("AI", "AI"),
        SettingsKey.tabQuickActions.rawValue: L10nEntry("Quick Actions", "快速操作"),
        SettingsKey.tabExtensions.rawValue: L10nEntry("Extensions", "扩展"),
        SettingsKey.tabPermissions.rawValue: L10nEntry("Permissions", "权限"),
        SettingsKey.tabBackup.rawValue: L10nEntry("Backup", "备份"),
        SettingsKey.tabAbout.rawValue: L10nEntry("About", "关于"),

        SettingsKey.sidebarSearchPrompt.rawValue: L10nEntry("Search", "搜索"),
    ]
}
