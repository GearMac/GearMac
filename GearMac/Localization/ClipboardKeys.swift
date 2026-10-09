// 文件职责：剪贴板功能的本地化键与中英词表。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 剪贴板面板、列表、设置与提示文案的键。
enum ClipboardKey: String, LocalizableKey {
    // MARK: - 类型筛选

    case filterAll = "clipboard.filter.all"
    case filterText = "clipboard.filter.text"
    case filterImage = "clipboard.filter.image"
    case filterFile = "clipboard.filter.file"
    case filterColor = "clipboard.filter.color"
    case filterLink = "clipboard.filter.link"
    case filterEmail = "clipboard.filter.email"

    // MARK: - 空列表提示

    case emptyAll = "clipboard.empty.all"
    case emptyText = "clipboard.empty.text"
    case emptyImage = "clipboard.empty.image"
    case emptyFile = "clipboard.empty.file"
    case emptyColor = "clipboard.empty.color"
    case emptyLink = "clipboard.empty.link"
    case emptyEmail = "clipboard.empty.email"

    // MARK: - 列表分区标题

    case bucketToday = "clipboard.bucket.today"
    case bucketYesterday = "clipboard.bucket.yesterday"
    case bucketThisWeek = "clipboard.bucket.thisWeek"
    case bucketThisMonth = "clipboard.bucket.thisMonth"
    case bucketEarlier = "clipboard.bucket.earlier"

    // MARK: - 底部横条

    case tabAll = "clipboard.tab.all"
    case tabText = "clipboard.tab.text"
    case tabImage = "clipboard.tab.image"
    case tabFile = "clipboard.tab.file"
    case tabColor = "clipboard.tab.color"
    case tabLink = "clipboard.tab.link"
    case tabEmail = "clipboard.tab.email"
    case tabTag = "clipboard.tab.tag"
    case cardCharacters = "clipboard.card.characters"
    case emptyTag = "clipboard.empty.tag"

    // MARK: - 文件类型

    case fileKindImage = "clipboard.fileKind.image"
    case fileKindMovie = "clipboard.fileKind.movie"
    case fileKindAudio = "clipboard.fileKind.audio"
    case fileKindPDF = "clipboard.fileKind.pdf"
    case fileKindFolder = "clipboard.fileKind.folder"
    case fileKindOther = "clipboard.fileKind.other"

    // MARK: - 颜色记法

    case colorFormatHex = "clipboard.colorFormat.hex"
    case colorFormatHexWithAlpha = "clipboard.colorFormat.hexWithAlpha"
    case colorFormatRGBA = "clipboard.colorFormat.rgba"
    case colorFormatHSL = "clipboard.colorFormat.hsl"
    case colorFormatHSLWithAlpha = "clipboard.colorFormat.hslWithAlpha"
    case colorFormatOklch = "clipboard.colorFormat.oklch"

    // MARK: - 默认动作

    case defaultActionPaste = "clipboard.defaultAction.paste"
    case defaultActionCopy = "clipboard.defaultAction.copy"
    case defaultActionPastePlainText = "clipboard.defaultAction.pastePlainText"
    case pasteToFormat = "clipboard.defaultAction.pasteTo"

    // MARK: - 保留时长

    case retentionDay = "clipboard.retention.day"
    case retentionWeek = "clipboard.retention.week"
    case retentionMonth = "clipboard.retention.month"
    case retentionThreeMonths = "clipboard.retention.threeMonths"
    case retentionSixMonths = "clipboard.retention.sixMonths"
    case retentionYear = "clipboard.retention.year"
    case retentionForever = "clipboard.retention.forever"

    // MARK: - 动作菜单与打标签

    case tagEntry = "clipboard.tag.entry"
    case tagBack = "clipboard.tag.back"
    case tagClear = "clipboard.tag.clear"
    case tagNew = "clipboard.tag.new"
    case tagNamePlaceholder = "clipboard.tag.namePlaceholder"
    case tagNameMissing = "clipboard.tag.nameMissing"
    case copyText = "clipboard.action.copyText"
    case deleteEntry = "clipboard.action.deleteEntry"
    case deleteAllEntries = "clipboard.action.deleteAllEntries"
    case deleteAllConfirm = "clipboard.action.deleteAllConfirm"

    // MARK: - 设置菜单

    case settingsDeleteAll = "clipboard.settings.deleteAll"
    case settingsToggleTextSearch = "clipboard.settings.toggleTextSearch"
    case settingsToggleHistory = "clipboard.settings.toggleHistory"
    case settingsMore = "clipboard.settings.more"

    // MARK: - 预览信息

