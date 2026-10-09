// 文件职责：菜单搜索（MenuSearch）的本地化键与中英词表。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 菜单搜索屏幕、列表与协调器的文案键。
enum MenuSearchKey: String, LocalizableKey {
    // 主操作
    case primaryAction = "menuSearch.primaryAction"

    // 空结果与状态
    case reading = "menuSearch.reading"
    case emptyNoItems = "menuSearch.empty.noItems"
    case excluded = "menuSearch.empty.excluded"
    case selfTarget = "menuSearch.empty.selfTarget"
    case menuLess = "menuSearch.empty.menuLess"
    case noApplication = "menuSearch.empty.noApplication"

    // 列表分组
    case results = "menuSearch.section.results"
    case sectionLabelOne = "menuSearch.section.labelOne"
    case sectionLabelMany = "menuSearch.section.labelMany"

    // 权限提示
    case permissionTitle = "menuSearch.permission.title"
    case permissionMessage = "menuSearch.permission.message"
    case permissionRecovery = "menuSearch.permission.recovery"

    // 目标应用已退出
    case goneTitle = "menuSearch.gone.title"
    case goneMessageApp = "menuSearch.gone.messageApp"
    case goneMessageGeneric = "menuSearch.gone.messageGeneric"

    // 菜单已变化、按下失败
    case pressFailedTitle = "menuSearch.pressFailed.title"
    case pressFailedMessage = "menuSearch.pressFailed.message"

    static let table: [String: L10nEntry] = [
        MenuSearchKey.primaryAction.rawValue: L10nEntry("Activate Menu Item", "激活菜单项"),

        MenuSearchKey.reading.rawValue: L10nEntry("Reading menu…", "正在读取菜单…"),
        MenuSearchKey.emptyNoItems.rawValue: L10nEntry(
            "No menu items found in %@", "在 %@ 中未找到菜单项"),
        MenuSearchKey.excluded.rawValue: L10nEntry(
            "Menu search is turned off for %@", "已对 %@ 关闭菜单搜索"),
        MenuSearchKey.selfTarget.rawValue: L10nEntry(
            "GearMac has no menu to search", "GearMac 没有可搜索的菜单"),
        MenuSearchKey.menuLess.rawValue: L10nEntry(
            "%@ has no menu bar to search", "%@ 没有可搜索的菜单栏"),
        MenuSearchKey.noApplication.rawValue: L10nEntry(
            "No application to search", "没有可搜索的应用"),

        MenuSearchKey.results.rawValue: L10nEntry("Results", "结果"),
        MenuSearchKey.sectionLabelOne.rawValue: L10nEntry("%@ (1 item)", "%@（1 项）"),
        MenuSearchKey.sectionLabelMany.rawValue: L10nEntry("%@ (%d items)", "%@（%d 项）"),

        MenuSearchKey.permissionTitle.rawValue: L10nEntry(
            "GearMac Needs Accessibility Access", "GearMac 需要辅助功能权限"),
        MenuSearchKey.permissionMessage.rawValue: L10nEntry(
            "Searching menus reads the front app's menu bar.",
            "菜单搜索需要读取最前应用的菜单栏。"),
        MenuSearchKey.permissionRecovery.rawValue: L10nEntry("Open Settings", "打开设置"),

        MenuSearchKey.goneTitle.rawValue: L10nEntry(
            "Couldn't Activate Menu Item", "无法激活菜单项"),
        MenuSearchKey.goneMessageApp.rawValue: L10nEntry(
            "%@ is no longer running.", "%@ 已不再运行。"),
        MenuSearchKey.goneMessageGeneric.rawValue: L10nEntry(
            "The application is no longer running.", "该应用已不再运行。"),

        MenuSearchKey.pressFailedTitle.rawValue: L10nEntry(
            "Couldn't Activate “%@”", "无法激活“%@”"),
        MenuSearchKey.pressFailedMessage.rawValue: L10nEntry(
            "Its menu changed before the press landed. Search again and retry.",
            "按下生效前菜单已变化，请重新搜索后再试。"),
    ]
}
