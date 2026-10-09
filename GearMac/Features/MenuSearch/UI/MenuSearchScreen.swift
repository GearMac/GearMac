// 文件职责：菜单搜索的调色板屏幕，把 Session 的目标与状态映射为读取中/空结果/结果列表。
// 分层：UI；实现 `PaletteScreen`，仅做展示与转发，不含 AX 访问与遍历逻辑。
import SwiftUI

/// 菜单搜索的调色板屏幕：根据目标类型与遍历状态渲染对应内容。
struct MenuSearchScreen: PaletteScreen {
    let session: MenuSearchSession
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    /// 屏幕上展示的行，来自 Session 过滤后的结果。
    var rows: [MenuSearchItem] { session.filtered }

    /// 主操作按钮文案。
    var primaryActionTitle: String { core.settings.text(MenuSearchKey.primaryAction) }

    func hasActions(at selection: Int) -> Bool { false }

    /// 按下标取行，越界返回 nil。
    private func item(at selection: Int) -> MenuSearchItem? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    /// 激活选中行对应的菜单项。
    func activate(at selection: Int) {
        guard let item = item(at: selection) else { return }
        core.menuSearchCoordinator.activate(item)
    }

    func secondary(at selection: Int) -> Bool { false }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    /// 按目标类型与状态渲染对应内容。
    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        switch session.target {
        case .searchable(let name):
            if session.state == .reading {
                EmptyResults(text: core.settings.text(MenuSearchKey.reading))
            } else if rows.isEmpty {
                EmptyResults(
                    text: String(
                        format: core.settings.text(MenuSearchKey.emptyNoItems), name))
            } else {
                MenuSearchList(
                    items: rows, targetName: name, isSearching: session.isSearching,
                    iconURL: core.menuSearchCoordinator.frozenIconURL,
                    iconStamp: core.menuSearchCoordinator.frozenIconStamp,
                    selectedID: rows.indices.contains(selection) ? rows[selection].id : nil,
                    scroll: scroll,
                    onActivate: { core.menuSearchCoordinator.activate($0) })
            }
        case .excluded(let name):
            EmptyResults(
                text: String(format: core.settings.text(MenuSearchKey.excluded), name))
        case .selfTarget:
            EmptyResults(text: core.settings.text(MenuSearchKey.selfTarget))
        case .menuLess(let name):
            EmptyResults(
                text: String(format: core.settings.text(MenuSearchKey.menuLess), name))
        case .noApplication:
            EmptyResults(text: core.settings.text(MenuSearchKey.noApplication))
        }
    }
}
