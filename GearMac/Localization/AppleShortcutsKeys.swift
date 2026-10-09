// 文件职责：AppleShortcuts（快捷指令）功能的本地化键与中英词表。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 快捷指令功能所有用户可见文案的键。
enum AppleShortcutsKey: String, LocalizableKey {
    case settingsEnableTitle = "appleShortcuts.settings.enable.title"
    case settingsEnableSubtitle = "appleShortcuts.settings.enable.subtitle"
    case searchPlaceholder = "appleShortcuts.searchPlaceholder"
    case openShortcuts = "appleShortcuts.openShortcuts"
    case defaultName = "appleShortcuts.defaultName"
    case errorRun = "appleShortcuts.error.run"

    static let table: [String: L10nEntry] = [
        AppleShortcutsKey.settingsEnableTitle.rawValue: L10nEntry(
            "Enable Apple Shortcuts", "启用快捷指令"),
        AppleShortcutsKey.settingsEnableSubtitle.rawValue: L10nEntry(
            "Run your shortcuts from the launcher.", "从启动器运行你的快捷指令。"),
        AppleShortcutsKey.searchPlaceholder.rawValue: L10nEntry("Search shortcuts…", "搜索快捷指令…"),
        AppleShortcutsKey.openShortcuts.rawValue: L10nEntry("Open Shortcuts", "打开快捷指令"),
        AppleShortcutsKey.defaultName.rawValue: L10nEntry("Shortcut", "快捷指令"),
        AppleShortcutsKey.errorRun.rawValue: L10nEntry("Couldn’t Run %@", "无法运行 %@")
    ]
}
