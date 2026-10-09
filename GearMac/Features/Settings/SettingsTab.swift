// 文件职责：定义设置窗口的 tab 枚举（标题、图标）与侧边栏分区划分。
// 分层：Settings（Model）；case 的声明顺序即显示顺序，标题经 `L10n` 按当前语言本地化。
enum SettingsTab: CaseIterable, Identifiable {
    case general, applications, systemSettings, systemActions, commands, quicklinks, appleShortcuts,
        fallbacks, clipboard, snippets, fileSearch, windowManagement, navigation, notes, calendar, emoji,
        dictation, ai, quickActions, extensions, permissions, backup, about
    /// 使用 case 本身而非索引作为 id：可选择的 `List` 会把分区与行的 id 混在同一个命名空间里。
    var id: Self { self }

    /// 侧边栏/标题中显示的名称。
    var title: String {
        switch self {
        case .general: return "General"
        case .applications: return "Applications"
        case .systemSettings: return "System Settings"
        case .systemActions: return "System Actions"
        case .commands: return "Commands"
        case .quicklinks: return "Quicklinks"
        case .appleShortcuts: return "Apple Shortcuts"
        case .fallbacks: return "Fallbacks"
        case .ai: return "AI"
        case .quickActions: return "Quick Actions"
        case .dictation: return "Dictation"
        case .fileSearch: return "File Search"
        case .notes: return "Notes"
        case .snippets: return "Snippets"
        case .navigation: return "Navigation"
        case .windowManagement: return "Window Management"
        case .clipboard: return "Clipboard"
        case .emoji: return "Emoji & Symbols"
        case .calendar: return "Calendar"
        case .extensions: return "Extensions"
        case .permissions: return "Permissions"
        case .backup: return "Backup"
        case .about: return "About"
        }
    }

    /// 本地化键，供设置界面按当前语言取标题。
    var l10nKey: SettingsKey {
        switch self {
        case .general: return .tabGeneral
        case .applications: return .tabApplications
        case .systemSettings: return .tabSystemSettings
        case .systemActions: return .tabSystemActions
        case .commands: return .tabCommands
        case .quicklinks: return .tabQuicklinks
        case .appleShortcuts: return .tabAppleShortcuts
        case .fallbacks: return .tabFallbacks
        case .clipboard: return .tabClipboard
        case .snippets: return .tabSnippets
        case .fileSearch: return .tabFileSearch
        case .windowManagement: return .tabWindowManagement
        case .navigation: return .tabNavigation
        case .notes: return .tabNotes
        case .calendar: return .tabCalendar
        case .emoji: return .tabEmoji
        case .dictation: return .tabDictation
        case .ai: return .tabAI
        case .quickActions: return .tabQuickActions
        case .extensions: return .tabExtensions
        case .permissions: return .tabPermissions
        case .backup: return .tabBackup
        case .about: return .tabAbout
        }
    }

    /// 按当前语言显示的标题。
    func localizedTitle(_ language: AppLanguage) -> String {
        L10n.string(l10nKey, language: language)
    }

    /// 侧边栏中使用的 SF Symbol 名称。
    var systemImage: String {
        switch self {
        case .general: return "switch.2"
        case .applications: return "square.grid.2x2"
        case .systemSettings: return "gearshape"
        case .systemActions: return "bolt"
        case .commands: return "terminal"
        case .quicklinks: return "link"
        case .appleShortcuts: return "square.2.layers.3d"
        case .fallbacks: return "arrow.turn.down.right"
        case .ai: return "sparkles"
        case .quickActions: return "wand.and.sparkles"
        case .dictation: return "waveform"
        case .fileSearch: return "doc.text.magnifyingglass"
        case .notes: return "text.page"
        case .snippets: return "curlybraces"
        case .navigation: return "arrow.left.arrow.right"
        case .windowManagement: return "macwindow"
        case .clipboard: return "doc.on.clipboard"
        case .emoji: return "face.smiling"
        case .calendar: return "calendar"
        case .extensions: return "puzzlepiece.extension"
        case .permissions: return "lock.shield"
        case .backup: return "arrow.up.arrow.down.circle"
        case .about: return "info.circle"
        }
    }
}

/// 声明顺序即显示顺序；名称不用 `Section`，以免遮蔽 SwiftUI 的 `Section`。
enum SettingsSection: CaseIterable, Identifiable {
    case general, launcher, features, advanced
    /// 参见 `SettingsTab.id`：两个类型不同，因此两个 id 命名空间不会冲突。
    var id: Self { self }

    /// 本地化键，供设置界面按当前语言取分区名。
    var l10nKey: SettingsKey {
        switch self {
        case .general: return .sectionGeneral
        case .launcher: return .sectionLauncher
        case .features: return .sectionFeatures
        case .advanced: return .sectionAdvanced
        }
    }

    /// 按当前语言显示的分区名。
    func localizedTitle(_ language: AppLanguage) -> String {
        L10n.string(l10nKey, language: language)
    }

    /// 侧边栏分组中显示的名称（英文，供检索索引使用）。
    var title: String {
        switch self {
        case .general: return "General"
        case .launcher: return "Launcher"
        case .features: return "Features"
        case .advanced: return "Advanced"
        }
    }

    /// 该分区按顺序包含的设置页。
    var tabs: [SettingsTab] {
        switch self {
        case .general: return [.general, .permissions]
        case .launcher:
            return [
                .applications, .systemSettings, .systemActions, .commands, .quicklinks,
                .appleShortcuts, .fallbacks
            ]
        case .features:
            // 日常工具在前；AI 与扩展是需要主动开启的附加功能。
            return [
                .clipboard, .snippets, .fileSearch, .windowManagement, .navigation, .notes,
                .calendar, .emoji, .dictation, .ai, .quickActions, .extensions
            ]
        case .advanced: return [.backup, .about]
        }
    }
}
