// 文件职责：菜单栏入口（状态栏下拉与应用菜单）的本地化键与中英词表。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 菜单栏入口文案：状态栏下拉与应用菜单共用同一套入口名。
enum MenuBarKey: String, LocalizableKey {
    case openFormat = "menuBar.openFormat"
    case clipboardHistory = "menuBar.clipboardHistory"
    case checkForUpdates = "menuBar.checkForUpdates"
    case supportFormat = "menuBar.supportFormat"
    case settings = "menuBar.settings"
    case quitFormat = "menuBar.quitFormat"
    case aboutFormat = "menuBar.aboutFormat"
    case closeWindow = "menuBar.closeWindow"

    static let table: [String: L10nEntry] = [
        MenuBarKey.openFormat.rawValue: L10nEntry("Open %@", "打开 %@"),
        MenuBarKey.clipboardHistory.rawValue: L10nEntry("Clipboard History", "剪贴板历史"),
        MenuBarKey.checkForUpdates.rawValue: L10nEntry("Check for Updates…", "检查更新…"),
        MenuBarKey.supportFormat.rawValue: L10nEntry("Support %@…", "支持 %@…"),
        MenuBarKey.settings.rawValue: L10nEntry("Settings…", "设置…"),
        MenuBarKey.quitFormat.rawValue: L10nEntry("Quit %@", "退出 %@"),
        MenuBarKey.aboutFormat.rawValue: L10nEntry("About %@", "关于 %@"),
        MenuBarKey.closeWindow.rawValue: L10nEntry("Close Window", "关闭窗口")
    ]
}
