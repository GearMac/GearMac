// 文件职责：Quicklinks（快捷链接）功能的本地化键与中英词表。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 快捷链接功能所有用户可见文案的键。
enum QuicklinksKey: String, LocalizableKey {
    // 设置页：开关与存储提示
    case settingsEnableTitle = "quicklinks.settings.enable.title"
    case settingsEnableSubtitle = "quicklinks.settings.enable.subtitle"
    case storageNotice = "quicklinks.storageNotice"
    case searchPlaceholder = "quicklinks.searchPlaceholder"
    case emptyList = "quicklinks.emptyList"
    case noMatch = "quicklinks.noMatch"
    case addQuicklink = "quicklinks.add"

    // 设置页：全局行为
    case openNewWindow = "quicklinks.behaviour.openNewWindow"
    case openNewWindowDetail = "quicklinks.behaviour.openNewWindow.detail"
    case noSelection = "quicklinks.behaviour.noSelection"
    case noSelectionDetail = "quicklinks.behaviour.noSelection.detail"
    case confirmDelete = "quicklinks.behaviour.confirmDelete"
    case confirmDeleteDetail = "quicklinks.behaviour.confirmDelete.detail"

    // 设置页：导入导出
    case importAction = "quicklinks.transfer.import"
    case importTitle = "quicklinks.transfer.import.title"
    case importDetail = "quicklinks.transfer.import.detail"
    case exportAction = "quicklinks.transfer.export"
    case exportTitle = "quicklinks.transfer.export.title"
    case exportDetail = "quicklinks.transfer.export.detail"

    // 设置页：行
    case rowPinned = "quicklinks.row.pinned"
    case rowHidden = "quicklinks.row.hidden"
    case rowEnabled = "quicklinks.row.enabled"
    case rowEnableNamed = "quicklinks.row.enableNamed"

    // 通用动作
    case deleteTitle = "quicklinks.delete.title"
    case deleteMessage = "quicklinks.delete.message"
    case deleteAction = "quicklinks.delete.action"
    case editQuicklink = "quicklinks.edit"
    case editNamed = "quicklinks.editNamed"
    case deleteQuicklink = "quicklinks.deleteQuicklink"
    case deleteNamed = "quicklinks.deleteNamed"
    case showInFinder = "quicklinks.showInFinder"
    case cancel = "quicklinks.cancel"
    case save = "quicklinks.save"

    // 编辑器面板
    case editorAddTitle = "quicklinks.editor.addTitle"
    case editorEditTitle = "quicklinks.editor.editTitle"
    case editorName = "quicklinks.editor.name"
    case editorNamePlaceholder = "quicklinks.editor.namePlaceholder"
    case editorLink = "quicklinks.editor.link"
    case editorLinkPlaceholder = "quicklinks.editor.linkPlaceholder"
    case editorResolvedHint = "quicklinks.editor.resolvedHint"
    case editorInvalidLink = "quicklinks.editor.invalidLink"
    case editorShowInRootSearch = "quicklinks.editor.showInRootSearch"
    case editorShowInRootSearchDetail = "quicklinks.editor.showInRootSearch.detail"
    case editorPinToTop = "quicklinks.editor.pinToTop"
    case editorPinToTopDetail = "quicklinks.editor.pinToTop.detail"
    case editorInsert = "quicklinks.editor.insert"
    case editorArgument = "quicklinks.editor.argument"
    case editorNamedArgument = "quicklinks.editor.namedArgument"
    case editorClipboard = "quicklinks.editor.clipboard"
    case editorSelectedText = "quicklinks.editor.selectedText"
    case editorDate = "quicklinks.editor.date"
    case editorTime = "quicklinks.editor.time"
    case editorDateTime = "quicklinks.editor.dateTime"
    case editorCustomDateFormat = "quicklinks.editor.customDateFormat"
    case editorUUID = "quicklinks.editor.uuid"
    case editorIcon = "quicklinks.editor.icon"
    case editorAutomatic = "quicklinks.editor.automatic"
    case editorCustom = "quicklinks.editor.custom"
    case editorOpenWith = "quicklinks.editor.openWith"
    case editorDefaultApp = "quicklinks.editor.defaultApp"

