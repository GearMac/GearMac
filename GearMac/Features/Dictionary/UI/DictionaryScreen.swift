// 文件职责：词典界面，把面板查询词当作待查词条，用一个词条行展示释义而非列表。
// 分层：UI；实现 PaletteScreen 协议，动作转发给 DictionaryCoordinator。
import SwiftUI

/// 搜索框就是查询词；词条直接填满面板，而不是与列表并列。
struct DictionaryScreen: PaletteScreen {
    let session: DictionarySession
    let core: AppCore
    let vm: PaletteState

    /// 去除首尾空白后的当前查询词。
    private var term: String { vm.query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// 当前屏幕上的页面：下一个词解析期间保持不变，回车作用于当前展示的内容。
    private var entry: DictionaryEntry? { session.lookup?.entry }

    /// 只含这一个词条，因此底部操作与 ⌘K 的作用与选中行完全一致。
    var rows: [DictionaryEntry] { entry.map { [$0] } ?? [] }

    var primaryActionTitle: String { core.settings.text(DictionaryKey.copyDefinition) }

    /// 返回当前词条的弹出菜单内容：拷贝释义与在 Dictionary.app 中打开。
    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let entry else { return nil }
        return PopoverMenuContent(
            header: entry.term,
            items: [
                PopoverMenuItem(
                    title: core.settings.text(DictionaryKey.copyDefinition), systemImage: "doc.on.doc",
                    shortcut: "↵"
                ) {
                    core.dictionaryCoordinator.copy(entry)
                },
                PopoverMenuItem(
                    title: core.settings.text(DictionaryKey.openInDictionary), systemImage: "book",
                    shortcut: "⌘↵"
                ) {
                    core.dictionaryCoordinator.openInDictionary(entry)
                }
            ])
    }

    /// 主操作：拷贝当前词条释义。
    func activate(at selection: Int) {
        guard let entry else { return }
        core.dictionaryCoordinator.copy(entry)
    }

    /// 次操作：在 Dictionary.app 中打开；无词条时返回 false 表示未处理。
    func secondary(at selection: Int) -> Bool {
        guard let entry else { return false }
        core.dictionaryCoordinator.openInDictionary(entry)
        return true
    }

    /// 主体内容：空查询、已找到词条、已确认无结果三种状态分别渲染。
    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        if term.isEmpty {
            return AnyView(EmptyResults(text: core.settings.text(DictionaryKey.emptyPrompt)))
        }
        if let entry { return AnyView(DictionaryEntryView(entry: entry)) }
        if session.lookup?.term == term {
            return AnyView(EmptyResults(text: core.settings.text(DictionaryKey.emptyNoDefinition)))
        }
        return AnyView(Color.clear)
    }
}
