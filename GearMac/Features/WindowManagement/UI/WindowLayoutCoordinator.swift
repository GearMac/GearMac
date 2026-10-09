// 文件职责：窗口布局协调器，负责布局库的管理、运行入口与门禁、抓取当前窗口，以及删除时的引用清理。
// 分层：Coordinator；@MainActor，运行通过串行任务队列保证同一时刻只执行一次。
import AppKit

/// 持有布局：库、唯一的运行入口及其门禁、抓取，以及删除时的清理。
@MainActor
final class WindowLayoutCoordinator {
    private let store: WindowLayoutStore
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let hotKeys: HotKeyManager
    private let favorites: FavoritesStore
    private let visibility: VisibilityStore
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    /// 仅用于对话框与消息 HUD 展示以及编辑器交接；该类不持有它的任何状态。
    private unowned let core: AppCore
    /// 同一时刻只运行一次：长按快捷键不能在同一批窗口上叠加两趟操作。
    private var run: Task<Void, Never>?

    init(
        store: WindowLayoutStore, settings: AppSettings, appIndex: AppIndex,
        hotKeys: HotKeyManager, favorites: FavoritesStore, visibility: VisibilityStore,
        ranking: LauncherRankingStore, aliases: AliasStore,
        paletteCoordinator: PaletteCoordinator, settingsCoordinator: SettingsCoordinator,
        core: AppCore
    ) {
        self.store = store
        self.settings = settings
        self.appIndex = appIndex
        self.hotKeys = hotKeys
        self.favorites = favorites
        self.visibility = visibility
        self.ranking = ranking
        self.aliases = aliases
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.core = core
    }

    // MARK: - Feature presence

    /// 根据设置同步布局在启动器中的可见性与命令注册状态。
    func applyWindowLayoutsPresence() {
        let visible = settings.windowManagementEnabled && settings.windowLayoutsShowInLauncher
        appIndex.setWindowLayouts(visible ? store.layouts : [])
        let commands: Set<CommandID> = [.createWindowLayout, .captureWindowLayout]
        appIndex.setCommandsVisible(commands, settings.windowManagementEnabled)
        appIndex.setCommandsListed(commands, settings.windowLayoutsShowInLauncher)
    }

    // MARK: - Running

    /// 调色板行、全局快捷键与面板「应用」共用的唯一入口。
    func runWindowLayout(id: UUID) {
        guard settings.windowManagementEnabled, let layout = store.layout(id: id) else { return }
        // 绝不 restoreFocus：被打开的 App 会自行激活，交还焦点会与之竞争。
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        let gap = CGFloat(settings.windowGap)
        run?.cancel()
        run = Task { [weak self] in
            let outcome = await WindowLayoutRunner.run(layout, gap: gap)
            await self?.report(outcome, for: layout)
        }
    }

    /// 退出前取消正在运行的布局任务。
    func prepareForTermination() {
        run?.cancel()
        run = nil
    }

    // MARK: - Library

    /// 新增布局并返回写入结果；校验失败时抛出错误。
    @discardableResult
    func addWindowLayout(
        _ draft: WindowLayout
    ) throws(WindowLayoutValidationError) -> WindowLayout {
        try store.add(draft)
    }

    /// 更新已有布局；校验失败时抛出错误。
    func updateWindowLayout(_ draft: WindowLayout) throws(WindowLayoutValidationError) {
        try store.update(draft)
    }

    /// 复制指定布局；失败时异步提示。
    func duplicateWindowLayout(id: UUID) {
        do {
            _ = try store.duplicate(id: id)
        } catch {
            Task { await report(failure: error) }
        }
    }

    /// 删除指定布局并清理其引用。
    func deleteWindowLayout(id: UUID) {
        guard let layout = store.remove(id: id) else { return }
        // 仅在记录确实被移除后才清理关联，保证保留的记录不会丢失快捷键。
        removeWindowLayoutReferences(ids: [layout.id], entryIDs: [layout.entryID])
    }

    /// 用导入的布局整体替换现有集合，并清理被移除项的引用；返回写入条数。
    @discardableResult
    func replaceWindowLayouts(_ incoming: [WindowLayout]) -> Int {
        let previous = Dictionary(uniqueKeysWithValues: store.layouts.map { ($0.id, $0) })
        let count = store.replace(with: incoming)
        let live = Set(store.layouts.map(\.id))
        let removed = Set(previous.keys).subtracting(live)
        removeWindowLayoutReferences(
            ids: removed, entryIDs: Set(removed.compactMap { previous[$0]?.entryID }))
        return count
    }

    // MARK: - Editing

