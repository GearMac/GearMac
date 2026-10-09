// 文件职责：启动器激活的中枢：把面板中的一行分派到该条目类型对应的执行逻辑。
// 分层：Coordinator；持有各功能 Coordinator 与窗口控制器，仅备份类命令通过 AppCore 访问实时存储。
import AppKit

/// 负责启动器激活：从面板行到该条目类型所执行逻辑的唯一通道。
@MainActor
final class LauncherCoordinator {
    private let ranking: LauncherRankingStore
    private let windowController: PaletteWindowController
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    private let customCommandCoordinator: CustomCommandCoordinator
    private let systemActionCoordinator: SystemActionCoordinator
    private let quicklinkCoordinator: QuicklinkCoordinator
    private let windowCommandCoordinator: WindowCommandCoordinator
    private let windowLayoutCoordinator: WindowLayoutCoordinator
    private let snippetCoordinator: SnippetCoordinator
    private let fileSearchCoordinator: FileSearchCoordinator
    private let menuSearchCoordinator: MenuSearchCoordinator
    private let windowSwitchCoordinator: WindowSwitchCoordinator
    private let notesCoordinator: NotesCoordinator
    private let extensionCoordinator: ExtensionCoordinator
    private let calendarCoordinator: CalendarCoordinator
    /// 仅用于备份类命令；它们需要实时存储来收集数据并写回。
    private unowned let core: AppCore

    /// 注入启动器所需的各功能 Coordinator 与窗口控制器，并保留对 AppCore 的弱引用。
    init(
        ranking: LauncherRankingStore,
        windowController: PaletteWindowController,
        paletteCoordinator: PaletteCoordinator,
        settingsCoordinator: SettingsCoordinator,
        customCommandCoordinator: CustomCommandCoordinator,
        systemActionCoordinator: SystemActionCoordinator,
        quicklinkCoordinator: QuicklinkCoordinator,
        windowCommandCoordinator: WindowCommandCoordinator,
        windowLayoutCoordinator: WindowLayoutCoordinator,
        snippetCoordinator: SnippetCoordinator,
        fileSearchCoordinator: FileSearchCoordinator,
        menuSearchCoordinator: MenuSearchCoordinator,
        windowSwitchCoordinator: WindowSwitchCoordinator,
        notesCoordinator: NotesCoordinator,
        extensionCoordinator: ExtensionCoordinator,
        calendarCoordinator: CalendarCoordinator,
        core: AppCore
    ) {
        self.ranking = ranking
        self.windowController = windowController
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.customCommandCoordinator = customCommandCoordinator
        self.systemActionCoordinator = systemActionCoordinator
        self.quicklinkCoordinator = quicklinkCoordinator
        self.windowCommandCoordinator = windowCommandCoordinator
        self.windowLayoutCoordinator = windowLayoutCoordinator
        self.snippetCoordinator = snippetCoordinator
        self.fileSearchCoordinator = fileSearchCoordinator
        self.menuSearchCoordinator = menuSearchCoordinator
        self.windowSwitchCoordinator = windowSwitchCoordinator
        self.notesCoordinator = notesCoordinator
        self.extensionCoordinator = extensionCoordinator
        self.calendarCoordinator = calendarCoordinator
        self.core = core
    }

    // MARK: - Activation

