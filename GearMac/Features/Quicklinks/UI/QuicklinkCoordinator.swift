// 文件职责：编排快捷链接的全部流程，包括打开漏斗、参数询问、链接库增删改、快捷键/置顶/别名等引用维护，以及导入导出。
// 分层：Coordinator；持有各 Store/Manager 引用，所有打开动作均须经此处以保证开关与参数校验不被绕过。
import AppKit

/// 负责快捷链接的完整流程：打开漏斗、参数询问、链接库以及导入导出。
@MainActor
final class QuicklinkCoordinator {
    private let store: QuicklinkStore
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let injector: TextInjector
    private let hotKeys: HotKeyManager
    private let favorites: FavoritesStore
    private let visibility: VisibilityStore
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    private let windowController: PaletteWindowController
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    /// `{clipboard offset=N}` 读取的是代码片段展开所用的同份剪贴板历史；一个所有者，一个深度。
    private let clipboardHistory: @MainActor () -> [String]
    /// 负责对话框、HUD，以及向设置面板交接的 `pendingQuicklinkEdit`。
    private unowned let core: AppCore

    /// 其 ⌘↵「用默认应用打开」覆盖需要跨越头部参数字段的往返而保留的快捷链接。
    private var pendingDefaultAppOverride: UUID?

    /// 注入各依赖；剪贴板历史以闭包传入，由外部决定读取时机。
    init(
        store: QuicklinkStore,
        settings: AppSettings,
        appIndex: AppIndex,
        injector: TextInjector,
        hotKeys: HotKeyManager,
        favorites: FavoritesStore,
        visibility: VisibilityStore,
        ranking: LauncherRankingStore,
        aliases: AliasStore,
        windowController: PaletteWindowController,
        paletteCoordinator: PaletteCoordinator,
        settingsCoordinator: SettingsCoordinator,
        clipboardHistory: @escaping @MainActor () -> [String],
        core: AppCore
    ) {
        self.store = store
        self.settings = settings
        self.appIndex = appIndex
        self.injector = injector
        self.hotKeys = hotKeys
        self.favorites = favorites
        self.visibility = visibility
        self.ranking = ranking
        self.aliases = aliases
        self.windowController = windowController
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.clipboardHistory = clipboardHistory
        self.core = core
    }

    // MARK: - Feature presence

    /// 任一开关关闭时，该功能都不会到达启动器——行与命令皆然。
    func applyQuicklinksPresence() {
        let visible = settings.quicklinksEnabled && settings.quicklinksShowInLauncher
        appIndex.setQuicklinks(visible ? store.quicklinks : [])
        let commands: Set<CommandID> = [
            .createQuicklink, .searchQuicklinks, .importQuicklinks, .exportQuicklinks
        ]
        appIndex.setCommandsVisible(commands, settings.quicklinksEnabled)
        appIndex.setCommandsListed(commands, settings.quicklinksShowInLauncher)
    }

    // MARK: - Opening

    /// 所有打开动作的唯一漏斗，确保开关状态与缺失的参数都无法被绕过。
    /// `values` 是头部的参数字段；任何仍缺失的值都会把该行退回给这些字段。
    func openQuicklink(
        id: UUID, forcingDefaultApp: Bool = false, values: [String: String] = [:]
    ) {
        guard settings.quicklinksEnabled, let quicklink = store.quicklink(id: id),
            quicklink.isEnabled
        else { return }
        // 命令面板关闭时，快捷键仍会从光标所在处读取选区。
        let target =
            windowController.isVisible
            ? windowController.previousTarget : InjectionTarget.current()
        let encoding: SnippetTemplateEngine.ValueEncoding =
            QuicklinkDestination.usesURLEncoding(quicklink.link) ? .percentEncoding : .none
        var context = injector.captureExpansionContext(
            target: target, clipboardHistory: clipboardHistory())
        var needsSelection = false

        // 无法读取的选区属于缺失而非空：改用剪贴板内容，或改由输入字段采集。
        if context.selection.isEmpty, SnippetTemplateEngine.usesSelection(quicklink.link) {
            switch settings.quicklinkSelectionFallback {
            case .clipboard:
                context = context.replacingSelection(with: context.clipboard)
            case .ask:
                let typed = values[Self.selectionArgument.name] ?? ""
                needsSelection = typed.isEmpty
                if !typed.isEmpty { context = context.replacingSelection(with: typed) }
            }
        }

        // 该覆盖需要跨越参数字段的往返，因此回程时仍予以尊重。
        let forcesDefault = forcingDefaultApp || pendingDefaultAppOverride == id
        let expansion = SnippetTemplateEngine.expand(
            text: quicklink.link, context: context, userArguments: values, encoding: encoding)
        guard expansion.missingArguments.isEmpty, !needsSelection else {
            pendingDefaultAppOverride = forcesDefault ? id : nil
            promptForArguments(quicklink, values: values)
            return
        }
        pendingDefaultAppOverride = nil
        performQuicklinkOpen(quicklink, link: expansion.text, forcingDefaultApp: forcesDefault)
    }

