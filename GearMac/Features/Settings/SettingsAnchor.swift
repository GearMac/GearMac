// 文件职责：集中定义设置界面的锚点（每个 Section）、搜索命中目标与滚动请求，供搜索目录与设置页共用。
// 分层：Settings（Model）；锚点与目标均为纯值类型，标题字符串是目录和页面唯一共用的来源。
/// 某个设置页里的一个 `Section`。标题只在此处命名一次，因此搜索目录与页面本身不会出现分歧：
/// 搜索结果携带锚点，页面的 `.settingsAnchor(_:)` 标记该结果应滚动到的位置。
struct SettingsAnchor: Hashable, Sendable {
    let tab: SettingsTab
    /// 该 `Section` 自身的标题文本，同时也是搜索结果面包屑所显示的文案。
    let title: String
}

// 全部按「<页面><分区>」命名，因此某个分区的常量名总能直接从名称推断出来。
extension SettingsAnchor {
    static let generalGlobalShortcuts = Self(tab: .general, title: "Global Shortcuts")
    static let generalSearch = Self(tab: .general, title: "Search")
    static let generalHyperKey = Self(tab: .general, title: "Hyper Key")
    static let generalAppearance = Self(tab: .general, title: "Appearance")
    static let generalCalculator = Self(tab: .general, title: "Calculator")
    static let generalGeneral = Self(tab: .general, title: "General")

    static let applicationsSearchScopes = Self(tab: .applications, title: "Search Scopes")
    static let applicationsApplications = Self(tab: .applications, title: "Applications")

    static let systemSettingsSystemSettings = Self(tab: .systemSettings, title: "System Settings")

    static let systemActionsSystemActions = Self(tab: .systemActions, title: "System Actions")

    static let commandsCommands = Self(tab: .commands, title: "Commands")
    static let commandsCustomCommands = Self(tab: .commands, title: "Custom Commands")

    static let quicklinksQuicklinks = Self(tab: .quicklinks, title: "Quicklinks")
    static let quicklinksCommands = Self(tab: .quicklinks, title: "Commands")
    static let quicklinksBehaviour = Self(tab: .quicklinks, title: "Behaviour")
    static let quicklinksImportExport = Self(tab: .quicklinks, title: "Import & Export")

    static let appleShortcutsAppleShortcuts = Self(tab: .appleShortcuts, title: "Apple Shortcuts")
    static let appleShortcutsShortcuts = Self(tab: .appleShortcuts, title: "Shortcuts")

    static let fallbacksFallbacks = Self(tab: .fallbacks, title: "Fallbacks")

    static let aiAI = Self(tab: .ai, title: "AI")
    static let aiProviders = Self(tab: .ai, title: "Providers")
    static let aiDecisions = Self(tab: .ai, title: "Decisions")
    static let aiDefault = Self(tab: .ai, title: "Default")
    static let aiChat = Self(tab: .ai, title: "Chat")
    static let aiConversations = Self(tab: .ai, title: "Conversations")
    static let aiSystemPrompt = Self(tab: .ai, title: "System prompt")
    static let aiMCPServers = Self(tab: .ai, title: "MCP Servers")
    static let aiCommands = Self(tab: .ai, title: "Commands")

    static let quickActionsQuickActions = Self(tab: .quickActions, title: "Quick Actions")
    static let quickActionsActions = Self(tab: .quickActions, title: "Actions")
    static let quickActionsModel = Self(tab: .quickActions, title: "Model")
    static let quickActionsTranslate = Self(tab: .quickActions, title: "Translate")

    static let dictationDictation = Self(tab: .dictation, title: "Dictation")
    static let dictationCommands = Self(tab: .dictation, title: "Commands")
    static let dictationModel = Self(tab: .dictation, title: "Model")
    static let dictationMemory = Self(tab: .dictation, title: "Memory")
    static let dictationOutput = Self(tab: .dictation, title: "Output")

    static let fileSearchFileSearch = Self(tab: .fileSearch, title: "File Search")
    static let fileSearchCommands = Self(tab: .fileSearch, title: "Commands")
    static let fileSearchSearchScopes = Self(tab: .fileSearch, title: "Search Scopes")
    static let fileSearchIgnorePatterns = Self(tab: .fileSearch, title: "Ignore Patterns")