    /// 启动器激活入口：按条目类型分派；查询驱动与视图类命令在面板隐藏前处理，其余先隐藏面板再执行。
    func launch(
        _ app: AppEntry, searchQuery: String? = nil, arguments: [String: String] = [:]
    ) {
        // 分类词不构成对该行的搜索输入：记录它会让该行被归到「s」之下。
        if !CommandCatalog.isQueryDriven(app) {
            let term = searchQuery.flatMap { AppEntry.Kind.named(by: $0) == nil ? $0 : nil }
            ranking.visit(itemKey: app.preferenceKey, query: term)
        }
        // 命令在面板隐藏前分派：切换模式的命令会让面板保持打开。
        if app.kind == .command {
            guard let id = CommandCatalog.command(for: app) else { return }
            // 查询驱动：只有该行知道输入文本解析出的 URL。
            if id == .openInBrowser {
                paletteCoordinator.hidePalette(restoreFocus: false)
                AppLauncher.open(app.url)
                return
            }
            runCommand(id)
            return
        }
        if app.kind == .quickAction {
            if let command = CommandCatalog.command(for: app) {
                runCommand(command)
                return
            }
            guard let id = CustomQuickAction.id(fromEntryID: app.id) else { return }
            core.quickActionCoordinator.run(id: id)
            return
        }
        if app.kind == .customCommand {
            guard let id = CustomCommand.id(fromEntryID: app.id) else { return }
            customCommandCoordinator.runCustomCommand(id: id, values: arguments)
            return
        }
        if app.kind == .systemAction {
            guard let action = SystemActionCatalog.action(forEntryID: app.id) else { return }
            systemActionCoordinator.runSystemAction(id: action.id)
            return
        }
        if app.kind == .windowCommand {
            if let command = WindowCommandCatalog.command(forEntryID: app.id) {
                windowCommandCoordinator.runWindowCommand(id: command.id)
                return
            }
            guard let id = CustomWindowSize.id(fromEntryID: app.id) else { return }
            windowCommandCoordinator.runCustomWindowSize(id: id)
            return
        }
        if app.kind == .windowRoom {
            // 由 Coordinator 自行隐藏面板：进入房间时不能先恢复焦点。
            guard let id = Room.id(fromEntryID: app.id) else { return }
            core.roomCoordinator.enterRoom(id: id)
            return
        }
        if app.kind == .windowLayout {
            // 由 Coordinator 自行隐藏面板：应用布局时不能先恢复焦点。
            guard let id = WindowLayout.id(fromEntryID: app.id) else { return }
            windowLayoutCoordinator.runWindowLayout(id: id)
            return
        }
        // 在面板隐藏前处理：视图类命令会接管面板而非将其关闭。
        if app.kind == .extensionCommand {
            extensionCoordinator.runExtensionCommand(app, arguments: arguments)
            return
        }
        if app.kind == .meeting {
            guard let id = MeetingEvent.id(fromEntryID: app.id) else { return }
            calendarCoordinator.activateMeeting(id: id)
            return
        }
        // 在面板隐藏前处理：未填写的快捷链接需要留在面板上先行询问。
        if app.kind == .quicklink {
            guard let id = Quicklink.id(fromEntryID: app.id) else { return }
            quicklinkCoordinator.openQuicklink(id: id, values: arguments)
            return
        }
        if app.kind == .appleShortcut {
            guard let id = AppleShortcut.id(fromEntryID: app.id) else { return }
            core.appleShortcutCoordinator.run(id: id)
            return
        }
        let previous = windowController.previousTarget
        paletteCoordinator.hidePalette(restoreFocus: false)
        switch app.kind {
        case .application:
            AppLauncher.launch(app.url)
        case .systemSettings:
            guard let bundleID = app.bundleID else { return }
            AppLauncher.openSettingsPane(bundleID: bundleID)
        case .snippet:
            guard let snippetID = StoredSnippet.id(fromEntryID: app.id) else { return }
            snippetCoordinator.expandSnippet(id: snippetID, target: previous)
        case .command, .quickAction, .customCommand, .systemAction, .windowCommand, .windowLayout,
            .windowRoom, .quicklink, .appleShortcut, .extensionCommand, .meeting:
            break  // 已在上方处理
        }
    }

