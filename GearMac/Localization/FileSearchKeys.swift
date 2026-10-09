// 文件职责：「搜索文件」（FileSearch）功能的本地化键与中英词表。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 文件搜索屏幕、列表、预览、设置与协调器的文案键。
enum FileSearchKey: String, LocalizableKey {
    // 屏幕主操作
    case primaryOpenFile = "fileSearch.primary.openFile"
    case primaryOpenFolder = "fileSearch.primary.openFolder"

    // 状态与空结果
    case unavailable = "fileSearch.unavailable"
    case listRecentlyUsed = "fileSearch.list.recentlyUsed"
    case listResults = "fileSearch.list.results"
    case emptyPrompt = "fileSearch.empty.prompt"

    // 右键菜单
    case menuOpenFile = "fileSearch.menu.openFile"
    case menuOpenFolder = "fileSearch.menu.openFolder"
    case menuShowInFinder = "fileSearch.menu.showInFinder"
    case menuQuickLook = "fileSearch.menu.quickLook"
    case menuShare = "fileSearch.menu.share"
    case menuCopyFile = "fileSearch.menu.copyFile"
    case menuCopyName = "fileSearch.menu.copyName"
    case menuCopyPath = "fileSearch.menu.copyPath"
    case menuPasteFile = "fileSearch.menu.pasteFile"
    case menuPasteFileTo = "fileSearch.menu.pasteFileTo"
    case menuMoveToTrash = "fileSearch.menu.moveToTrash"

    // 预览信息区
    case previewInformation = "fileSearch.preview.information"
    case infoName = "fileSearch.info.name"
    case infoWhere = "fileSearch.info.where"
    case infoType = "fileSearch.info.type"
    case infoFolder = "fileSearch.info.folder"
    case infoFile = "fileSearch.info.file"
    case infoSize = "fileSearch.info.size"
    case infoCreated = "fileSearch.info.created"
    case infoModified = "fileSearch.info.modified"

    // Quick Look 浮层
    case quickLookClose = "fileSearch.quickLook.close"

    // 提示与通知
    case noticeOpenFailed = "fileSearch.notice.openFailed"
    case messageCopiedPath = "fileSearch.message.copiedPath"
    case messageCopiedName = "fileSearch.message.copiedName"
    case messageCopiedFile = "fileSearch.message.copiedFile"
    case messageMovedToTrash = "fileSearch.message.movedToTrash"
    case noticeTrashFailed = "fileSearch.notice.trashFailed"

    // 设置页
    case settingsToggleTitle = "fileSearch.settings.toggleTitle"
    case settingsToggleSubtitle = "fileSearch.settings.toggleSubtitle"
    case settingsAddButton = "fileSearch.settings.addButton"
    case settingsAddHelp = "fileSearch.settings.addHelp"
    case settingsRestoreDefaults = "fileSearch.settings.restoreDefaults"
    case settingsScopesFooter = "fileSearch.settings.scopesFooter"
    case settingsPanelPrompt = "fileSearch.settings.panelPrompt"
    case settingsPanelMessage = "fileSearch.settings.panelMessage"
    case settingsAddPattern = "fileSearch.settings.addPattern"
    case settingsIgnoreFooter = "fileSearch.settings.ignoreFooter"
    case accessibilityRemovePattern = "fileSearch.accessibility.removePattern"

    // 类型筛选器
    case filterAll = "fileSearch.filter.all"
    case filterFolders = "fileSearch.filter.folders"
    case filterDocuments = "fileSearch.filter.documents"
    case filterImages = "fileSearch.filter.images"
    case filterAudio = "fileSearch.filter.audio"
    case filterVideo = "fileSearch.filter.video"
    case filterArchives = "fileSearch.filter.archives"

    // 筛选器空结果
    case emptyAll = "fileSearch.empty.all"
    case emptyFolders = "fileSearch.empty.folders"
    case emptyDocuments = "fileSearch.empty.documents"
    case emptyImages = "fileSearch.empty.images"
    case emptyAudio = "fileSearch.empty.audio"
    case emptyVideo = "fileSearch.empty.videos"
    case emptyArchives = "fileSearch.empty.archives"