    case information = "clipboard.info.title"
    case infoSource = "clipboard.info.source"
    case infoType = "clipboard.info.type"
    case infoCharacters = "clipboard.info.characters"
    case infoWords = "clipboard.info.words"
    case infoDimensions = "clipboard.info.dimensions"
    case infoSize = "clipboard.info.size"
    case infoPath = "clipboard.info.path"
    case infoCopied = "clipboard.info.copied"
    case typeText = "clipboard.info.typeText"
    case typeColor = "clipboard.info.typeColor"
    case typeImage = "clipboard.info.typeImage"
    case fileMissing = "clipboard.info.fileMissing"

    // MARK: - 提示与确认

    case hudCopiedPath = "clipboard.hud.copiedPath"
    case hudReadingText = "clipboard.hud.readingText"
    case hudNoTextFound = "clipboard.hud.noTextFound"
    case hudClipboardChanged = "clipboard.hud.clipboardChanged"
    case hudCopiedText = "clipboard.hud.copiedText"
    case hudReadFailed = "clipboard.hud.readFailed"
    case hudNothingToPaste = "clipboard.hud.nothingToPaste"
    case imageUnavailable = "clipboard.error.imageUnavailable"
    case fileMovedOrDeleted = "clipboard.error.fileMovedOrDeleted"
    case deleteAllMessage = "clipboard.error.deleteAllMessage"

    // MARK: - 设置

    case settingsEnable = "clipboard.settings.enable"
    case settingsEnableSubtitle = "clipboard.settings.enableSubtitle"
    case settingsKeepHistoryFor = "clipboard.settings.keepHistoryFor"
    case settingsTextSearch = "clipboard.settings.textSearch"
    case settingsTextSearchSubtitle = "clipboard.settings.textSearchSubtitle"
    case settingsDefaultAction = "clipboard.settings.defaultAction"
    case settingsDefaultActionSubtitle = "clipboard.settings.defaultActionSubtitle"
    case settingsDisabledAppsFooter = "clipboard.settings.disabledAppsFooter"
    case settingsClearTitle = "clipboard.settings.clearTitle"
    case settingsClearSubtitle = "clipboard.settings.clearSubtitle"
    case settingsClearButton = "clipboard.settings.clearButton"
    case settingsClearConfirmTitle = "clipboard.settings.clearConfirmTitle"
    case settingsClearConfirm = "clipboard.settings.clearConfirm"
    case settingsClearConfirmMessage = "clipboard.settings.clearConfirmMessage"
    case settingsCancel = "clipboard.settings.cancel"

