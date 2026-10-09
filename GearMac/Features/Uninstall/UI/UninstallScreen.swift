// 文件职责：定义卸载子页面，把一次扫描得到的残留文件渲染为可选、可勾选的面板行。
// 分层：UI（SwiftUI，PaletteScreen）；只读取 UninstallSession 与 PaletteState，所有动作一律转交 UninstallCoordinator。
import SwiftUI

/// 某个应用被找到的残留文件列表，每一项都可选中并送入废纸篓。
struct UninstallScreen: PaletteScreen {
    let session: UninstallSession
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    /// 本页的搜索框按文件名或所在位置过滤列表。
    var rows: [UninstallCandidate] {
        let query = vm.query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return session.candidates }
        return session.candidates.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.locationLabel.localizedCaseInsensitiveContains(query)
        }
    }

    var primaryActionTitle: String { core.settings.text(UninstallKey.primaryAction) }

    /// 用作其他列表中的分节标题，这里显示已选数量与总大小。
    private var summary: String {
        let total = session.plan?.removableIDs.count ?? 0
        let size = MeasuredSize(bytes: session.selectedBytes).formatted
        return String(
            format: core.settings.text(UninstallKey.summary), session.selectedCount, total, size)
    }

    /// 按行号安全地取回候选条目。
    private func candidate(at selection: Int) -> UninstallCandidate? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    /// 为当前行提供操作菜单，没有对应条目时返回 nil。
    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let candidate = candidate(at: selection) else { return nil }
        return UninstallActionsMenu.content(candidate: candidate, session: session, core: core)
    }

    /// 主操作删除的是会话中已勾选的集合，而不是当前高亮的那一行。
    func activate(at selection: Int) {
        core.uninstallCoordinator.performUninstall()
    }

    /// 次级操作切换当前行的勾选状态；被锁定的条目不可勾选。
    func secondary(at selection: Int) -> Bool {
        guard let candidate = candidate(at: selection), !candidate.isLocked else { return false }
        session.toggle(candidate.id)
        return true
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        switch session.state {
        case .idle, .scanning:
            // 留空而不显示文案：发现过程只有几毫秒，任何提示都只会一闪而过。
            Color.clear
        case .failed(let failure):
            EmptyResults(text: failure.message(core.settings.resolvedLanguage))
        case .ready:
            let rows = rows
            if rows.isEmpty {
                EmptyResults(
                    text: vm.query.trimmingCharacters(in: .whitespaces).isEmpty
                        ? core.settings.text(UninstallKey.emptyNothingLeft)
                        : core.settings.text(UninstallKey.emptyNoMatch))
            } else {
                UninstallList(
                    results: rows,
                    selectedID: rows.indices.contains(selection) ? rows[selection].id : nil,
                    summary: summary,
                    scroll: scroll,
                    onSelect: { candidate in
                        if let index = rows.firstIndex(of: candidate) { vm.selection = index }
                    },
                    onToggle: { session.toggle($0.id) },
                    onActions: { candidate in
                        if let index = rows.firstIndex(of: candidate) { vm.selection = index }
                        openActions()
                    }
                )
            }
        }
    }
}

/// 卸载页面单行条目的操作菜单。
@MainActor
enum UninstallActionsMenu {
    /// 依据会话状态与条目是否被锁定，逐项构建菜单内容。
    static func content(
        candidate: UninstallCandidate, session: UninstallSession, core: AppCore
    ) -> PopoverMenuContent {
        var items: [PopoverMenuItem] = []
        if session.canConfirm {
            items.append(
                PopoverMenuItem(
                    title: core.settings.text(UninstallKey.menuUninstall), systemImage: "trash",
                    shortcut: "↵",
                    isDestructive: true
                ) { core.uninstallCoordinator.performUninstall() })
        }
        if !candidate.isLocked {
            let checked = session.selection?.isChecked(candidate.id) ?? false
            items.append(
                PopoverMenuItem(
                    title: core.settings.text(
                        checked ? UninstallKey.menuUnselectFile : UninstallKey.menuSelectFile),
                    systemImage: checked ? "circle" : "checkmark.circle", startsSection: true,
                    shortcut: "⌘↵"
                ) { session.toggle(candidate.id) })
        }
        items.append(
            PopoverMenuItem(
                title: core.settings.text(UninstallKey.menuCopyPath),
                systemImage: "doc.on.clipboard", startsSection: true, shortcut: "⌥⌘C"
            ) {
                core.uninstallCoordinator.copyUninstallPath(candidate)
            })
        items.append(
            PopoverMenuItem(
                title: core.settings.text(UninstallKey.menuShowInFinder), systemImage: "folder",
                shortcut: "⇧⌘O"
            ) {
                core.uninstallCoordinator.showUninstallItemInFinder(candidate)
            })
        items.append(
            PopoverMenuItem(
                title: core.settings.text(UninstallKey.menuShowInfoInFinder),
                systemImage: "info.circle", shortcut: "⇧⌘I"
            ) {
                core.uninstallCoordinator.showUninstallItemInfo(candidate)
            })
        return PopoverMenuContent(header: session.app?.name ?? candidate.name, items: items)
    }
}