    /// 打开窗口管理面板并让编辑器展示 `layout`；传 nil 表示新建。
    func editWindowLayout(_ layout: WindowLayout?) {
        core.pendingWindowLayoutEdit = WindowLayoutEditRequest(layout: layout)
        settingsCoordinator.showSettings(tab: .windowManagement)
    }

    /// 抓取绝不静默保存：草稿进入编辑器，便于查看并命名。
    func captureWindowLayout() {
        let (entries, frontmostEntryID) = WindowLayoutRunner.captureCurrentWindows()
        guard !entries.isEmpty else {
            core.showMessage(settings.text(WindowKey.layoutNoWindowsToCapture), tone: .neutral)
            return
        }
        // 构造上即无缝（无间隙），因此后续修改 `windowGap` 不会移动所有窗口。
        let draft = WindowLayout(
            name: uniqueCaptureName(among: store.layouts), usesPreferredGap: false,
            entries: entries, frontmostEntryID: frontmostEntryID)
        core.pendingWindowLayoutEdit = WindowLayoutEditRequest(layout: draft, isCapture: true)
        settingsCoordinator.showSettings(tab: .windowManagement)
    }

    // MARK: - Reporting

    /// 汇报运行结果：权限受阻、完全失败或部分失败。
    private func report(_ outcome: WindowLayoutRunner.Outcome, for layout: WindowLayout) async {
        if outcome.isBlockedOnPermission {
            let openSettings = await core.reportFailure(
                title: settings.text(WindowKey.permissionTitle),
                message: settings.text(WindowKey.layoutPermissionMessage),
                symbol: layout.symbol, recovery: settings.text(WindowKey.permissionRecovery))
            if openSettings { Permissions.openAccessibilitySettings() }
            return
        }
        // 窗口摆放本身就是反馈，因此一次无异常的运行不显示任何消息。
        guard let detail = detail(for: outcome) else { return }
        guard outcome.didAnything else {
            await core.showNotice(
                title: String(
                    format: settings.text(WindowKey.layoutRunFailedTitle), layout.name),
                message: detail, symbol: layout.symbol,
                tone: .danger)
            return
        }
        core.showMessage(
            String(format: settings.text(WindowKey.layoutMessage), layout.name, detail),
            tone: .neutral)
    }

    /// 说明哪里出错；当布局要求的一切都成功时返回 nil。
    private func detail(for outcome: WindowLayoutRunner.Outcome) -> String? {
        var parts: [String] = []
        if let skipped = WindowLayoutPlan(placements: [], skipped: outcome.skipped)
            .localizedSkippedSummary(settings.resolvedLanguage)
        {
            parts.append(skipped)
        }
        if !outcome.neverAppeared.isEmpty {
            let count = outcome.neverAppeared.count
            parts.append(
                count == 1
                    ? settings.text(WindowKey.layoutMissingAppOne)
                    : String(format: settings.text(WindowKey.layoutMissingAppMany), count))
        }
        let failed = outcome.openFailures.count
        if failed > 0 {
            parts.append(
                failed == 1
                    ? settings.text(WindowKey.layoutFailedAppOne)
                    : String(format: settings.text(WindowKey.layoutFailedAppMany), failed))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 保存失败时的提示。
    private func report(failure: WindowLayoutValidationError) async {
        await core.showNotice(
            title: settings.text(WindowKey.layoutSaveFailedTitle),
            message: failure.localizedMessage(settings.resolvedLanguage),
            symbol: WindowLayout.sfSymbol, tone: .danger)
    }

    /// 清理被移除布局的快捷键绑定、收藏、可见性、别名与排序记录。
    private func removeWindowLayoutReferences(ids: Set<UUID>, entryIDs: Set<String>) {
        for id in ids {
            let action = HotKeyAction.windowLayout(id: id)
            if hotKeys.recordingAction == action { hotKeys.recordingAction = nil }
            hotKeys.setBinding(nil, for: action)
        }
        favorites.remove(keys: entryIDs)
        visibility.removeItemKeys(entryIDs)
        aliases.removeKeys(entryIDs)
        for entryID in entryIDs {
            ranking.reset(itemKey: entryID)
        }
    }

    /// 先生成“捕获的布局”，冲突时再加 " 2"，以便编辑器打开的名称能通过校验。
    private func uniqueCaptureName(among existing: [WindowLayout]) -> String {
        let taken = Set(existing.map { $0.name.lowercased() })
        let base = settings.text(WindowKey.layoutCapturedName)
        guard taken.contains(base.lowercased()) else { return base }
        var index = 2
        while taken.contains("\(base) \(index)".lowercased()) { index += 1 }
        return "\(base) \(index)"
    }
}