    static let notesNotes = Self(tab: .notes, title: "Notes")
    static let notesOptions = Self(tab: .notes, title: "Options")
    static let notesCommands = Self(tab: .notes, title: "Commands")

    static let snippetsSnippets = Self(tab: .snippets, title: "Snippets")
    static let snippetsCommands = Self(tab: .snippets, title: "Commands")
    static let snippetsLibrary = Self(tab: .snippets, title: "Library")

    static let navigationNavigation = Self(tab: .navigation, title: "Navigation")
    static let navigationCommands = Self(tab: .navigation, title: "Commands")
    static let navigationMenuSearch = Self(tab: .navigation, title: "Search Menu Bar Items")

    static let windowManagementWindowManagement = Self(
        tab: .windowManagement, title: "Window Management")
    static let windowManagementLayouts = Self(tab: .windowManagement, title: "Window Layouts")
    static let windowManagementRooms = Self(tab: .windowManagement, title: "Rooms")
    static let windowManagementLayoutCommands = Self(
        tab: .windowManagement, title: "Layout and Room Commands")
    static let windowManagementOptions = Self(tab: .windowManagement, title: "Options")
    static let windowManagementCustomSizes = Self(tab: .windowManagement, title: "Custom Sizes")

    static let clipboardClipboard = Self(tab: .clipboard, title: "Clipboard")
    static let clipboardCommands = Self(tab: .clipboard, title: "Commands")
    static let clipboardHistory = Self(tab: .clipboard, title: "History")
    static let clipboardDisabledApplications = Self(
        tab: .clipboard, title: "Disabled Applications")

    static let emojiCommands = Self(tab: .emoji, title: "Commands")
    static let emojiAppearance = Self(tab: .emoji, title: "Appearance")

    static let calendarCalendar = Self(tab: .calendar, title: "Calendar")
    static let calendarCommands = Self(tab: .calendar, title: "Commands")
    static let calendarJoining = Self(tab: .calendar, title: "Joining")
    static let calendarMenuBar = Self(tab: .calendar, title: "Menu Bar")
    static let calendarCalendars = Self(tab: .calendar, title: "Calendars")

    static let extensionsExtensions = Self(tab: .extensions, title: "Extensions")
    static let extensionsCompatibility = Self(tab: .extensions, title: "Compatibility")
    static let extensionsInstalled = Self(tab: .extensions, title: "Installed")
    static let extensionsInstall = Self(tab: .extensions, title: "Install")
    static let extensionsStorage = Self(tab: .extensions, title: "Storage")

    static let permissionsAccessibility = Self(tab: .permissions, title: "Accessibility")
    static let permissionsCalendars = Self(tab: .permissions, title: "Calendars")
    static let permissionsMicrophone = Self(tab: .permissions, title: "Microphone")

    static let backupExport = Self(tab: .backup, title: "Export")
    static let backupImport = Self(tab: .backup, title: "Import")
    static let backupImportFromRaycast = Self(tab: .backup, title: "Import from Raycast")
    static let backupSettingsFile = Self(tab: .backup, title: "Settings File")

    static let aboutAbout = Self(tab: .about, title: "About")
    static let aboutLinks = Self(tab: .about, title: "Links")
}

/// 搜索结果的落点：整个分区，或分区内的某一行。
enum SettingsTarget: Hashable, Sendable {
    case section(SettingsAnchor)
    /// 该行可见的标题，同时也是目录条目的标题——两者是同一个字符串。
    case row(SettingsAnchor, String)

    /// 结果对应的分区锚点。
    var anchor: SettingsAnchor {
        switch self {
        case .section(let anchor), .row(let anchor, _): return anchor
        }
    }

    var tab: SettingsTab { anchor.tab }
}

/// 由搜索结果发起的一次跳转。token 让重复选择同一个结果时仍会再次滚动并高亮，
/// 而不是因为相等比较通过就什么都不做。
struct SettingsScrollRequest: Equatable, Sendable {
    let target: SettingsTarget
    let token: Int
}