    /// 内置命令运行的唯一通道：来自面板行或它的全局快捷键。
    func runCommand(_ id: CommandID) {
        switch id {
        case .quickAI:
            core.quickAICoordinator.show()
        case .aiChat:
            dismissPalette()
            core.aiChatCoordinator.toggleWindow()
        case .fixGrammar:
            core.quickActionCoordinator.run(.fixGrammar)
        case .rewrite:
            core.quickActionCoordinator.run(.rewrite)
        case .translate:
            core.quickActionCoordinator.run(.translate)
        case .summarize:
            core.quickActionCoordinator.run(.summarize)
        case .decide:
            core.quickActionCoordinator.run(.decide)
        case .calculatorHistory:
            paletteCoordinator.togglePalette(mode: .calculatorHistory)
        case .clipboardHistory:
            paletteCoordinator.togglePalette(mode: .clipboard)
        case .pasteSequentially:
            core.clipboardCoordinator.pasteNextInSequence()
        case .searchEmoji:
            paletteCoordinator.togglePalette(mode: .emoji)
        case .searchFiles:
            fileSearchCoordinator.show()
        case .searchMenuItems:
            menuSearchCoordinator.show()
        case .switchWindows:
            windowSwitchCoordinator.show()
        case .openCamera:
            dismissPalette()
            Task { await core.cameraCoordinator.show() }
        case .define:
            core.dictionaryCoordinator.show()
        case .openInBrowser, .runShellCommand:
            break  // 查询驱动：它们各在输入文本处运行，从不经过此通道。
        case .joinNextMeeting:
            calendarCoordinator.joinNextMeeting()
        case .copyMeetingLink:
            calendarCoordinator.copyNextMeetingLink()
        case .mySchedule:
            calendarCoordinator.showSchedule()
        case .openInCalendar:
            calendarCoordinator.openNextMeetingInCalendar()
        case .createEvent:
            calendarCoordinator.createEvent()
        case .showNotes:
            dismissPalette()
            notesCoordinator.toggle()
        case .createNote:
            dismissPalette()
            notesCoordinator.createNote()
        case .searchNotes:
            dismissPalette()
            notesCoordinator.searchNotes()
        case .searchQuicklinks:
            paletteCoordinator.togglePalette(mode: .quicklinks)
        case .searchSnippets:
            snippetCoordinator.showSnippets()
        case .createSnippet:
            dismissPalette()
            snippetCoordinator.editSnippet(nil)
        case .createWindowLayout:
            dismissPalette()
            windowLayoutCoordinator.editWindowLayout(nil)
        case .captureWindowLayout:
            dismissPalette()
            windowLayoutCoordinator.captureWindowLayout()
        case .switchRoom:
            core.roomCoordinator.showRooms()
        case .createRoom:
            core.roomCoordinator.createRoom()
        case .createQuicklink:
            dismissPalette()
            quicklinkCoordinator.editQuicklink(nil)
        case .importQuicklinks:
            dismissPalette()
            Task { await quicklinkCoordinator.importQuicklinks() }
        case .exportQuicklinks:
            dismissPalette()
            Task { await quicklinkCoordinator.exportQuicklinks() }
        case .exportSettings:
            dismissPalette()
            Task { await BackupActions.runExportCommand(core: core) }
        case .importSettings:
            dismissPalette()
            Task { await BackupActions.runImportCommand(core: core) }
        case .importFromRaycast:
            dismissPalette()
            settingsCoordinator.showBackupSettings()
        case .checkForUpdates:
            dismissPalette()
            core.updateCoordinator.checkForUpdates()
        case .settings:
            dismissPalette()
            settingsCoordinator.showSettings()
        case .about:
            dismissPalette()
            settingsCoordinator.showAbout()
        case .support:
            dismissPalette()
            core.supportCoordinator.showSupport()
        case .quit:
            NSApp.terminate(nil)
        }
    }

    /// 全局快捷键在无窗口打开时调用这些命令，此时直接隐藏也会重置面板状态。
    private func dismissPalette() {
        guard paletteCoordinator.isVisible else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
    }

    // MARK: - Row actions

    /// 重置该条目的启动器排序权重。
    func resetRanking(for app: AppEntry) {
        ranking.reset(itemKey: app.preferenceKey)
    }

    /// 隐藏面板并在 Finder 中显示该条目对应的文件。
    func showInFinder(_ app: AppEntry) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(app.url)
    }

    /// 焦点不回交：重启会接管它，或由拒绝关闭的应用持有。
    func restart(_ app: AppEntry) {
        guard app.kind == .application, let bundleID = app.bundleID else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        Task { await AppLauncher.restart(bundleID: bundleID, url: app.url) }
    }

    /// 退出条目对应的应用；应用未运行时为空操作（面板保持不动）。
    func quit(_ app: AppEntry, force: Bool = false) {
        guard app.kind == .application, let bundleID = app.bundleID else { return }
        // 此处没有任何操作会夺取焦点，因此除非该应用即将退出，否则把焦点交还。
        let quittingPreviousApp = windowController.previousApp?.bundleIdentifier == bundleID
        guard AppLauncher.quit(bundleID: bundleID, force: force) else { return }
        paletteCoordinator.hidePalette(restoreFocus: !quittingPreviousApp)
    }
}