    // 启动器列表与菜单
    case listPinned = "quicklinks.list.pinned"
    case listQuicklinks = "quicklinks.list.quicklinks"
    case listOpen = "quicklinks.list.open"
    case listEmpty = "quicklinks.list.empty"
    case listNoMatch = "quicklinks.list.noMatch"
    case actionOpenWithDefault = "quicklinks.action.openWithDefault"
    case actionDuplicate = "quicklinks.action.duplicate"
    case actionUnpin = "quicklinks.action.unpin"
    case actionPin = "quicklinks.action.pin"
    case actionHideFromRoot = "quicklinks.action.hideFromRoot"
    case actionShowInRoot = "quicklinks.action.showInRoot"

    // 信息区
    case infoName = "quicklinks.info.name"
    case infoLink = "quicklinks.info.link"
    case infoOpenWith = "quicklinks.info.openWith"
    case infoShortcut = "quicklinks.info.shortcut"
    case infoCreated = "quicklinks.info.created"
    case infoTitle = "quicklinks.info.title"

    // 选区回退选项
    case fallbackAsk = "quicklinks.fallback.ask"
    case fallbackClipboard = "quicklinks.fallback.clipboard"

    // 协调器与错误
    case errorOpenNamed = "quicklinks.error.openNamed"
    case errorAppMissing = "quicklinks.error.appMissing"
    case errorOpenWithDefault = "quicklinks.error.openWithDefault"
    case errorDeleteNamed = "quicklinks.error.deleteNamed"
    case errorSaveChange = "quicklinks.error.saveChange"
    case exportNothing = "quicklinks.export.nothing"
    case exportNothingMessage = "quicklinks.export.nothing.message"
    case exportDone = "quicklinks.export.done"
    case exportFailed = "quicklinks.export.failed"
    case importNothing = "quicklinks.import.nothing"
    case importNothingMessage = "quicklinks.import.nothing.message"
    case importSummary = "quicklinks.import.summary"
    case importSummarySkipped = "quicklinks.import.summarySkipped"
    case importDone = "quicklinks.import.done"
    case importFailed = "quicklinks.import.failed"

    // 模型错误
    case errorEmptyName = "quicklinks.error.emptyName"
    case errorEmptyLink = "quicklinks.error.emptyLink"
    case errorDuplicateName = "quicklinks.error.duplicateName"
    case errorUnresolvableLink = "quicklinks.error.unresolvableLink"
    case errorInvalidCharacter = "quicklinks.error.invalidCharacter"
    case errorStorageUnavailable = "quicklinks.error.storageUnavailable"

    // 打开失败
    case launcherUnresolvable = "quicklinks.launcher.unresolvable"
    case launcherMissingFile = "quicklinks.launcher.missingFile"
    case launcherMissingApp = "quicklinks.launcher.missingApp"
    case launcherOpenFailed = "quicklinks.launcher.openFailed"

    // 归档错误
    case archiveUnreadable = "quicklinks.archive.unreadable"
    case archiveEmpty = "quicklinks.archive.empty"

