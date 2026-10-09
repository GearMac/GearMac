// 文件职责：表情与符号功能的本地化键与中英词表。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 表情选择器、设置页与动作菜单文案的键。
enum EmojiKey: String, LocalizableKey {
    // MARK: - 分类

    case categorySmileysAndPeople = "emoji.category.smileysAndPeople"
    case categoryAnimalsAndNature = "emoji.category.animalsAndNature"
    case categoryFoodAndDrink = "emoji.category.foodAndDrink"
    case categoryActivity = "emoji.category.activity"
    case categoryTravelAndPlaces = "emoji.category.travelAndPlaces"
    case categoryObjects = "emoji.category.objects"
    case categorySymbols = "emoji.category.symbols"
    case categoryFlags = "emoji.category.flags"
    case categoryArrows = "emoji.category.arrows"
    case categoryCurrency = "emoji.category.currency"
    case categoryMath = "emoji.category.math"
    case categoryShapesAndPunctuation = "emoji.category.shapesAndPunctuation"
    case categoryCJK = "emoji.category.cjk"
    case categoryKeysAndTechnical = "emoji.category.keysAndTechnical"

    // MARK: - 筛选项

    case filterAll = "emoji.filter.all"
    case filterPinned = "emoji.filter.pinned"
    case filterFrequentlyUsed = "emoji.filter.frequentlyUsed"
    case sectionResults = "emoji.section.results"

    // MARK: - 动作菜单

    case actionPaste = "emoji.action.paste"
    case actionCopyToClipboard = "emoji.action.copyToClipboard"
    case actionPasteAndKeepOpen = "emoji.action.pasteAndKeepOpen"
    case actionPinFormat = "emoji.action.pin"
    case actionUnpinFormat = "emoji.action.unpin"
    case actionMoveUp = "emoji.action.moveUp"
    case actionMoveDown = "emoji.action.moveDown"
    case actionActualSize = "emoji.action.actualSize"
    case actionZoomIn = "emoji.action.zoomIn"
    case actionZoomOut = "emoji.action.zoomOut"

    // MARK: - 空态

    case emptyLoading = "emoji.empty.loading"
    case emptyNoResults = "emoji.empty.noResults"

    // MARK: - 设置

    case settingsSkinTone = "emoji.settings.skinTone"
    case settingsColumnCount = "emoji.settings.columnCount"
    case settingsColumnsFormat = "emoji.settings.columns"
    case settingsColumnsAccessibilityFormat = "emoji.settings.columnsAccessibility"
    case toneDefault = "emoji.tone.default"
    case toneLight = "emoji.tone.light"
    case toneMediumLight = "emoji.tone.mediumLight"
    case toneMedium = "emoji.tone.medium"
    case toneMediumDark = "emoji.tone.mediumDark"
    case toneDark = "emoji.tone.dark"

    // MARK: - 动作中的名词

    case nounEmoji = "emoji.noun.emoji"
    case nounSymbol = "emoji.noun.symbol"

    static let table: [String: L10nEntry] = [
        EmojiKey.categorySmileysAndPeople.rawValue: L10nEntry(
            "Smileys & People", "笑脸与人物"),
        EmojiKey.categoryAnimalsAndNature.rawValue: L10nEntry(
            "Animals & Nature", "动物与自然"),
        EmojiKey.categoryFoodAndDrink.rawValue: L10nEntry("Food & Drink", "食物与饮品"),
        EmojiKey.categoryActivity.rawValue: L10nEntry("Activity", "活动"),
        EmojiKey.categoryTravelAndPlaces.rawValue: L10nEntry(
            "Travel & Places", "旅行与地点"),
        EmojiKey.categoryObjects.rawValue: L10nEntry("Objects", "物品"),
        EmojiKey.categorySymbols.rawValue: L10nEntry("Symbols", "符号"),
        EmojiKey.categoryFlags.rawValue: L10nEntry("Flags", "旗帜"),
        EmojiKey.categoryArrows.rawValue: L10nEntry("Arrows", "箭头"),
        EmojiKey.categoryCurrency.rawValue: L10nEntry("Currency", "货币"),
        EmojiKey.categoryMath.rawValue: L10nEntry("Math", "数学"),
        EmojiKey.categoryShapesAndPunctuation.rawValue: L10nEntry(
            "Shapes & Punctuation", "形状与标点"),
        EmojiKey.categoryCJK.rawValue: L10nEntry("CJK Symbols", "CJK 符号"),
        EmojiKey.categoryKeysAndTechnical.rawValue: L10nEntry(
            "Keys & Technical", "按键与技术"),

        EmojiKey.filterAll.rawValue: L10nEntry("All Categories", "全部分类"),
        EmojiKey.filterPinned.rawValue: L10nEntry("Pinned", "已固定"),
        EmojiKey.filterFrequentlyUsed.rawValue: L10nEntry("Frequently Used", "常用"),
        EmojiKey.sectionResults.rawValue: L10nEntry("Results", "搜索结果"),

        EmojiKey.actionPaste.rawValue: L10nEntry("Paste", "粘贴"),
        EmojiKey.actionCopyToClipboard.rawValue: L10nEntry(
            "Copy to Clipboard", "复制到剪贴板"),
        EmojiKey.actionPasteAndKeepOpen.rawValue: L10nEntry(
            "Paste and Keep Window Open", "粘贴并保持窗口打开"),
        EmojiKey.actionPinFormat.rawValue: L10nEntry("Pin %@", "固定 %@"),
        EmojiKey.actionUnpinFormat.rawValue: L10nEntry("Unpin %@", "取消固定 %@"),
        EmojiKey.actionMoveUp.rawValue: L10nEntry("Move Up in Pinned", "在固定列表中上移"),
        EmojiKey.actionMoveDown.rawValue: L10nEntry("Move Down in Pinned", "在固定列表中下移"),
        EmojiKey.actionActualSize.rawValue: L10nEntry("Actual Size", "实际大小"),
        EmojiKey.actionZoomIn.rawValue: L10nEntry("Zoom In", "放大"),
        EmojiKey.actionZoomOut.rawValue: L10nEntry("Zoom Out", "缩小"),

        EmojiKey.emptyLoading.rawValue: L10nEntry("Loading emoji…", "正在加载表情…"),
        EmojiKey.emptyNoResults.rawValue: L10nEntry("No emoji found", "未找到表情"),

        EmojiKey.settingsSkinTone.rawValue: L10nEntry("Emoji Skin Tone", "表情肤色"),
        EmojiKey.settingsColumnCount.rawValue: L10nEntry("Column Count", "列数"),
        EmojiKey.settingsColumnsFormat.rawValue: L10nEntry("%d columns", "%d 列"),
        EmojiKey.settingsColumnsAccessibilityFormat.rawValue: L10nEntry(
            "%d columns", "%d 列"),
        EmojiKey.toneDefault.rawValue: L10nEntry("Default", "默认"),
        EmojiKey.toneLight.rawValue: L10nEntry("Light", "浅色"),
        EmojiKey.toneMediumLight.rawValue: L10nEntry("Medium Light", "中浅"),
        EmojiKey.toneMedium.rawValue: L10nEntry("Medium", "中等"),
        EmojiKey.toneMediumDark.rawValue: L10nEntry("Medium Dark", "中深"),
        EmojiKey.toneDark.rawValue: L10nEntry("Dark", "深色"),

        EmojiKey.nounEmoji.rawValue: L10nEntry("Emoji", "表情"),
        EmojiKey.nounSymbol.rawValue: L10nEntry("Symbol", "符号"),
    ]
}
