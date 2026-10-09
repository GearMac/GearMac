// 文件职责：Notes（笔记）功能的本地化键与中英词表。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 笔记功能所有用户可见文案的键。
enum NotesKey: String, LocalizableKey {
    // 空状态与标题栏操作
    case emptyTitle = "notes.empty.title"
    case actionCreate = "notes.action.create"
    case actionCreateHelp = "notes.action.createHelp"
    case actionBrowse = "notes.action.browse"
    case actionBrowseHelp = "notes.action.browseHelp"
    case actionOpenFolder = "notes.action.openFolder"
    case actionOpenFolderHelp = "notes.action.openFolderHelp"
    case windowTitle = "notes.windowTitle"

    // 字数统计
    case characterCountOne = "notes.characterCount.one"
    case characterCountMany = "notes.characterCount.many"
    case characterCountAccessibility = "notes.characterCount.accessibility"

    // 删除与文件夹选择
    case trashConfirmTitle = "notes.trash.confirmTitle"
    case trashConfirmMessage = "notes.trash.confirmMessage"
    case trashConfirmAction = "notes.trash.confirmAction"
    case chooseFolderMessage = "notes.chooseFolder.message"

    // 错误提示
    case errorOpen = "notes.error.open"
    case errorSave = "notes.error.save"
    case errorUpdate = "notes.error.update"
    case errorRetry = "notes.error.retry"
    case errorInvalidTitle = "notes.error.invalidTitle"
    case errorNotUTF8 = "notes.error.notUTF8"
    case errorOutsideFolder = "notes.error.outsideFolder"
    case errorAccessFailed = "notes.error.accessFailed"

    // 设置页
    case settingsEnableTitle = "notes.settings.enable.title"
    case settingsEnableSubtitle = "notes.settings.enable.subtitle"
    case settingsRenderMarkdown = "notes.settings.renderMarkdown"
    case settingsRenderMarkdownSubtitle = "notes.settings.renderMarkdown.subtitle"
    case settingsFormattingBar = "notes.settings.formattingBar"
    case settingsFolder = "notes.settings.folder"
    case settingsUseDefault = "notes.settings.useDefault"
    case settingsChoose = "notes.settings.choose"

    // 切换器
    case switcherSearchPlaceholder = "notes.switcher.searchPlaceholder"
    case switcherSearchLabel = "notes.switcher.searchLabel"
    case switcherClearSearch = "notes.switcher.clearSearch"
    case switcherSearching = "notes.switcher.searching"
    case switcherNoResults = "notes.switcher.noResults"
    case switcherTitlePlaceholder = "notes.switcher.titlePlaceholder"
    case switcherRename = "notes.switcher.rename"
    case switcherTrash = "notes.switcher.trash"

    // 格式栏
    case formatBold = "notes.format.bold"
    case formatItalic = "notes.format.italic"
    case formatStrikethrough = "notes.format.strikethrough"
    case formatInlineCode = "notes.format.inlineCode"
    case formatLink = "notes.format.link"
    case formatCodeBlock = "notes.format.codeBlock"
    case formatQuote = "notes.format.quote"
    case formatNumberedList = "notes.format.numberedList"
    case formatBulletList = "notes.format.bulletList"
    case formatTaskList = "notes.format.taskList"
    case formatAccessibility = "notes.format.accessibility"
    case formatExpanded = "notes.format.expanded"
    case formatCollapsed = "notes.format.collapsed"
    case formatToggleHelp = "notes.format.toggleHelp"
    case formatHeading = "notes.format.heading"
    case formatText = "notes.format.text"
    case formatHeadingLevel = "notes.format.headingLevel"

    // 标题层级菜单
    case headingLevel1 = "notes.heading.level1"
    case headingLevel2 = "notes.heading.level2"
    case headingLevel3 = "notes.heading.level3"
    case headingMenuAccessibility = "notes.heading.accessibility"

    // 编辑器
    case editorPlaceholder = "notes.editor.placeholder"