    static let table: [String: L10nEntry] = [
        FileSearchKey.primaryOpenFile.rawValue: L10nEntry("Open File", "打开文件"),
        FileSearchKey.primaryOpenFolder.rawValue: L10nEntry("Open Folder", "打开文件夹"),

        FileSearchKey.unavailable.rawValue: L10nEntry(
            "File search is unavailable", "文件搜索不可用"),
        FileSearchKey.listRecentlyUsed.rawValue: L10nEntry("Recently Used", "最近使用"),
        FileSearchKey.listResults.rawValue: L10nEntry("Results", "结果"),
        FileSearchKey.emptyPrompt.rawValue: L10nEntry(
            "Type to search files and folders", "输入以搜索文件和文件夹"),

        FileSearchKey.menuOpenFile.rawValue: L10nEntry("Open File", "打开文件"),
        FileSearchKey.menuOpenFolder.rawValue: L10nEntry("Open Folder", "打开文件夹"),
        FileSearchKey.menuShowInFinder.rawValue: L10nEntry("Show in Finder", "在访达中显示"),
        FileSearchKey.menuQuickLook.rawValue: L10nEntry("Quick Look", "快速查看"),
        FileSearchKey.menuShare.rawValue: L10nEntry("Share…", "共享…"),
        FileSearchKey.menuCopyFile.rawValue: L10nEntry("Copy File", "复制文件"),
        FileSearchKey.menuCopyName.rawValue: L10nEntry("Copy Name", "复制名称"),
        FileSearchKey.menuCopyPath.rawValue: L10nEntry("Copy Path", "复制路径"),
        FileSearchKey.menuPasteFile.rawValue: L10nEntry("Paste File", "粘贴文件"),
        FileSearchKey.menuPasteFileTo.rawValue: L10nEntry(
            "Paste File to %@", "粘贴文件到 %@"),
        FileSearchKey.menuMoveToTrash.rawValue: L10nEntry("Move to Trash", "移入废纸篓"),

        FileSearchKey.previewInformation.rawValue: L10nEntry("Information", "信息"),
        FileSearchKey.infoName.rawValue: L10nEntry("Name", "名称"),
        FileSearchKey.infoWhere.rawValue: L10nEntry("Where", "位置"),
        FileSearchKey.infoType.rawValue: L10nEntry("Type", "类型"),
        FileSearchKey.infoFolder.rawValue: L10nEntry("Folder", "文件夹"),
        FileSearchKey.infoFile.rawValue: L10nEntry("File", "文件"),
        FileSearchKey.infoSize.rawValue: L10nEntry("Size", "大小"),
        FileSearchKey.infoCreated.rawValue: L10nEntry("Created", "创建时间"),
        FileSearchKey.infoModified.rawValue: L10nEntry("Modified", "修改时间"),

        FileSearchKey.quickLookClose.rawValue: L10nEntry("Close", "关闭"),

        FileSearchKey.noticeOpenFailed.rawValue: L10nEntry(
            "Couldn’t Open %@", "无法打开 %@"),
        FileSearchKey.messageCopiedPath.rawValue: L10nEntry("Copied path", "已复制路径"),
        FileSearchKey.messageCopiedName.rawValue: L10nEntry("Copied name", "已复制名称"),
        FileSearchKey.messageCopiedFile.rawValue: L10nEntry("Copied file", "已复制文件"),
        FileSearchKey.messageMovedToTrash.rawValue: L10nEntry("Moved to Trash", "已移入废纸篓"),
        FileSearchKey.noticeTrashFailed.rawValue: L10nEntry(
            "Couldn’t Move %@ to Trash", "无法将 %@ 移入废纸篓"),

        FileSearchKey.settingsToggleTitle.rawValue: L10nEntry(
            "Enable File Search", "启用文件搜索"),
        FileSearchKey.settingsToggleSubtitle.rawValue: L10nEntry(
            "Uses the Spotlight index, only when you search.", "仅在搜索时使用 Spotlight 索引。"),
        FileSearchKey.settingsAddButton.rawValue: L10nEntry("Add…", "添加…"),
        FileSearchKey.settingsAddHelp.rawValue: L10nEntry(
            "Add a folder to search.", "添加要搜索的文件夹。"),
        FileSearchKey.settingsRestoreDefaults.rawValue: L10nEntry("Restore Defaults", "恢复默认"),
        FileSearchKey.settingsScopesFooter.rawValue: L10nEntry(
            "Home covers its visible folders and cloud drives, never Library.",
            "主目录覆盖其可见文件夹与云盘，不含资源库。"),
        FileSearchKey.settingsPanelPrompt.rawValue: L10nEntry("Add", "添加"),
        FileSearchKey.settingsPanelMessage.rawValue: L10nEntry(
            "Choose folders to include when searching for files.",
            "选择搜索文件时要包含的文件夹。"),
        FileSearchKey.settingsAddPattern.rawValue: L10nEntry("Add pattern…", "添加模式…"),
        FileSearchKey.settingsIgnoreFooter.rawValue: L10nEntry(
            "No slash matches a name, like *.tmp. A slash matches the path, like **/[Cc]ache/**.",
            "不含斜杠时匹配文件名，如 *.tmp；含斜杠时匹配路径，如 **/[Cc]ache/**。"),
        FileSearchKey.accessibilityRemovePattern.rawValue: L10nEntry("Remove %@", "移除 %@"),

        FileSearchKey.filterAll.rawValue: L10nEntry("All Types", "全部类型"),
        FileSearchKey.filterFolders.rawValue: L10nEntry("Folders", "文件夹"),
        FileSearchKey.filterDocuments.rawValue: L10nEntry("Documents", "文档"),
        FileSearchKey.filterImages.rawValue: L10nEntry("Images", "图片"),
        FileSearchKey.filterAudio.rawValue: L10nEntry("Audio", "音频"),
        FileSearchKey.filterVideo.rawValue: L10nEntry("Videos", "视频"),
        FileSearchKey.filterArchives.rawValue: L10nEntry("Archives", "压缩包"),

        FileSearchKey.emptyAll.rawValue: L10nEntry("No files found", "未找到文件"),
        FileSearchKey.emptyFolders.rawValue: L10nEntry("No folders found", "未找到文件夹"),
        FileSearchKey.emptyDocuments.rawValue: L10nEntry("No documents found", "未找到文档"),
        FileSearchKey.emptyImages.rawValue: L10nEntry("No images found", "未找到图片"),
        FileSearchKey.emptyAudio.rawValue: L10nEntry("No audio found", "未找到音频"),
        FileSearchKey.emptyVideo.rawValue: L10nEntry("No videos found", "未找到视频"),
        FileSearchKey.emptyArchives.rawValue: L10nEntry("No archives found", "未找到压缩包"),
    ]
}