    /// 兜底行的查询文本，用于填充链接中第一个尚未填写的 `{argument}`。
    func openQuicklink(id: UUID, filling seed: String) {
        guard let quicklink = store.quicklink(id: id) else { return }
        let arguments = SnippetTemplateEngine.declaredArguments(in: quicklink.link)
        guard let target = arguments.first(where: { !$0.isOptional }) ?? arguments.first else {
            return openQuicklink(id: id)
        }
        openQuicklink(id: id, values: [target.name: seed])
    }

    /// 选区无法读取时被提升为字段的 `{selection}`；即使留空，在打开时仍会解析。
    static let selectionArgument = SnippetTemplateEngine.DeclaredArgument(
        name: "Selected Text", options: [], isOptional: true)

    /// 某行在头部展示的字段：链接自身的参数，再加上设置所要求的那个字段。
    func promptedArguments(for quicklink: Quicklink) -> [SnippetTemplateEngine.DeclaredArgument] {
        var arguments = SnippetTemplateEngine.declaredArguments(in: quicklink.link)
        // 提前询问，而不是等读取失败后再问：快捷键触发时无法捕获选区。
        if settings.quicklinkSelectionFallback == .ask,
            SnippetTemplateEngine.usesSelection(quicklink.link)
        {
            arguments.append(Self.selectionArgument)
        }
        return arguments
    }

    /// 「搜索快捷链接」是唯一的参数输入界面，因此缺值的快捷键会落到这里。
    private func promptForArguments(_ quicklink: Quicklink, values: [String: String]) {
        paletteCoordinator.showPalette(mode: .quicklinks)
        // 必须在展示之后设置：`prepare` 运行于展示内部，会清空此前设置的内容。
        core.palette.selection = store.enabled.firstIndex(of: quicklink) ?? 0
        for (name, value) in values {
            core.palette.commandArguments[PaletteState.argumentKey(quicklink.entryID, name)] = value
        }
        core.palette.pendingArgumentEntryID = quicklink.entryID
    }

    /// 隐藏命令面板（若可见）并执行打开；`forcingDefaultApp` 为真时忽略保存的「打开方式」。
    private func performQuicklinkOpen(
        _ quicklink: Quicklink, link: String, forcingDefaultApp: Bool
    ) {
        if windowController.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        let openWith = forcingDefaultApp ? nil : quicklink.openWithBundleID
        Task {
            do throws(QuicklinkLauncher.Failure) {
                try await QuicklinkLauncher.open(
                    link, openWithBundleID: openWith,
                    inNewWindow: settings.quicklinkOpensNewWindow)
            } catch {
                await presentQuicklinkFailure(quicklink, link: link, failure: error)
            }
        }
    }

