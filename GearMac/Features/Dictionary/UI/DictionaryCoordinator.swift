// 文件职责：词典功能的动作入口，负责打开词典屏、拷贝释义与在 Dictionary.app 中打开词条。
// 分层：Coordinator；直接调用 UI 与服务完成页面切换和外部打开。
import Foundation

/// 词典的动作面：在屏幕上打开某个词条，并对当前显示的词条执行操作。
@MainActor
final class DictionaryCoordinator {
    private let paletteCoordinator: PaletteCoordinator

    init(paletteCoordinator: PaletteCoordinator) {
        self.paletteCoordinator = paletteCoordinator
    }

    /// `term` 是回退行的查询词，因此屏幕打开时已经展示对应词条。
    func show(term: String = "") {
        paletteCoordinator.togglePalette(mode: .dictionary, seeding: term.isEmpty ? nil : term)
    }

    /// 拷贝词条文本到剪贴板，并先隐藏面板。
    func copy(_ entry: DictionaryEntry) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(entry.text)
    }

    /// 在 Dictionary.app 中打开完整词条，包含读者已启用的全部辞典。
    func openInDictionary(_ entry: DictionaryEntry) {
        guard let term = entry.term.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
            let url = URL(string: "dict://" + term)
        else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.open(url)
    }
}
