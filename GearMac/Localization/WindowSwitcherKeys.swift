// 文件职责：窗口切换器（WindowSwitcher）的本地化键与中英词表。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 窗口切换屏幕与协调器的文案键。
enum WindowSwitcherKey: String, LocalizableKey {
    // 主操作
    case primaryAction = "windowSwitcher.primaryAction"

    // 空结果
    case emptyNoWindows = "windowSwitcher.empty.noWindows"
    case emptyNoMatch = "windowSwitcher.empty.noMatch"

    // 行尾状态
    case minimized = "windowSwitcher.row.minimized"

    // 权限提示
    case permissionTitle = "windowSwitcher.permission.title"
    case permissionMessage = "windowSwitcher.permission.message"
    case permissionRecovery = "windowSwitcher.permission.recovery"

    // 目标窗口已关闭
    case goneTitle = "windowSwitcher.gone.title"
    case goneMessage = "windowSwitcher.gone.message"

    static let table: [String: L10nEntry] = [
        WindowSwitcherKey.primaryAction.rawValue: L10nEntry("Switch to Window", "切换到窗口"),

        WindowSwitcherKey.emptyNoWindows.rawValue: L10nEntry("No open windows", "没有打开的窗口"),
        WindowSwitcherKey.emptyNoMatch.rawValue: L10nEntry("No windows found", "未找到窗口"),

        WindowSwitcherKey.minimized.rawValue: L10nEntry("Minimized", "已最小化"),

        WindowSwitcherKey.permissionTitle.rawValue: L10nEntry(
            "GearMac Needs Accessibility Access", "GearMac 需要辅助功能权限"),
        WindowSwitcherKey.permissionMessage.rawValue: L10nEntry(
            "Switching windows reads and raises other apps' windows.",
            "窗口切换需要读取并前置其他应用的窗口。"),
        WindowSwitcherKey.permissionRecovery.rawValue: L10nEntry("Open Settings", "打开设置"),

        WindowSwitcherKey.goneTitle.rawValue: L10nEntry(
            "Couldn’t Switch to “%@”", "无法切换到“%@”"),
        WindowSwitcherKey.goneMessage.rawValue: L10nEntry(
            "It closed before the switch landed. Search again and retry.",
            "切换生效前该窗口已关闭，请重新搜索后再试。"),
    ]
}