    /// 打开失败后的提示；若失败带缺失的应用 bundle ID，则额外提供「用默认应用打开」的恢复选项。
    private func presentQuicklinkFailure(
        _ quicklink: Quicklink, link: String, failure: QuicklinkLauncher.Failure
    ) async {
        let symbol = quicklink.iconSymbol ?? Quicklink.sfSymbol
        guard let bundleID = failure.missingApplicationBundleID else {
            await core.showNotice(
                title: String(
                    format: settings.text(QuicklinksKey.errorOpenNamed), quicklink.name),
                message: failure.message(settings.language), symbol: symbol, tone: .danger)
            return
        }
        // 唯一带有可用备选方案的失败类型，因此给出备选而不是直接走死路。
        let name = applicationName(forBundleID: bundleID) ?? bundleID
        guard
            await core.reportFailure(
                title: String(
                    format: settings.text(QuicklinksKey.errorOpenNamed), quicklink.name),
                message: String(
                    format: settings.text(QuicklinksKey.errorAppMissing), name), symbol: symbol,
                recovery: settings.text(QuicklinksKey.errorOpenWithDefault))
        else { return }
        performQuicklinkOpen(quicklink, link: link, forcingDefaultApp: true)
    }

    /// 通过系统查询把 bundle ID 解析为应用显示名，查不到时返回 nil。
    private func applicationName(forBundleID bundleID: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .flatMap { FileManager.default.displayName(atPath: $0.path) }
    }

    // MARK: - Library

    /// 新增快捷链接并返回入库后的条目。
    @discardableResult
    func addQuicklink(_ draft: Quicklink) throws -> Quicklink {
        try store.add(draft)
    }

    /// 用草稿内容覆盖更新已有快捷链接。
    func updateQuicklink(_ draft: Quicklink) throws {
        try store.update(draft)
    }

    /// 删除链接并清理所有引用；`confirming: false` 供已经询问过的设置面板使用。
    func deleteQuicklink(id: UUID, confirming: Bool = true) async {
        guard let quicklink = store.quicklink(id: id) else { return }
        if confirming, settings.quicklinkConfirmsBeforeDelete {
            guard
                await core.confirm(
                    title: String(
                        format: settings.text(QuicklinksKey.deleteTitle), quicklink.name),
                    message: settings.text(QuicklinksKey.deleteMessage),
                    symbol: quicklink.iconSymbol ?? Quicklink.sfSymbol,
                    confirmTitle: settings.text(QuicklinksKey.deleteAction))
            else { return }
        }
        // 只在行确实删除后才做解绑：删除失败不能留下悬空引用。
        do {
            try store.remove(id: id)
        } catch {
            await core.showNotice(
                title: String(
                    format: settings.text(QuicklinksKey.errorDeleteNamed), quicklink.name),
                message: (error as? QuicklinkError)?.message(settings.language)
                    ?? error.localizedDescription,
                symbol: quicklink.iconSymbol ?? Quicklink.sfSymbol, tone: .danger)
            return
        }
        removeQuicklinkReferences(ids: [id], entryIDs: [quicklink.entryID])
    }

    /// 切换该链接的置顶状态。
    func toggleQuicklinkPinned(id: UUID) {
        do { try store.togglePinned(id: id) } catch { report(error) }
    }

    /// 设置该链接是否出现在根搜索列表中。
    func setQuicklinkShowsInRootSearch(_ shows: Bool, id: UUID) {
        do { try store.setShowsInRootSearch(shows, id: id) } catch { report(error) }
    }

    /// 保留该行及其快捷键，但将其从所有能触发打开的入口中移除。
    func setQuicklinkEnabled(_ enabled: Bool, id: UUID) {
        do { try store.setEnabled(enabled, id: id) } catch { report(error) }
    }

    /// 复制一份该链接（名称等由 Store 去重处理）。
    func duplicateQuicklink(id: UUID) {
        do { _ = try store.duplicate(id: id) } catch { report(error) }
    }

    /// 快捷链接是用户创作的数据，因此写入被拒时要明确报错，而不是呈现为无操作。
    private func report(_ error: QuicklinkError) {
        Task {
            await core.showNotice(
                title: settings.text(QuicklinksKey.errorSaveChange),
                message: error.message(settings.language),
                symbol: Quicklink.sfSymbol, tone: .danger)
        }
    }

