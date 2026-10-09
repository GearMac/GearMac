// 文件职责：定义 Raycast 导出文件（`.rayconfig`）的可选项与解析结果模型。
// 分层：Model；只描述可导入的类别与数据，不执行实际写入。
import Foundation

/// Raycast 导出中可独立导入的类别，用户可从中挑选子集。
struct RaycastImportOptions: OptionSet, Sendable {
    let rawValue: Int
    static let shortcuts = RaycastImportOptions(rawValue: 1 << 0)
    static let favorites = RaycastImportOptions(rawValue: 1 << 1)
    static let emojiSkinTone = RaycastImportOptions(rawValue: 1 << 2)
    static let launchAtLogin = RaycastImportOptions(rawValue: 1 << 3)
    static let menuBarVisibility = RaycastImportOptions(rawValue: 1 << 4)
    static let clipboardHistory = RaycastImportOptions(rawValue: 1 << 5)
    static let popToRoot = RaycastImportOptions(rawValue: 1 << 6)
    static let compactMode = RaycastImportOptions(rawValue: 1 << 7)
    static let snippets = RaycastImportOptions(rawValue: 1 << 8)
    static let aliases = RaycastImportOptions(rawValue: 1 << 9)
    static let quicklinks = RaycastImportOptions(rawValue: 1 << 10)
    /// 全部可导入类别。
    static let all: RaycastImportOptions = [
        .shortcuts, .favorites, .emojiSkinTone, .launchAtLogin, .menuBarVisibility, .clipboardHistory,
        .popToRoot, .compactMode, .snippets, .aliases, .quicklinks
    ]
}

/// `.rayconfig` 解析后、进入应用之前的结果模型。参见 docs/features/raycast-import.md。
enum RaycastImport {
    /// 一次导入所得到的数据集合。
    struct Result {
        var backup: SettingsBackup
        var clipboard: [ClipboardItem]
        var snippets: [Snippet]
        var quicklinks: [Quicklink]
        /// 文件已不存在的图片剪贴板记录数量，上报以便 UI 提示。
        var missingImages: Int

        /// 裁剪为所选类别；由于 `apply()` 逐字段应用，直接丢弃即可。
        func selecting(_ options: RaycastImportOptions) -> Result {
            var trimmed = SettingsBackup()
            if options.contains(.shortcuts) { trimmed.hotkeys = backup.hotkeys }
            if options.contains(.favorites) { trimmed.favoriteApps = backup.favoriteApps }
            if options.contains(.aliases) { trimmed.launcherAliases = backup.launcherAliases }

            var settings = SettingsBackup.SettingsData()
            var hasSettings = false
            if options.contains(.emojiSkinTone), let tone = backup.settings?.emojiSkinTone {
                settings.emojiSkinTone = tone
                hasSettings = true
            }
            if options.contains(.launchAtLogin), let launch = backup.settings?.launchAtLogin {
                settings.launchAtLogin = launch
                hasSettings = true
            }
            if options.contains(.menuBarVisibility), let show = backup.settings?.showInMenuBar {
                settings.showInMenuBar = show
                hasSettings = true
            }
            if options.contains(.popToRoot), let secs = backup.settings?.popToRootSeconds {
                settings.popToRootSeconds = secs
                hasSettings = true
            }
            if options.contains(.compactMode) {
                if let compact = backup.settings?.compactMode {
                    settings.compactMode = compact
                    hasSettings = true
                }
                if let showFavorites = backup.settings?.showFavoritesInCompactMode {
                    settings.showFavoritesInCompactMode = showFavorites
                    hasSettings = true
                }
            }
            if options.contains(.shortcuts) {
                if let shift = backup.settings?.hyperKeyIncludesShift {
                    settings.hyperKeyIncludesShift = shift
                    hasSettings = true
                }
                if let key = backup.settings?.hyperKey {
                    settings.hyperKey = key
                    hasSettings = true
                }
            }

            let keepClipboard = options.contains(.clipboardHistory)
            // 按应用排除列表属于剪贴板历史，而非整个设置。
            if keepClipboard, let disabled = backup.settings?.clipboardDisabledApps {
                settings.clipboardDisabledApps = disabled
                hasSettings = true
            }
            if hasSettings { trimmed.settings = settings }

            return Result(
                backup: trimmed,
                clipboard: keepClipboard ? clipboard : [],
                snippets: options.contains(.snippets) ? snippets : [],
                quicklinks: options.contains(.quicklinks) ? quicklinks : [],
                missingImages: keepClipboard ? missingImages : 0)
        }
    }
}