    static let table: [String: L10nEntry] = [
        ClipboardKey.filterAll.rawValue: L10nEntry("All Types", "所有类型"),
        ClipboardKey.filterText.rawValue: L10nEntry("Text Only", "仅文本"),
        ClipboardKey.filterImage.rawValue: L10nEntry("Images Only", "仅图片"),
        ClipboardKey.filterFile.rawValue: L10nEntry("Files Only", "仅文件"),
        ClipboardKey.filterColor.rawValue: L10nEntry("Colors Only", "仅颜色"),
        ClipboardKey.filterLink.rawValue: L10nEntry("Links Only", "仅链接"),
        ClipboardKey.filterEmail.rawValue: L10nEntry("Emails Only", "仅邮箱"),

        ClipboardKey.emptyAll.rawValue: L10nEntry("Clipboard history is empty", "剪贴板历史为空"),
        ClipboardKey.emptyText.rawValue: L10nEntry(
            "No text in clipboard history", "剪贴板历史中没有文本"),
        ClipboardKey.emptyImage.rawValue: L10nEntry(
            "No images in clipboard history", "剪贴板历史中没有图片"),
        ClipboardKey.emptyFile.rawValue: L10nEntry(
            "No files in clipboard history", "剪贴板历史中没有文件"),
        ClipboardKey.emptyColor.rawValue: L10nEntry(
            "No colors in clipboard history", "剪贴板历史中没有颜色"),
        ClipboardKey.emptyLink.rawValue: L10nEntry(
            "No links in clipboard history", "剪贴板历史中没有链接"),
        ClipboardKey.emptyEmail.rawValue: L10nEntry(
            "No email addresses in clipboard history", "剪贴板历史中没有邮箱地址"),

        ClipboardKey.bucketToday.rawValue: L10nEntry("Today", "今天"),
        ClipboardKey.bucketYesterday.rawValue: L10nEntry("Yesterday", "昨天"),
        ClipboardKey.bucketThisWeek.rawValue: L10nEntry("This Week", "本周"),
        ClipboardKey.bucketThisMonth.rawValue: L10nEntry("This Month", "本月"),
        ClipboardKey.bucketEarlier.rawValue: L10nEntry("Earlier", "更早"),

        ClipboardKey.tabAll.rawValue: L10nEntry("Clipboard", "剪贴板"),
        ClipboardKey.tabText.rawValue: L10nEntry("Text", "文本"),
        ClipboardKey.tabImage.rawValue: L10nEntry("Images", "图片"),
        ClipboardKey.tabFile.rawValue: L10nEntry("Files", "文件"),
        ClipboardKey.tabColor.rawValue: L10nEntry("Colors", "颜色"),
        ClipboardKey.tabLink.rawValue: L10nEntry("Links", "链接"),
        ClipboardKey.tabEmail.rawValue: L10nEntry("Emails", "邮箱"),
        ClipboardKey.tabTag.rawValue: L10nEntry("Tags", "标签"),
        ClipboardKey.cardCharacters.rawValue: L10nEntry("%d characters", "%d个字符"),
        ClipboardKey.emptyTag.rawValue: L10nEntry(
            "No entries with this tag", "没有该标签的条目"),

        ClipboardKey.fileKindImage.rawValue: L10nEntry("Image", "图片"),
        ClipboardKey.fileKindMovie.rawValue: L10nEntry("Movie", "影片"),
        ClipboardKey.fileKindAudio.rawValue: L10nEntry("Audio", "音频"),
        ClipboardKey.fileKindPDF.rawValue: L10nEntry("PDF", "PDF"),
        ClipboardKey.fileKindFolder.rawValue: L10nEntry("Folder", "文件夹"),
        ClipboardKey.fileKindOther.rawValue: L10nEntry("File", "文件"),

        ClipboardKey.colorFormatHex.rawValue: L10nEntry("Hex", "十六进制"),
        ClipboardKey.colorFormatHexWithAlpha.rawValue: L10nEntry(
            "Hex with Alpha", "带 Alpha 的十六进制"),
        ClipboardKey.colorFormatRGBA.rawValue: L10nEntry("RGBA", "RGBA"),
        ClipboardKey.colorFormatHSL.rawValue: L10nEntry("HSL", "HSL"),
        ClipboardKey.colorFormatHSLWithAlpha.rawValue: L10nEntry(
            "HSL with Alpha", "带 Alpha 的 HSL"),
        ClipboardKey.colorFormatOklch.rawValue: L10nEntry("Oklch", "Oklch"),

        ClipboardKey.defaultActionPaste.rawValue: L10nEntry("Paste", "粘贴"),
        ClipboardKey.defaultActionCopy.rawValue: L10nEntry(
            "Copy to Clipboard", "复制到剪贴板"),
        ClipboardKey.defaultActionPastePlainText.rawValue: L10nEntry(
            "Paste as Plain Text", "以纯文本粘贴"),
        ClipboardKey.pasteToFormat.rawValue: L10nEntry("Paste to %@", "粘贴到 %@"),

        ClipboardKey.retentionDay.rawValue: L10nEntry("1 Day", "1 天"),
        ClipboardKey.retentionWeek.rawValue: L10nEntry("1 Week", "1 周"),
        ClipboardKey.retentionMonth.rawValue: L10nEntry("1 Month", "1 个月"),
        ClipboardKey.retentionThreeMonths.rawValue: L10nEntry("3 Months", "3 个月"),
        ClipboardKey.retentionSixMonths.rawValue: L10nEntry("6 Months", "6 个月"),
        ClipboardKey.retentionYear.rawValue: L10nEntry("1 Year", "1 年"),
        ClipboardKey.retentionForever.rawValue: L10nEntry("Forever", "永久"),

        ClipboardKey.tagEntry.rawValue: L10nEntry("Tag…", "打标签…"),
        ClipboardKey.tagBack.rawValue: L10nEntry("Back", "返回"),
        ClipboardKey.tagClear.rawValue: L10nEntry("Clear Tag", "清除标签"),
        ClipboardKey.tagNew.rawValue: L10nEntry("New Tag…", "新增标签"),
        ClipboardKey.tagNamePlaceholder.rawValue: L10nEntry(
            "Type a name, ↵ creates", "输入标签名，回车新建"),
        ClipboardKey.tagNameMissing.rawValue: L10nEntry(
            "A tag needs a name", "标签名不能为空"),
        ClipboardKey.copyText.rawValue: L10nEntry("Copy Text", "图片取字"),
        ClipboardKey.deleteEntry.rawValue: L10nEntry("Delete Entry", "删除条目"),
        ClipboardKey.deleteAllEntries.rawValue: L10nEntry("Delete All Entries", "删除全部条目"),
        ClipboardKey.deleteAllConfirm.rawValue: L10nEntry("Delete All", "全部删除"),

        ClipboardKey.settingsDeleteAll.rawValue: L10nEntry(
            "Delete All History…", "删除所有历史…"),
        ClipboardKey.settingsToggleTextSearch.rawValue: L10nEntry(
            "Search Text in Images", "图片文字搜索"),
        ClipboardKey.settingsToggleHistory.rawValue: L10nEntry(
            "Clipboard History", "剪贴板历史"),
        ClipboardKey.settingsMore.rawValue: L10nEntry("More Settings…", "更多设置…"),

        ClipboardKey.information.rawValue: L10nEntry("Information", "信息"),
        ClipboardKey.infoSource.rawValue: L10nEntry("Source", "来源"),
        ClipboardKey.infoType.rawValue: L10nEntry("Type", "类型"),
        ClipboardKey.infoCharacters.rawValue: L10nEntry("Characters", "字符数"),
        ClipboardKey.infoWords.rawValue: L10nEntry("Words", "词数"),
        ClipboardKey.infoDimensions.rawValue: L10nEntry("Dimensions", "尺寸"),
        ClipboardKey.infoSize.rawValue: L10nEntry("Size", "大小"),
        ClipboardKey.infoPath.rawValue: L10nEntry("Path", "路径"),
        ClipboardKey.infoCopied.rawValue: L10nEntry("Copied", "复制时间"),
        ClipboardKey.typeText.rawValue: L10nEntry("Text", "文本"),
        ClipboardKey.typeColor.rawValue: L10nEntry("Color", "颜色"),
        ClipboardKey.typeImage.rawValue: L10nEntry("Image", "图片"),
        ClipboardKey.fileMissing.rawValue: L10nEntry(
            "File is no longer available", "文件已不可用"),

        ClipboardKey.hudCopiedPath.rawValue: L10nEntry("Copied path", "已复制路径"),
        ClipboardKey.hudReadingText.rawValue: L10nEntry("Reading text…", "正在识别文本…"),
        ClipboardKey.hudNoTextFound.rawValue: L10nEntry("No text found", "未找到文本"),
        ClipboardKey.hudClipboardChanged.rawValue: L10nEntry(
            "Clipboard changed, text not copied", "剪贴板已变化，未复制文本"),
        ClipboardKey.hudCopiedText.rawValue: L10nEntry("Copied text", "已复制文本"),
        ClipboardKey.hudReadFailed.rawValue: L10nEntry("Couldn’t read the text", "无法识别文本"),
        ClipboardKey.hudNothingToPaste.rawValue: L10nEntry(
            "Nothing left to paste", "没有可继续粘贴的内容"),
        ClipboardKey.imageUnavailable.rawValue: L10nEntry(
            "That image is no longer available.", "该图片已不可用。"),
        ClipboardKey.fileMovedOrDeleted.rawValue: L10nEntry(
            "That file has moved or been deleted.", "该文件已被移动或删除。"),
        ClipboardKey.deleteAllMessage.rawValue: L10nEntry(
            "Are you sure you want to proceed with deleting all clipboard history entries?",
            "确定要删除全部剪贴板历史记录吗？"),

        ClipboardKey.settingsEnable.rawValue: L10nEntry(
            "Enable Clipboard History", "启用剪贴板历史"),
        ClipboardKey.settingsEnableSubtitle.rawValue: L10nEntry(
            "Keep copied items ready to reuse.", "保留复制过的内容，随时取用。"),
        ClipboardKey.settingsKeepHistoryFor.rawValue: L10nEntry("Keep history for", "历史保留时长"),
        ClipboardKey.settingsTextSearch.rawValue: L10nEntry(
            "Search text in images and PDFs", "搜索图片与 PDF 中的文本"),
        ClipboardKey.settingsTextSearchSubtitle.rawValue: L10nEntry(
            "Recognized on this Mac while idle.", "在系统空闲时于本机识别。"),
        ClipboardKey.settingsDefaultAction.rawValue: L10nEntry("Default action", "默认动作"),
        ClipboardKey.settingsDefaultActionSubtitle.rawValue: L10nEntry(
            "↵ does this, and Paste takes its shortcut.", "↵ 执行该动作，Paste 则占用它空出的快捷键。"),
        ClipboardKey.settingsDisabledAppsFooter.rawValue: L10nEntry(
            "Copies from these apps aren't recorded.", "来自这些应用的复制不会被记录。"),
        ClipboardKey.settingsClearTitle.rawValue: L10nEntry("Clear history", "清空历史"),
        ClipboardKey.settingsClearSubtitle.rawValue: L10nEntry(
            "Removes every clip and image.", "删除全部条目与图片。"),
        ClipboardKey.settingsClearButton.rawValue: L10nEntry("Clear…", "清空…"),
        ClipboardKey.settingsClearConfirmTitle.rawValue: L10nEntry(
            "Clear clipboard history?", "清空剪贴板历史？"),
        ClipboardKey.settingsClearConfirm.rawValue: L10nEntry("Clear History", "清空历史"),
        ClipboardKey.settingsClearConfirmMessage.rawValue: L10nEntry(
            "This can't be undone.", "此操作无法撤销。"),
        ClipboardKey.settingsCancel.rawValue: L10nEntry("Cancel", "取消")
    ]
}
