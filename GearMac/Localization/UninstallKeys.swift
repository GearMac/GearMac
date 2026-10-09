// 文件职责：卸载（Uninstall）功能的本地化键与中英词表。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 卸载屏幕、列表、协调器与模型的文案键。
enum UninstallKey: String, LocalizableKey {
    // 屏幕主操作与空结果
    case primaryAction = "uninstall.primaryAction"
    case emptyNothingLeft = "uninstall.empty.nothingLeft"
    case emptyNoMatch = "uninstall.empty.noMatch"
    case summary = "uninstall.summary"

    // 操作菜单
    case menuUninstall = "uninstall.menu.uninstall"
    case menuSelectFile = "uninstall.menu.selectFile"
    case menuUnselectFile = "uninstall.menu.unselectFile"
    case menuCopyPath = "uninstall.menu.copyPath"
    case menuShowInFinder = "uninstall.menu.showInFinder"
    case menuShowInfoInFinder = "uninstall.menu.showInfoInFinder"

    // 证据标签
    case evidenceMatchedByName = "uninstall.evidence.matchedByName"
    case evidenceCommandLineTool = "uninstall.evidence.commandLineTool"

    // 保护原因
    case protectionSystemProtected = "uninstall.protection.systemProtected"
    case protectionUserLocked = "uninstall.protection.userLocked"
    case protectionNotOwned = "uninstall.protection.notOwned"
    case protectionNeedsFullDiskAccess = "uninstall.protection.needsFullDiskAccess"
    case protectionParentNotWritable = "uninstall.protection.parentNotWritable"
    case protectionMissing = "uninstall.protection.missing"

    // 扫描失败
    case scanRefused = "uninstall.scan.refused"
    case scanFailed = "uninstall.scan.failed"

    // 确认弹窗
    case confirmTitle = "uninstall.confirm.title"
    case confirmItemOne = "uninstall.confirm.itemOne"
    case confirmItemMany = "uninstall.confirm.itemMany"
    case confirmMessage = "uninstall.confirm.message"
    case confirmQuitSuffix = "uninstall.confirm.quitSuffix"
    case confirmMoveToTrash = "uninstall.confirm.moveToTrash"

    // 消息与结果
    case copiedPath = "uninstall.message.copiedPath"
    case getInfoFailedTitle = "uninstall.getInfoFailed.title"
    case getInfoFailedMessage = "uninstall.getInfoFailed.message"
    case movedToTrash = "uninstall.message.movedToTrash"
    case reportSomeFailed = "uninstall.report.someFailed"
    case reportNoneMoved = "uninstall.report.noneMoved"
    case reportAndMore = "uninstall.report.andMore"