    static let table: [String: L10nEntry] = [
        QuicklinksKey.settingsEnableTitle.rawValue: L10nEntry("Enable quicklinks", "启用快捷链接"),
        QuicklinksKey.settingsEnableSubtitle.rawValue: L10nEntry(
            "Open saved links and searches from the launcher.", "从启动器打开已保存的链接和搜索。"),
        QuicklinksKey.storageNotice.rawValue: L10nEntry(
            "Changes can't be saved: the database couldn't be opened. Its file is untouched.",
            "无法保存更改：数据库无法打开。其文件未被改动。"),
        QuicklinksKey.searchPlaceholder.rawValue: L10nEntry("Search quicklinks…", "搜索快捷链接…"),
        QuicklinksKey.emptyList.rawValue: L10nEntry("No quicklinks yet.", "暂无快捷链接。"),
        QuicklinksKey.noMatch.rawValue: L10nEntry(
            "No quicklink matches “%@”.", "没有匹配“%@”的快捷链接。"),
        QuicklinksKey.addQuicklink.rawValue: L10nEntry("Add Quicklink", "添加快捷链接"),

        QuicklinksKey.openNewWindow.rawValue: L10nEntry("Open in a new window", "在新窗口中打开"),
        QuicklinksKey.openNewWindowDetail.rawValue: L10nEntry(
            "Where the app supports it.", "在应用支持的情况下。"),
        QuicklinksKey.noSelection.rawValue: L10nEntry(
            "When there's no selected text", "没有选中文本时"),
        QuicklinksKey.noSelectionDetail.rawValue: L10nEntry(
            "For links that use {selection}.", "适用于使用 {selection} 的链接。"),
        QuicklinksKey.confirmDelete.rawValue: L10nEntry("Confirm before deleting", "删除前确认"),
        QuicklinksKey.confirmDeleteDetail.rawValue: L10nEntry(
            "From the launcher's Actions menu.", "来自启动器的操作菜单。"),

        QuicklinksKey.importAction.rawValue: L10nEntry("Import…", "导入…"),
        QuicklinksKey.importTitle.rawValue: L10nEntry("Import quicklinks", "导入快捷链接"),
        QuicklinksKey.importDetail.rawValue: L10nEntry(
            "From a JSON file; duplicates are skipped.", "从 JSON 文件导入；重复项会被跳过。"),
        QuicklinksKey.exportAction.rawValue: L10nEntry("Export…", "导出…"),
        QuicklinksKey.exportTitle.rawValue: L10nEntry("Export quicklinks", "导出快捷链接"),
        QuicklinksKey.exportDetail.rawValue: L10nEntry("To a JSON file.", "导出为 JSON 文件。"),

        QuicklinksKey.rowPinned.rawValue: L10nEntry("Pinned to the top", "已置顶"),
        QuicklinksKey.rowHidden.rawValue: L10nEntry("Hidden from root search", "已从根搜索隐藏"),
        QuicklinksKey.rowEnabled.rawValue: L10nEntry("Enabled", "启用"),
        QuicklinksKey.rowEnableNamed.rawValue: L10nEntry("Enable %@", "启用 %@"),

        QuicklinksKey.deleteTitle.rawValue: L10nEntry("Delete “%@”?", "删除“%@”？"),
        QuicklinksKey.deleteMessage.rawValue: L10nEntry(
            "Its global shortcut and launcher references will also be removed.",
            "它的全局快捷键和启动器引用也会一并移除。"),
        QuicklinksKey.deleteAction.rawValue: L10nEntry("Delete", "删除"),
        QuicklinksKey.editQuicklink.rawValue: L10nEntry("Edit Quicklink", "编辑快捷链接"),
        QuicklinksKey.editNamed.rawValue: L10nEntry("Edit %@", "编辑 %@"),
        QuicklinksKey.deleteQuicklink.rawValue: L10nEntry("Delete Quicklink", "删除快捷链接"),
        QuicklinksKey.deleteNamed.rawValue: L10nEntry("Delete %@", "删除 %@"),
        QuicklinksKey.showInFinder.rawValue: L10nEntry("Show in Finder", "在访达中显示"),
        QuicklinksKey.cancel.rawValue: L10nEntry("Cancel", "取消"),
        QuicklinksKey.save.rawValue: L10nEntry("Save", "保存"),

        QuicklinksKey.editorAddTitle.rawValue: L10nEntry("Add Quicklink", "添加快捷链接"),
        QuicklinksKey.editorEditTitle.rawValue: L10nEntry("Edit Quicklink", "编辑快捷链接"),
        QuicklinksKey.editorName.rawValue: L10nEntry("Name", "名称"),
        QuicklinksKey.editorNamePlaceholder.rawValue: L10nEntry("Search GitHub", "搜索 GitHub"),
        QuicklinksKey.editorLink.rawValue: L10nEntry("Link", "链接"),
        QuicklinksKey.editorLinkPlaceholder.rawValue: L10nEntry(
            "https://github.com/search?q={argument}", "https://github.com/search?q={argument}"),
        QuicklinksKey.editorResolvedHint.rawValue: L10nEntry(
            "Resolved when you open it — placeholders are filled in first.",
            "打开时解析——先填充占位符。"),
        QuicklinksKey.editorInvalidLink.rawValue: L10nEntry(
            "This doesn't look like a URL, file path, or deeplink.",
            "这看起来不像 URL、文件路径或 deeplink。"),
        QuicklinksKey.editorShowInRootSearch.rawValue: L10nEntry(
            "Show in root search", "在根搜索中显示"),
        QuicklinksKey.editorShowInRootSearchDetail.rawValue: L10nEntry(
            "List this quicklink alongside apps and commands.", "在应用和命令旁边列出此快捷链接。"),
        QuicklinksKey.editorPinToTop.rawValue: L10nEntry("Pin to top", "置顶"),
        QuicklinksKey.editorPinToTopDetail.rawValue: L10nEntry(
            "Keep it above the other quicklinks.", "让它保持在其他快捷链接之上。"),
        QuicklinksKey.editorInsert.rawValue: L10nEntry("Insert…", "插入…"),
        QuicklinksKey.editorArgument.rawValue: L10nEntry("Argument", "参数"),
        QuicklinksKey.editorNamedArgument.rawValue: L10nEntry("Named Argument", "命名参数"),
        QuicklinksKey.editorClipboard.rawValue: L10nEntry("Clipboard", "剪贴板"),
        QuicklinksKey.editorSelectedText.rawValue: L10nEntry("Selected Text", "选中文本"),
        QuicklinksKey.editorDate.rawValue: L10nEntry("Date", "日期"),
        QuicklinksKey.editorTime.rawValue: L10nEntry("Time", "时间"),
        QuicklinksKey.editorDateTime.rawValue: L10nEntry("Date & Time", "日期与时间"),
        QuicklinksKey.editorCustomDateFormat.rawValue: L10nEntry(
            "Custom Date Format", "自定义日期格式"),
        QuicklinksKey.editorUUID.rawValue: L10nEntry("UUID", "UUID"),
        QuicklinksKey.editorIcon.rawValue: L10nEntry("Icon", "图标"),
        QuicklinksKey.editorAutomatic.rawValue: L10nEntry("Automatic", "自动"),
        QuicklinksKey.editorCustom.rawValue: L10nEntry("Custom", "自定义"),
        QuicklinksKey.editorOpenWith.rawValue: L10nEntry("Open With", "打开方式"),
        QuicklinksKey.editorDefaultApp.rawValue: L10nEntry("Default app", "默认应用"),

        QuicklinksKey.listPinned.rawValue: L10nEntry("Pinned", "已置顶"),
        QuicklinksKey.listQuicklinks.rawValue: L10nEntry("Quicklinks", "快捷链接"),
        QuicklinksKey.listOpen.rawValue: L10nEntry("Open Quicklink", "打开快捷链接"),
        QuicklinksKey.listEmpty.rawValue: L10nEntry("No quicklinks yet", "暂无快捷链接"),
        QuicklinksKey.listNoMatch.rawValue: L10nEntry("No matching quicklinks", "没有匹配的快捷链接"),
        QuicklinksKey.actionOpenWithDefault.rawValue: L10nEntry(
            "Open With Default App", "用默认应用打开"),
        QuicklinksKey.actionDuplicate.rawValue: L10nEntry("Duplicate Quicklink", "复制快捷链接"),
        QuicklinksKey.actionUnpin.rawValue: L10nEntry("Unpin Quicklink", "取消置顶"),
        QuicklinksKey.actionPin.rawValue: L10nEntry("Pin Quicklink", "置顶快捷链接"),
        QuicklinksKey.actionHideFromRoot.rawValue: L10nEntry(
            "Hide from Root Search", "从根搜索隐藏"),
        QuicklinksKey.actionShowInRoot.rawValue: L10nEntry("Show in Root Search", "在根搜索中显示"),

        QuicklinksKey.infoName.rawValue: L10nEntry("Name", "名称"),
        QuicklinksKey.infoLink.rawValue: L10nEntry("Link", "链接"),
        QuicklinksKey.infoOpenWith.rawValue: L10nEntry("Open With", "打开方式"),
        QuicklinksKey.infoShortcut.rawValue: L10nEntry("Shortcut", "快捷键"),
        QuicklinksKey.infoCreated.rawValue: L10nEntry("Created", "创建时间"),
        QuicklinksKey.infoTitle.rawValue: L10nEntry("Information", "信息"),

        QuicklinksKey.fallbackAsk.rawValue: L10nEntry("Ask for it", "询问"),
        QuicklinksKey.fallbackClipboard.rawValue: L10nEntry("Use the clipboard", "使用剪贴板"),

        QuicklinksKey.errorOpenNamed.rawValue: L10nEntry("Couldn’t Open %@", "无法打开 %@"),
        QuicklinksKey.errorAppMissing.rawValue: L10nEntry(
            "%@ isn’t installed any more.", "%@ 已不再安装。"),
        QuicklinksKey.errorOpenWithDefault.rawValue: L10nEntry(
            "Open with Default", "用默认应用打开"),
        QuicklinksKey.errorDeleteNamed.rawValue: L10nEntry(
            "Couldn’t Delete “%@”", "无法删除“%@”"),
        QuicklinksKey.errorSaveChange.rawValue: L10nEntry(
            "Couldn’t Save the Change", "无法保存更改"),
        QuicklinksKey.exportNothing.rawValue: L10nEntry("Nothing to Export", "无可导出内容"),
        QuicklinksKey.exportNothingMessage.rawValue: L10nEntry(
            "You haven’t created any quicklinks yet.", "你还没有创建任何快捷链接。"),
        QuicklinksKey.exportDone.rawValue: L10nEntry(
            "Exported %d Quicklinks", "已导出 %d 个快捷链接"),
        QuicklinksKey.exportFailed.rawValue: L10nEntry("Export Failed", "导出失败"),
        QuicklinksKey.importNothing.rawValue: L10nEntry("Nothing to Import", "无可导入内容"),
        QuicklinksKey.importNothingMessage.rawValue: L10nEntry(
            "Every quicklink in this file is already in your library.",
            "此文件中的每个快捷链接都已在你的库中。"),
        QuicklinksKey.importSummary.rawValue: L10nEntry(
            "Imported %d quicklinks.", "已导入 %d 个快捷链接。"),
        QuicklinksKey.importSummarySkipped.rawValue: L10nEntry(
            "Imported %d quicklinks. Skipped %d already in your library.",
            "已导入 %d 个快捷链接，跳过 %d 个已在库中的。"),
        QuicklinksKey.importDone.rawValue: L10nEntry("Quicklinks Imported", "快捷链接已导入"),
        QuicklinksKey.importFailed.rawValue: L10nEntry("Import Failed", "导入失败"),

        QuicklinksKey.errorEmptyName.rawValue: L10nEntry(
            "Enter a name for the quicklink.", "请输入快捷链接的名称。"),
        QuicklinksKey.errorEmptyLink.rawValue: L10nEntry("Enter a link to open.", "请输入要打开的链接。"),
        QuicklinksKey.errorDuplicateName.rawValue: L10nEntry(
            "A quicklink with this name already exists.", "已存在同名的快捷链接。"),
        QuicklinksKey.errorUnresolvableLink.rawValue: L10nEntry(
            "This doesn't look like a URL, file path, or deeplink.",
            "这看起来不像 URL、文件路径或 deeplink。"),
        QuicklinksKey.errorInvalidCharacter.rawValue: L10nEntry(
            "Names and links cannot contain null characters.", "名称和链接不能包含空字符。"),
        QuicklinksKey.errorStorageUnavailable.rawValue: L10nEntry(
            "The quicklinks database could not be opened, so changes can't be saved.",
            "快捷链接数据库无法打开，因此无法保存更改。"),

        QuicklinksKey.launcherUnresolvable.rawValue: L10nEntry(
            "“%@” isn't a URL, file path, or deeplink.", "“%@”不是 URL、文件路径或 deeplink。"),
        QuicklinksKey.launcherMissingFile.rawValue: L10nEntry(
            "Nothing exists at %@ any more.", "%@ 处已不存在任何内容。"),
        QuicklinksKey.launcherMissingApp.rawValue: L10nEntry(
            "The app this quicklink opens with isn't installed any more.",
            "此快捷链接所使用的打开应用已不再安装。"),
        QuicklinksKey.launcherOpenFailed.rawValue: L10nEntry(
            "macOS could not open %@.\n\n%@", "macOS 无法打开 %@。\n\n%@"),

        QuicklinksKey.archiveUnreadable.rawValue: L10nEntry(
            "This file isn't a GearMac quicklinks export.", "此文件不是 GearMac 快捷链接导出文件。"),
        QuicklinksKey.archiveEmpty.rawValue: L10nEntry(
            "This file contains no quicklinks.", "此文件不包含任何快捷链接。")
    ]
}
