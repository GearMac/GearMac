// 文件职责：Snippets（代码片段）功能的本地化键与中英词表。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 代码片段功能所有用户可见文案的键。
enum SnippetsKey: String, LocalizableKey {
    // 设置页：启用与权限
    case settingsEnableTitle = "snippets.settings.enable.title"
    case settingsEnableSubtitle = "snippets.settings.enable.subtitle"
    case settingsGrantAccess = "snippets.settings.grantAccess"
    case settingsAccessTitle = "snippets.settings.access.title"
    case settingsAccessSubtitle = "snippets.settings.access.subtitle"

    // 设置页：片段库
    case settingsDeleteTitle = "snippets.settings.delete.title"
    case settingsDeleteMessage = "snippets.settings.delete.message"
    case settingsDeleteAction = "snippets.settings.deleteAction"
    case settingsLoading = "snippets.settings.loading"
    case settingsEmpty = "snippets.settings.empty"
    case settingsAdd = "snippets.settings.add"
    case settingsNewSnippet = "snippets.settings.newSnippet"
    case settingsUseDefault = "snippets.settings.useDefault"
    case settingsChoose = "snippets.settings.choose"
    case settingsOpenFolder = "snippets.settings.openFolder"
    case settingsOpenFolderHint = "snippets.settings.openFolder.hint"
    case settingsFolder = "snippets.settings.folder"

    // 设置页：提示区段
    case noticeLoadFailed = "snippets.notice.loadFailed"
    case noticeLoadRetryHint = "snippets.notice.loadRetryHint"
    case noticeIssuesRetryHint = "snippets.notice.issuesRetryHint"
    case noticeOperationFailed = "snippets.notice.operationFailed"
    case noticeRetry = "snippets.notice.retry"
    case issueTitleOne = "snippets.issue.title.one"
    case issueTitleMany = "snippets.issue.title.many"
    case issueMessage = "snippets.issue.message"
    case issuePlusMore = "snippets.issue.plusMore"

    // 设置页：行按钮
    case rowEdit = "snippets.row.edit"
    case rowEditNamed = "snippets.row.editNamed"
    case rowDelete = "snippets.row.delete"
    case rowDeleteNamed = "snippets.row.deleteNamed"

    // 编辑器面板
    case editorAddTitle = "snippets.editor.addTitle"
    case editorEditTitle = "snippets.editor.editTitle"
    case editorName = "snippets.editor.name"
    case editorNamePlaceholder = "snippets.editor.namePlaceholder"
    case editorNameHint = "snippets.editor.nameHint"
    case editorKeyword = "snippets.editor.keyword"
    case editorKeywordPlaceholder = "snippets.editor.keywordPlaceholder"
    case editorKeywordHint = "snippets.editor.keywordHint"
    case editorEnabled = "snippets.editor.enabled"
    case editorEnabledDetail = "snippets.editor.enabledDetail"
    case editorConfirm = "snippets.editor.confirm"
    case editorConfirmDetail = "snippets.editor.confirmDetail"
    case editorCancel = "snippets.editor.cancel"
    case editorSave = "snippets.editor.save"
    case editorTemplate = "snippets.editor.template"
    case editorTemplateAccessibility = "snippets.editor.template.accessibility"
    case editorTemplateHint = "snippets.editor.template.hint"
    case editorInsert = "snippets.editor.insert"
    case editorSectionText = "snippets.editor.section.text"
    case editorSectionDateTime = "snippets.editor.section.dateTime"
    case editorSectionArguments = "snippets.editor.section.arguments"
    case editorSectionSnippets = "snippets.editor.section.snippets"
    case editorInsertAccessibility = "snippets.editor.insert.accessibility"
    case editorFieldAccessibility = "snippets.editor.field.accessibility"

    // 信息区
    case infoName = "snippets.info.name"
    case infoKeyword = "snippets.info.keyword"
    case infoShortcut = "snippets.info.shortcut"
    case infoFile = "snippets.info.file"
    case infoCharacters = "snippets.info.characters"
    case infoTitle = "snippets.info.title"

    // 启动器与协调器
    case pasteSnippet = "snippets.pasteSnippet"
    case loading = "snippets.loading"
    case noMatching = "snippets.noMatching"
    case noSnippets = "snippets.noSnippets"
    case createSnippet = "snippets.createSnippet"
    case showInFinder = "snippets.showInFinder"
    case chooseFolderMessage = "snippets.chooseFolder.message"
    case enableConfirmTitle = "snippets.enable.confirmTitle"
    case enableConfirmMessage = "snippets.enable.confirmMessage"
    case enableConfirmAction = "snippets.enable.confirmAction"
    case clickTextField = "snippets.clickTextField"
    case inserted = "snippets.inserted"

    // 仓库错误
    case errorConflict = "snippets.error.conflict"
    case errorFileNotFound = "snippets.error.fileNotFound"
    case errorInvalidLocation = "snippets.error.invalidLocation"
    case errorAccessFailed = "snippets.error.accessFailed"