    /// 打开快捷链接设置面板并让编辑器展示 `quicklink`；传 nil 表示新建。
    func editQuicklink(_ quicklink: Quicklink?) {
        core.pendingQuicklinkEdit = QuicklinkEditRequest(quicklink: quicklink)
        settingsCoordinator.showSettings(tab: .quicklinks)
    }

    /// 用传入列表整体替换链接库，并清理被移除条目的所有引用；返回实际写入的条数。
    @discardableResult
    func replaceQuicklinks(_ incoming: [Quicklink]) -> Int {
        let previous = store.quicklinks
        let count = store.replace(with: incoming)
        let liveIDs = Set(store.quicklinks.map(\.id))
        let removed = previous.filter { !liveIDs.contains($0.id) }
        removeQuicklinkReferences(
            ids: Set(removed.map(\.id)), entryIDs: Set(removed.map(\.entryID)))
        return count
    }

    /// 清除这批条目在各处的引用：快捷键绑定、收藏位、可见性、别名与学习排序。
    private func removeQuicklinkReferences(ids: Set<UUID>, entryIDs: Set<String>) {
        for id in ids {
            let action = HotKeyAction.quicklink(id: id)
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

    // MARK: - Import & export

    /// 将链接库导出为 JSON 文件；库为空时给出提示而不是弹保存面板。
    func exportQuicklinks() async {
        guard !store.quicklinks.isEmpty else {
            await core.showNotice(
                title: settings.text(QuicklinksKey.exportNothing),
                message: settings.text(QuicklinksKey.exportNothingMessage),
                symbol: Quicklink.sfSymbol, tone: .neutral)
            return
        }
        guard let url = BackupActions.chooseSaveLocation(named: "GearMac-Quicklinks") else {
            return
        }
        do {
            try QuicklinkArchive.encode(store.quicklinks).write(to: url, options: .atomic)
            core.showMessage(
                String(
                    format: settings.text(QuicklinksKey.exportDone), store.quicklinks.count))
        } catch {
            await core.showNotice(
                title: settings.text(QuicklinksKey.exportFailed),
                message: error.localizedDescription,
                symbol: Quicklink.sfSymbol, tone: .danger)
        }
    }

    /// 按「设置 → 导入」的规则合并进链接库，使 Raycast 与 JSON 导入共用同一套合并逻辑。
    @discardableResult
    func addImportedQuicklinks(_ incoming: [Quicklink]) -> [Quicklink] {
        let merge = QuicklinkArchive.merge(incoming, into: store.quicklinks)
        return store.append(merge.additions)
    }

    /// 选择 JSON 文件并导入，按合并结果给出成功/无新增/失败三类提示。
    func importQuicklinks() async {
        guard let url = BackupActions.chooseJSONFile() else { return }
        do {
            let incoming = try QuicklinkArchive.decode(Data(contentsOf: url))
            let added = addImportedQuicklinks(incoming)
            // 文件中提供的条目都已存在，因此明确提示，而不是显示「导入 0 条」。
            guard !added.isEmpty else {
                await core.showNotice(
                    title: settings.text(QuicklinksKey.importNothing),
                    message: settings.text(QuicklinksKey.importNothingMessage),
                    symbol: Quicklink.sfSymbol, tone: .neutral)
                return
            }
            let skipped = incoming.count - added.count
            let summary =
                skipped == 0
                ? String(
                    format: settings.text(QuicklinksKey.importSummary), added.count)
                : String(
                    format: settings.text(QuicklinksKey.importSummarySkipped), added.count, skipped)
            await core.showNotice(
                title: settings.text(QuicklinksKey.importDone), message: summary,
                symbol: Quicklink.sfSymbol, tone: .success)
        } catch {
            await core.showNotice(
                title: settings.text(QuicklinksKey.importFailed),
                message: (error as? QuicklinkArchive.ArchiveError)?.message(settings.language)
                    ?? error.localizedDescription,
                symbol: Quicklink.sfSymbol, tone: .danger)
        }
    }
}
