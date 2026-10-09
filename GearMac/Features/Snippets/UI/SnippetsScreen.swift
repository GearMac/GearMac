// 文件职责：启动器中的片段搜索屏，按查询过滤已启用的片段库，并渲染列表与预览。
// 分层：UI；实现 PaletteScreen 协议，实际展开委托给 SnippetCoordinator。
import SwiftUI

/// Search Snippets 屏：把已启用的片段库按搜索框过滤，粘贴前先预览。
struct SnippetsScreen: PaletteScreen {
    let store: SnippetsStore
    let core: AppCore
    let vm: PaletteState

    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }
    let openActions: () -> Void

    /// 被禁用的片段处处关闭，因此浏览器列出的内容与启动器完全一致。
    var rows: [StoredSnippet] {
        let enabled = store.snippets.filter { $0.snippet.isEnabled }
        let query = vm.query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return enabled }
        return enabled.filter { record in
            record.snippet.name.localizedCaseInsensitiveContains(query)
                || record.snippet.keyword?.localizedCaseInsensitiveContains(query) == true
        }
    }

    var primaryActionTitle: String { core.settings.text(SnippetsKey.pasteSnippet) }

    private func record(at selection: Int) -> StoredSnippet? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let record = record(at: selection) else { return nil }
        return SnippetActionsMenu.content(record: record, core: core)
    }

    func activate(at selection: Int) {
        guard let record = record(at: selection) else { return }
        core.snippetCoordinator.expandSnippetFromPalette(id: record.id)
    }

    func secondary(at selection: Int) -> Bool { false }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        if rows.isEmpty {
            EmptyResults(text: emptyMessage)
        } else {
            let selected = record(at: selection)
            HStack(spacing: 0) {
                SnippetsList(
                    results: rows, selectedID: selected?.id, scroll: scroll,
                    onSelect: { record in
                        vm.selection = rows.firstIndex(of: record) ?? 0
                    },
                    onActivate: { activate(at: vm.selection) },
                    onActions: { record in
                        if let index = rows.firstIndex(of: record) { vm.selection = index }
                        openActions()
                    }
                )
                .frame(width: metrics.size.clipboardListWidth)
                Rectangle().fill(Theme.Colors.separator).frame(width: Theme.Size.hairline)
                SnippetPreview(record: selected)
            }
        }
    }

    /// 空库和过滤后为空是两种不同问题，提示文案也不同。
    private var emptyMessage: String {
        if store.state == .loading { return core.settings.text(SnippetsKey.loading) }
        return store.snippets.contains(where: { $0.snippet.isEnabled })
            ? core.settings.text(SnippetsKey.noMatching) : core.settings.text(SnippetsKey.noSnippets)
    }
}

/// 片段右键菜单的内容构造。
@MainActor
enum SnippetActionsMenu {
    static func content(record: StoredSnippet, core: AppCore) -> PopoverMenuContent {
        PopoverMenuContent(
            header: record.snippet.name,
            items: [
                PopoverMenuItem(
                    title: core.settings.text(SnippetsKey.pasteSnippet), systemImage: "text.quote",
                    shortcut: "↵"
                ) {
                    core.snippetCoordinator.expandSnippetFromPalette(id: record.id)
                },
                PopoverMenuItem(
                    title: core.settings.text(SnippetsKey.rowEdit), systemImage: "pencil",
                    startsSection: true
                ) {
                    core.paletteCoordinator.hidePalette(restoreFocus: false)
                    core.snippetCoordinator.editSnippet(record)
                },
                PopoverMenuItem(
                    title: core.settings.text(SnippetsKey.createSnippet), systemImage: "plus"
                ) {
                    core.paletteCoordinator.hidePalette(restoreFocus: false)
                    core.snippetCoordinator.editSnippet(nil)
                },
                PopoverMenuItem(
                    title: core.settings.text(SnippetsKey.showInFinder), systemImage: "folder",
                    startsSection: true
                ) {
                    core.snippetCoordinator.showSnippetInFinder(record)
                }
            ])
    }
}