    static let table: [String: L10nEntry] = [
        SnippetsKey.settingsEnableTitle.rawValue: L10nEntry("Enable snippets", "启用代码片段"),
        SnippetsKey.settingsEnableSubtitle.rawValue: L10nEntry(
            "Expand templates from the launcher or by keyword.", "从启动器或通过关键字展开模板。"),
        SnippetsKey.settingsGrantAccess.rawValue: L10nEntry("Grant Access…", "授予访问权限…"),
        SnippetsKey.settingsAccessTitle.rawValue: L10nEntry(
            "Keyword expansion needs Accessibility access", "关键字展开需要辅助功能权限"),
        SnippetsKey.settingsAccessSubtitle.rawValue: L10nEntry(
            "Launcher search still works.", "启动器搜索仍可使用。"),

        SnippetsKey.settingsDeleteTitle.rawValue: L10nEntry(
            "Delete “%@”?", "删除“%@”？"),
        SnippetsKey.settingsDeleteMessage.rawValue: L10nEntry(
            "This removes %@ from your snippets folder.", "这会从代码片段文件夹中移除 %@。"),
        SnippetsKey.settingsDeleteAction.rawValue: L10nEntry("Delete", "删除"),
        SnippetsKey.settingsLoading.rawValue: L10nEntry("Loading snippets…", "正在加载代码片段…"),
        SnippetsKey.settingsEmpty.rawValue: L10nEntry("No snippets yet.", "暂无代码片段。"),
        SnippetsKey.settingsAdd.rawValue: L10nEntry("Add…", "添加…"),
        SnippetsKey.settingsNewSnippet.rawValue: L10nEntry("New Snippet", "新建代码片段"),
        SnippetsKey.settingsUseDefault.rawValue: L10nEntry("Use Default", "使用默认值"),
        SnippetsKey.settingsChoose.rawValue: L10nEntry("Choose…", "选取…"),
        SnippetsKey.settingsOpenFolder.rawValue: L10nEntry("Open Folder", "打开文件夹"),
        SnippetsKey.settingsOpenFolderHint.rawValue: L10nEntry(
            "Reveals the snippets folder in Finder.", "在访达中显示代码片段文件夹。"),
        SnippetsKey.settingsFolder.rawValue: L10nEntry("Snippets Folder", "代码片段文件夹"),

        SnippetsKey.noticeLoadFailed.rawValue: L10nEntry(
            "Couldn’t load the snippet library", "无法加载代码片段库"),
        SnippetsKey.noticeLoadRetryHint.rawValue: L10nEntry(
            "Tries to load the snippet library again.", "再次尝试加载代码片段库。"),
        SnippetsKey.noticeIssuesRetryHint.rawValue: L10nEntry(
            "Reloads snippet files after you fix them on disk.", "修复磁盘上的代码片段文件后重新加载。"),
        SnippetsKey.noticeOperationFailed.rawValue: L10nEntry(
            "The snippet operation failed", "代码片段操作失败"),
        SnippetsKey.noticeRetry.rawValue: L10nEntry("Retry", "重试"),
        SnippetsKey.issueTitleOne.rawValue: L10nEntry(
            "1 snippet file couldn’t be loaded", "1 个代码片段文件无法加载"),
        SnippetsKey.issueTitleMany.rawValue: L10nEntry(
            "%d snippet files couldn’t be loaded", "%d 个代码片段文件无法加载"),
        SnippetsKey.issueMessage.rawValue: L10nEntry("%@: %@", "%@：%@"),
        SnippetsKey.issuePlusMore.rawValue: L10nEntry(" Plus %d more.", "，另有 %d 个。"),

        SnippetsKey.rowEdit.rawValue: L10nEntry("Edit Snippet", "编辑代码片段"),
        SnippetsKey.rowEditNamed.rawValue: L10nEntry("Edit %@", "编辑 %@"),
        SnippetsKey.rowDelete.rawValue: L10nEntry("Delete Snippet", "删除代码片段"),
        SnippetsKey.rowDeleteNamed.rawValue: L10nEntry("Delete %@", "删除 %@"),

        SnippetsKey.editorAddTitle.rawValue: L10nEntry("Add Snippet", "新增代码片段"),
        SnippetsKey.editorEditTitle.rawValue: L10nEntry("Edit Snippet", "编辑代码片段"),
        SnippetsKey.editorName.rawValue: L10nEntry("Name", "名称"),
        SnippetsKey.editorNamePlaceholder.rawValue: L10nEntry("Email Sign-off", "邮件署名"),
        SnippetsKey.editorNameHint.rawValue: L10nEntry(
            "Required. Shown in the library and launcher.", "必填。显示在代码片段库和启动器中。"),
        SnippetsKey.editorKeyword.rawValue: L10nEntry("Keyword", "关键字"),
        SnippetsKey.editorKeywordPlaceholder.rawValue: L10nEntry(
            "Optional, for example !notes", "可选，例如 !notes"),
        SnippetsKey.editorKeywordHint.rawValue: L10nEntry(
            "Optional. Type this to expand the snippet.", "可选。输入它以展开代码片段。"),
        SnippetsKey.editorEnabled.rawValue: L10nEntry("Enabled", "启用"),
        SnippetsKey.editorEnabledDetail.rawValue: L10nEntry(
            "Disabled snippets cannot be expanded.", "已禁用的代码片段无法展开。"),
        SnippetsKey.editorConfirm.rawValue: L10nEntry("Show confirmation", "显示确认"),
        SnippetsKey.editorConfirmDetail.rawValue: L10nEntry(
            "Confirm on screen after this snippet is inserted.", "插入代码片段后在屏幕上确认。"),
        SnippetsKey.editorCancel.rawValue: L10nEntry("Cancel", "取消"),
        SnippetsKey.editorSave.rawValue: L10nEntry("Save", "保存"),
        SnippetsKey.editorTemplate.rawValue: L10nEntry("Template", "模板"),
        SnippetsKey.editorTemplateAccessibility.rawValue: L10nEntry("Snippet template", "代码片段模板"),
        SnippetsKey.editorTemplateHint.rawValue: L10nEntry(
            "Enter the text GearMac expands.", "输入 GearMac 展开的文本。"),
        SnippetsKey.editorInsert.rawValue: L10nEntry("Insert…", "插入…"),
        SnippetsKey.editorSectionText.rawValue: L10nEntry("Text", "文本"),
        SnippetsKey.editorSectionDateTime.rawValue: L10nEntry("Date & Time", "日期与时间"),
        SnippetsKey.editorSectionArguments.rawValue: L10nEntry("Arguments", "参数"),
        SnippetsKey.editorSectionSnippets.rawValue: L10nEntry("Snippets", "代码片段"),
        SnippetsKey.editorInsertAccessibility.rawValue: L10nEntry("Insert a placeholder", "插入占位符"),
        SnippetsKey.editorFieldAccessibility.rawValue: L10nEntry("Snippet %@", "代码片段%@"),

        SnippetsKey.infoName.rawValue: L10nEntry("Name", "名称"),
        SnippetsKey.infoKeyword.rawValue: L10nEntry("Keyword", "关键字"),
        SnippetsKey.infoShortcut.rawValue: L10nEntry("Shortcut", "快捷键"),
        SnippetsKey.infoFile.rawValue: L10nEntry("File", "文件"),
        SnippetsKey.infoCharacters.rawValue: L10nEntry("Characters", "字符数"),
        SnippetsKey.infoTitle.rawValue: L10nEntry("Information", "信息"),

        SnippetsKey.pasteSnippet.rawValue: L10nEntry("Paste Snippet", "粘贴代码片段"),
        SnippetsKey.loading.rawValue: L10nEntry("Loading snippets…", "正在加载代码片段…"),
        SnippetsKey.noMatching.rawValue: L10nEntry("No matching snippets", "没有匹配的代码片段"),
        SnippetsKey.noSnippets.rawValue: L10nEntry("No snippets yet", "暂无代码片段"),
        SnippetsKey.createSnippet.rawValue: L10nEntry("Create Snippet", "创建代码片段"),
        SnippetsKey.showInFinder.rawValue: L10nEntry("Show in Finder", "在访达中显示"),
        SnippetsKey.chooseFolderMessage.rawValue: L10nEntry(
            "Choose the folder your snippets are kept in.", "选择存放代码片段的文件夹。"),
        SnippetsKey.enableConfirmTitle.rawValue: L10nEntry("Enable snippets?", "启用代码片段？"),
        SnippetsKey.enableConfirmMessage.rawValue: L10nEntry(
            "Keyword expansion requires the Accessibility permission. Keystrokes stay on this Mac.",
            "关键字展开需要辅助功能权限。按键内容不会离开这台 Mac。"),
        SnippetsKey.enableConfirmAction.rawValue: L10nEntry("Continue", "继续"),
        SnippetsKey.clickTextField.rawValue: L10nEntry(
            "Click into a text field first", "请先点击一个文本输入框"),
        SnippetsKey.inserted.rawValue: L10nEntry("Inserted %@", "已插入 %@"),

        SnippetsKey.errorConflict.rawValue: L10nEntry(
            "The snippet changed on disk. Reload it before saving or deleting. (%@)",
            "代码片段在磁盘上已被修改。请在保存或删除前重新加载。(%@)"),
        SnippetsKey.errorFileNotFound.rawValue: L10nEntry(
            "The snippet file no longer exists. (%@)", "代码片段文件已不存在。(%@)"),
        SnippetsKey.errorInvalidLocation.rawValue: L10nEntry(
            "The snippet file is outside this GearMac channel. (%@)",
            "代码片段文件不在当前 GearMac 通道内。(%@)"),
        SnippetsKey.errorAccessFailed.rawValue: L10nEntry(
            "Could not access %@: %@", "无法访问 %@：%@")
    ]
}