    static let table: [String: L10nEntry] = [
        UninstallKey.primaryAction.rawValue: L10nEntry("Uninstall Application", "卸载应用"),
        UninstallKey.emptyNothingLeft.rawValue: L10nEntry(
            "Nothing left to remove", "没有可移除的条目"),
        UninstallKey.emptyNoMatch.rawValue: L10nEntry("No matching files", "没有匹配的文件"),
        UninstallKey.summary.rawValue: L10nEntry(
            "%1$d of %2$d files selected · %3$@", "已选择 %1$d/%2$d 个文件 · %3$@"),

        UninstallKey.menuUninstall.rawValue: L10nEntry("Uninstall Application", "卸载应用"),
        UninstallKey.menuSelectFile.rawValue: L10nEntry("Select File", "选择文件"),
        UninstallKey.menuUnselectFile.rawValue: L10nEntry("Unselect File", "取消选择文件"),
        UninstallKey.menuCopyPath.rawValue: L10nEntry("Copy Path", "复制路径"),
        UninstallKey.menuShowInFinder.rawValue: L10nEntry("Show in Finder", "在访达中显示"),
        UninstallKey.menuShowInfoInFinder.rawValue: L10nEntry(
            "Show Info in Finder", "在访达中显示简介"),

        UninstallKey.evidenceMatchedByName.rawValue: L10nEntry("matched by name", "按名称匹配"),
        UninstallKey.evidenceCommandLineTool.rawValue: L10nEntry(
            "command-line tool", "命令行工具"),

        UninstallKey.protectionSystemProtected.rawValue: L10nEntry(
            "Part of macOS and protected by the system.", "属于 macOS 的一部分，受系统保护。"),
        UninstallKey.protectionUserLocked.rawValue: L10nEntry(
            "Locked in Finder. Unlock it in Get Info, then try again.",
            "已在访达中锁定。请在“显示简介”中解锁后重试。"),
        UninstallKey.protectionNotOwned.rawValue: L10nEntry(
            "Owned by another user, in a folder that only lets owners remove things.",
            "属主是其他用户，所在文件夹仅允许属主移除其中的条目。"),
        UninstallKey.protectionNeedsFullDiskAccess.rawValue: L10nEntry(
            "Needs Full Disk Access, which GearMac doesn’t request. "
                + "Grant it in System Settings › Privacy & Security to include this item.",
            "需要“完全磁盘访问权限”，而 GearMac 不会申请该权限。"
                + "请在“系统设置 › 隐私与安全性”中授予，以便包含此条目。"),
        UninstallKey.protectionParentNotWritable.rawValue: L10nEntry(
            "Its enclosing folder isn’t writable by you, and GearMac never asks for an "
                + "administrator password.",
            "所在文件夹对你不可写，而 GearMac 从不索取管理员密码。"),
        UninstallKey.protectionMissing.rawValue: L10nEntry("No longer on disk.", "磁盘上已不存在。"),

        UninstallKey.scanRefused.rawValue: L10nEntry(
            "GearMac can’t uninstall this app.", "GearMac 无法卸载此应用。"),
        UninstallKey.scanFailed.rawValue: L10nEntry(
            "Uninstall couldn’t start: %@", "无法开始卸载：%@"),

        UninstallKey.confirmTitle.rawValue: L10nEntry("Uninstall “%@”?", "卸载“%@”？"),
        UninstallKey.confirmItemOne.rawValue: L10nEntry("1 item", "1 个条目"),
        UninstallKey.confirmItemMany.rawValue: L10nEntry("%d items", "%d 个条目"),
        UninstallKey.confirmMessage.rawValue: L10nEntry(
            "%1$@ (%2$@) will be moved to the Trash, where you can put them back.",
            "%1$@（%2$@）将被移入废纸篓，你之后可以将其放回。"),
        UninstallKey.confirmQuitSuffix.rawValue: L10nEntry(
            " %@ will quit first.", " %@ 将先退出。"),
        UninstallKey.confirmMoveToTrash.rawValue: L10nEntry("Move to Trash", "移入废纸篓"),

        UninstallKey.copiedPath.rawValue: L10nEntry("Copied path", "已复制路径"),
        UninstallKey.getInfoFailedTitle.rawValue: L10nEntry(
            "Couldn’t Open Get Info", "无法打开“显示简介”"),
        UninstallKey.getInfoFailedMessage.rawValue: L10nEntry(
            "Allow GearMac to control Finder in System Settings › Privacy & Security "
                + "› Automation, then try again.",
            "请在“系统设置 › 隐私与安全性 › 自动化”中允许 GearMac 控制“访达”，然后重试。"),
        UninstallKey.movedToTrash.rawValue: L10nEntry(
            "Moved %1$@ to the Trash · %2$@", "已将 %1$@ 移入废纸篓 · %2$@"),
        UninstallKey.reportSomeFailed.rawValue: L10nEntry(
            "Some Items Weren’t Moved", "部分条目未能移动"),
        UninstallKey.reportNoneMoved.rawValue: L10nEntry(
            "Nothing Was Moved", "没有条目被移动"),
        UninstallKey.reportAndMore.rawValue: L10nEntry("\nand %d more.", "\n以及另外 %d 个。"),
    ]
}
