// 文件职责：窗口切换屏幕，定义 PaletteScreen 的展示与回车切换行为。
// 分层：UI（PaletteScreen）；遵照调色板屏协议，实际切换委托给 WindowSwitchCoordinator。
import SwiftUI

/// 窗口切换屏幕：列出可切换窗口，回车跳转。
struct WindowSwitchScreen: PaletteScreen {
    let session: WindowSwitchSession
    let core: AppCore

    /// 当前过滤后的窗口条目。
    var rows: [WindowSwitchEntry] { session.filtered }

    /// 主操作标题（固定为切换到窗口）。
    var primaryActionTitle: String { core.settings.text(WindowSwitcherKey.primaryAction) }

    /// 该屏幕不提供操作菜单。
    func hasActions(at selection: Int) -> Bool { false }

    /// ↵：切换到选中位置对应的窗口。
    func activate(at selection: Int) {
        guard rows.indices.contains(selection) else { return }
        core.windowSwitchCoordinator.activate(rows[selection])
    }

    /// 该屏幕不使用 ⌘↵ 主操作（保留为默认行为）。
    func secondary(at selection: Int) -> Bool { false }

    /// 屏幕主体：包装内容视图。
    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    /// 屏幕内容：无条目时区分「无窗口」与「无匹配」，否则渲染窗口列表。
    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        if rows.isEmpty {
            EmptyResults(
                text: core.settings.text(
                    session.snapshot.isEmpty
                        ? WindowSwitcherKey.emptyNoWindows : WindowSwitcherKey.emptyNoMatch))
        } else {
            WindowSwitchList(
                entries: rows,
                selectedID: rows.indices.contains(selection) ? rows[selection].id : nil,
                scroll: scroll,
                onActivate: { core.windowSwitchCoordinator.activate($0) })
        }
    }
}