    static let table: [String: L10nEntry] = [
        NotesKey.emptyTitle.rawValue: L10nEntry("No Notes", "暂无笔记"),
        NotesKey.actionCreate.rawValue: L10nEntry("Create Note", "新建笔记"),
        NotesKey.actionCreateHelp.rawValue: L10nEntry("Create Note  ⌘N", "新建笔记  ⌘N"),
        NotesKey.actionBrowse.rawValue: L10nEntry("Browse Notes", "浏览笔记"),
        NotesKey.actionBrowseHelp.rawValue: L10nEntry("Browse Notes  ⌘P", "浏览笔记  ⌘P"),
        NotesKey.actionOpenFolder.rawValue: L10nEntry("Open Notes Folder", "打开笔记文件夹"),
        NotesKey.actionOpenFolderHelp.rawValue: L10nEntry(
            "Open Notes Folder  ⌘O", "打开笔记文件夹  ⌘O"),
        NotesKey.windowTitle.rawValue: L10nEntry("Notes", "笔记"),

        NotesKey.characterCountOne.rawValue: L10nEntry("1 character", "1 个字符"),
        NotesKey.characterCountMany.rawValue: L10nEntry("%d characters", "%d 个字符"),
        NotesKey.characterCountAccessibility.rawValue: L10nEntry("%@ in this note", "本笔记共 %@"),

        NotesKey.trashConfirmTitle.rawValue: L10nEntry(
            "Move “%@” to Trash?", "将“%@”移到废纸篓？"),
        NotesKey.trashConfirmMessage.rawValue: L10nEntry(
            "You can recover it from the Trash in Finder.", "你可以在访达的废纸篓中恢复它。"),
        NotesKey.trashConfirmAction.rawValue: L10nEntry("Move to Trash", "移到废纸篓"),
        NotesKey.chooseFolderMessage.rawValue: L10nEntry(
            "Choose the folder your notes are kept in.", "选择存放笔记的文件夹。"),

        NotesKey.errorOpen.rawValue: L10nEntry("Couldn’t Open Note", "无法打开笔记"),
        NotesKey.errorSave.rawValue: L10nEntry("Couldn’t Save Note", "无法保存笔记"),
        NotesKey.errorUpdate.rawValue: L10nEntry("Couldn’t Update Note", "无法更新笔记"),
        NotesKey.errorRetry.rawValue: L10nEntry("Retry", "重试"),
        NotesKey.errorInvalidTitle.rawValue: L10nEntry(
            "“%@” can’t be used as a note title.", "“%@”不能用作笔记标题。"),
        NotesKey.errorNotUTF8.rawValue: L10nEntry(
            "The note isn’t valid UTF-8. (%@)", "笔记不是有效的 UTF-8。(%@)"),
        NotesKey.errorOutsideFolder.rawValue: L10nEntry(
            "The note file is outside the notes folder. (%@)", "笔记文件不在笔记文件夹内。(%@)"),
        NotesKey.errorAccessFailed.rawValue: L10nEntry(
            "Could not access %@: %@", "无法访问 %@：%@"),

        NotesKey.settingsEnableTitle.rawValue: L10nEntry("Enable Notes", "启用笔记"),
        NotesKey.settingsEnableSubtitle.rawValue: L10nEntry(
            "Plain Markdown in a floating editor.", "在浮动编辑器中编辑纯 Markdown。"),
        NotesKey.settingsRenderMarkdown.rawValue: L10nEntry("Render Markdown", "渲染 Markdown"),
        NotesKey.settingsRenderMarkdownSubtitle.rawValue: L10nEntry(
            "Formats as you type.", "边输入边格式化。"),
        NotesKey.settingsFormattingBar.rawValue: L10nEntry("Show Formatting Bar", "显示格式栏"),
        NotesKey.settingsFolder.rawValue: L10nEntry("Notes Folder", "笔记文件夹"),
        NotesKey.settingsUseDefault.rawValue: L10nEntry("Use Default", "使用默认值"),
        NotesKey.settingsChoose.rawValue: L10nEntry("Choose…", "选取…"),

        NotesKey.switcherSearchPlaceholder.rawValue: L10nEntry("Search notes…", "搜索笔记…"),
        NotesKey.switcherSearchLabel.rawValue: L10nEntry("Search Notes", "搜索笔记"),
        NotesKey.switcherClearSearch.rawValue: L10nEntry("Clear Search", "清除搜索"),
        NotesKey.switcherSearching.rawValue: L10nEntry("Searching notes…", "正在搜索笔记…"),
        NotesKey.switcherNoResults.rawValue: L10nEntry("No notes found", "未找到笔记"),
        NotesKey.switcherTitlePlaceholder.rawValue: L10nEntry("Note title", "笔记标题"),
        NotesKey.switcherRename.rawValue: L10nEntry("Rename %@", "重命名 %@"),
        NotesKey.switcherTrash.rawValue: L10nEntry("Move %@ to Trash", "将 %@ 移到废纸篓"),

        NotesKey.formatBold.rawValue: L10nEntry("Bold", "加粗"),
        NotesKey.formatItalic.rawValue: L10nEntry("Italic", "斜体"),
        NotesKey.formatStrikethrough.rawValue: L10nEntry("Strikethrough", "删除线"),
        NotesKey.formatInlineCode.rawValue: L10nEntry("Inline Code", "行内代码"),
        NotesKey.formatLink.rawValue: L10nEntry("Link", "链接"),
        NotesKey.formatCodeBlock.rawValue: L10nEntry("Code Block", "代码块"),
        NotesKey.formatQuote.rawValue: L10nEntry("Quote", "引用"),
        NotesKey.formatNumberedList.rawValue: L10nEntry("Numbered List", "有序列表"),
        NotesKey.formatBulletList.rawValue: L10nEntry("Bullet List", "无序列表"),
        NotesKey.formatTaskList.rawValue: L10nEntry("Task List", "任务列表"),
        NotesKey.formatAccessibility.rawValue: L10nEntry("Formatting", "格式"),
        NotesKey.formatExpanded.rawValue: L10nEntry("Expanded", "已展开"),
        NotesKey.formatCollapsed.rawValue: L10nEntry("Collapsed", "已收起"),
        NotesKey.formatToggleHelp.rawValue: L10nEntry("Formatting  ⌥⌘T", "格式  ⌥⌘T"),
        NotesKey.formatHeading.rawValue: L10nEntry("Heading", "标题"),
        NotesKey.formatText.rawValue: L10nEntry("Text", "正文"),
        NotesKey.formatHeadingLevel.rawValue: L10nEntry("Heading %d", "%d 级标题"),

        NotesKey.headingLevel1.rawValue: L10nEntry("Heading 1", "一级标题"),
        NotesKey.headingLevel2.rawValue: L10nEntry("Heading 2", "二级标题"),
        NotesKey.headingLevel3.rawValue: L10nEntry("Heading 3", "三级标题"),
        NotesKey.headingMenuAccessibility.rawValue: L10nEntry("Heading", "标题"),

        NotesKey.editorPlaceholder.rawValue: L10nEntry("Start writing…", "开始写作…")
    ]
}
