// 文件职责：编排卸载流程，串起残留扫描结果的交接、唯一一次确认弹窗与卸载后的引用清理。
// 分层：Coordinator（@MainActor）；只通过 UninstallSession、各类 Store 与 AppCore 读写状态，不直接操作文件系统。
import AppKit

/// 掌管卸载流程：扫描结果交接、唯一的确认入口，以及卸载完成后的引用清理。
@MainActor
final class UninstallCoordinator {
    private let session: UninstallSession
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    private let appIndex: AppIndex
    private let runningApps: RunningAppsMonitor
    private let hotKeys: HotKeyManager
    private let favorites: FavoritesStore
    private let visibility: VisibilityStore
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    /// 仅用于弹窗与消息 HUD 的呈现；绝不用于本类型自己拥有的状态。
    private unowned let core: AppCore

    /// 注入卸载会话、各类 Store 与 AppCore，构造时不产生任何副作用。
    init(
        session: UninstallSession,
        palette: PaletteState,
        paletteCoordinator: PaletteCoordinator,
        appIndex: AppIndex,
        runningApps: RunningAppsMonitor,
        hotKeys: HotKeyManager,
        favorites: FavoritesStore,
        visibility: VisibilityStore,
        ranking: LauncherRankingStore,
        aliases: AliasStore,
        core: AppCore
    ) {
        self.session = session
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.appIndex = appIndex
        self.runningApps = runningApps
        self.hotKeys = hotKeys
        self.favorites = favorites
        self.visibility = visibility
        self.ranking = ranking
        self.aliases = aliases
        self.core = core
    }

    /// 面板此时已经显示，因此这里只切换到卸载子页面，而不是重新弹出面板。
    func beginUninstall(_ app: AppEntry) {
        guard app.kind == .application else { return }
        // 用于避免仅凭名称或共享的 bundle ID 命名空间误判归属的其他应用。
        let others = appIndex.apps.filter { $0.kind == .application && $0.id != app.id }
        session.begin(
            app: app, otherAppNames: others.map(\.name),
            otherBundleIDs: others.compactMap(\.bundleID), isRunning: runningApps.isRunning(app))
        paletteCoordinator.navigate(to: .uninstall)
    }

    /// 该页 ↵ 键与操作菜单共用的唯一入口，保证两条路径都不会跳过确认。
    func performUninstall() {
        guard let app = session.app, let plan = session.plan, session.canConfirm else { return }
        let items = session.selectedCandidates
        guard !items.isEmpty else { return }
        Task {
            let running = plan.isTargetRunning || runningApps.isRunning(app)
            let size = MeasuredSize(bytes: items.reduce(0) { $0 + ($1.size?.bytes ?? 0) }).formatted
            let count =
                items.count == 1
                ? core.settings.text(UninstallKey.confirmItemOne)
                : String(format: core.settings.text(UninstallKey.confirmItemMany), items.count)
            let message = String(
                format: core.settings.text(UninstallKey.confirmMessage), count, size)
                + (running
                    ? String(
                        format: core.settings.text(UninstallKey.confirmQuitSuffix), app.name)
                    : "")
            guard
                await core.confirm(
                    title: String(
                        format: core.settings.text(UninstallKey.confirmTitle), app.name),
                    message: message,
                    symbol: "trash",
                    confirmTitle: core.settings.text(UninstallKey.confirmMoveToTrash))
            else { return }

            if running, let bundleID = app.bundleID { _ = AppLauncher.quit(bundleID: bundleID) }
            session.setTrashing(true)
            let report = await UninstallRunner.moveToTrash(items)
            session.setTrashing(false)

            if report.removedBundle {
                removeUninstalledReferences(app)
                await appIndex.refresh()
            }
            if !palette.pop() { palette.prepare(mode: .launcher) }
            await presentUninstallReport(report)
        }
    }

    /// 停留在当前页面：为复制一个路径而丢掉整次扫描并不划算。
    func copyUninstallPath(_ candidate: UninstallCandidate) {
        Paster.copyPlainText(candidate.path)
        core.showMessage(core.settings.text(UninstallKey.copiedPath))
    }

    /// 隐藏面板并在 Finder 中定位该条目所在的文件。
    func showUninstallItemInFinder(_ candidate: UninstallCandidate) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(candidate.url)
    }

    /// 隐藏面板并在 Finder 中打开该条目的“显示简介”；失败时提示用户授予自动化权限。
    func showUninstallItemInfo(_ candidate: UninstallCandidate) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Task {
            guard await !AppLauncher.showInfoInFinder(candidate.url) else { return }
            await core.showNotice(
                title: core.settings.text(UninstallKey.getInfoFailedTitle),
                message: core.settings.text(UninstallKey.getInfoFailedMessage),
                symbol: "info.circle", tone: .danger)
        }
    }

    /// 应用已删除后，清除它在快捷键、收藏、隐藏、排序与别名中的引用。
    private func removeUninstalledReferences(_ app: AppEntry) {
        if let action = app.hotKeyAction {
            if hotKeys.recordingAction == action { hotKeys.recordingAction = nil }
            hotKeys.setBinding(nil, for: action)
        }
        favorites.remove(keys: [app.preferenceKey])
        visibility.removeItemKeys([app.preferenceKey])
        ranking.reset(itemKey: app.preferenceKey)
        aliases.removeKeys([app.preferenceKey])
    }

    /// 呈现卸载结果：全部成功时用消息 HUD 汇报，存在失败时改用通知面板逐条列出原因。
    private func presentUninstallReport(_ report: UninstallReport) async {
        guard report.hasFailures else {
            guard report.trashedCount > 0 else { return }
            let count =
                report.trashedCount == 1
                ? core.settings.text(UninstallKey.confirmItemOne)
                : String(format: core.settings.text(UninstallKey.confirmItemMany), report.trashedCount)
            let freed = MeasuredSize(bytes: report.freedBytes).formatted
            core.showMessage(
                String(format: core.settings.text(UninstallKey.movedToTrash), count, freed))
            return
        }
        let listed = report.failed.prefix(5).map { "\($0.name) — \($0.reason)" }
        let remaining = report.failed.count - listed.count
        await core.showNotice(
            title: core.settings.text(
                report.trashedCount > 0 ? UninstallKey.reportSomeFailed : UninstallKey.reportNoneMoved),
            message: listed.joined(separator: "\n")
                + (remaining > 0
                    ? String(format: core.settings.text(UninstallKey.reportAndMore), remaining) : ""),
            symbol: "trash", tone: .danger)
    }
}
