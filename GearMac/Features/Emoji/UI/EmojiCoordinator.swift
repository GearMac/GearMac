// 文件职责：表情功能的动作入口，负责粘贴、拷贝与保持窗口打开地粘贴，并记录使用频次。
// 分层：Coordinator；频次按基础字形统计，配置的肤色在拷贝/粘贴时才应用。
import AppKit

/// 负责表情的投递：频次按基础字形统计，配置的肤色在拷贝时应用。
@MainActor
final class EmojiCoordinator {
    private let frequentEmoji: FrequentEmojiStore
    private let settings: AppSettings
    private let windowController: PaletteWindowController
    private let paletteCoordinator: PaletteCoordinator

    init(
        frequentEmoji: FrequentEmojiStore,
        settings: AppSettings,
        windowController: PaletteWindowController,
        paletteCoordinator: PaletteCoordinator
    ) {
        self.frequentEmoji = frequentEmoji
        self.settings = settings
        self.windowController = windowController
        self.paletteCoordinator = paletteCoordinator
    }

    /// 粘贴表情：先计入频次，隐藏面板后按当前肤色粘贴到上一个应用。
    func pasteEmoji(_ entry: EmojiEntry) {
        frequentEmoji.record(entry.glyph)
        let previous = windowController.previousApp
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.pasteString(entry.display(tone: settings.emojiSkinTone), previousApp: previous)
    }

    /// 拷贝表情到剪贴板：先计入频次，隐藏面板后写入按当前肤色渲染的字形。
    func copyEmoji(_ entry: EmojiEntry) {
        frequentEmoji.record(entry.glyph)
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyString(entry.display(tone: settings.emojiSkinTone))
    }

    /// 粘贴表情但保持面板不关闭，便于连续输入多个表情。
    func pasteEmojiKeepingWindowOpen(_ entry: EmojiEntry) {
        frequentEmoji.record(entry.glyph)
        windowController.pasteStringKeepingWindowOpen(entry.display(tone: settings.emojiSkinTone))
    }
}
