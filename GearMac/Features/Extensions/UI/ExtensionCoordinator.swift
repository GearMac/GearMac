// 文件职责：扩展命令与 Palette 之间的协调层：负责启动/退出命令、启用开关、卸载/清理确认、深链解析，以及扩展可调用的宿主回调。
// 分层：Coordinator；不直接操作窗口，所有窗口交互都经 PaletteCoordinator/AppCore。
import AppKit

/// 命令与 Palette 的衔接点：启动、退出，以及命令可调用的宿主回调。
@MainActor
final class ExtensionCoordinator {
    private let extensions: ExtensionManager
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    private let settings: AppSettings
    /// 仅用于消息 HUD 的展示——绝不用于本类型自己持有的状态。
    private unowned let core: AppCore

    /// 注入扩展管理器、Palette、设置协调器与 AppCore 等依赖。
    init(
        extensions: ExtensionManager,
        palette: PaletteState,
        paletteCoordinator: PaletteCoordinator,
        settingsCoordinator: SettingsCoordinator,
        settings: AppSettings,
        core: AppCore
    ) {
        self.extensions = extensions
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.settings = settings
        self.core = core
    }

    // MARK: - Feature presence

    /// 按当前开关状态应用两项设置——启动时，以及备份导入改变它们之后。
    func applyEnabled() {
        extensions.setShowsInLauncher(settings.extensionsShowInLauncher)
        Task { await extensions.setEnabled(settings.extensionsEnabled) }
    }

    /// 同时征得运行第三方 JavaScript 的同意，因此在启动前先询问。
    func setExtensionsEnabled(_ enabled: Bool) {
        guard enabled != settings.extensionsEnabled else { return }
        guard enabled else {
            settings.extensionsEnabled = false
            Task { await extensions.setEnabled(false) }
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        Task {
            guard
                await core.confirm(
                    title: "Enable extensions?",
                    message:
                        "Extensions are third-party JavaScript, run on this Mac. A running command "
                        + "holds a JavaScript engine in memory until you leave it — expect GearMac "
                        + "to use noticeably more RAM while one is open.",
                    symbol: "puzzlepiece.extension", confirmTitle: "Enable", tone: .neutral,
                    confirmRole: .standard)
            else { return }

            settings.extensionsEnabled = true
            await extensions.setEnabled(true)
        }
    }

    /// 按设置应用扩展在启动器中是否显示。
    func applyExtensionsLauncherPresence() {
        extensions.setShowsInLauncher(settings.extensionsShowInLauncher)
    }

    /// 从已安装集合解析：启动器可能从未被打开过。
    func runExtensionCommand(entryID: String) {
        guard settings.extensionsEnabled,
            let entry = extensions.launcherEntry(forEntryID: entryID)
        else { return }
        // 再次按快捷键会关闭该命令，与模式命令的行为一致。
        if paletteCoordinator.isShowing(.extensionCommand),
            extensions.running == ExtensionCommandRef(entryID: entryID)
        {
            paletteCoordinator.hidePalette()
            return
        }
        runExtensionCommand(entry)
    }

    /// `raycast://extensions/…` 链接：按 slug 运行启动器会运行的同一个命令。
    func runDeepLink(_ link: ExtensionDeepLink) {
        guard settings.extensionsEnabled else {
            core.showMessage("Extensions are disabled — enable them in Settings", tone: .danger)
            return
        }
        guard let (owner, command) = extensions.resolve(link) else {
            core.showMessage("No installed extension provides '\(link.commandName)'", tone: .danger)
            return
        }
        run(
            owner, command: command, arguments: link.arguments, fallbackText: link.fallbackText,
            launchType: link.launchType)
    }

    // MARK: - Managing one extension from the launcher

    /// 打开设置并定位到启动器某行所属的扩展。
    func showExtensionSettings(for app: AppEntry) {
        guard let (owner, _) = extensions.resolve(app) else { return }
        showExtensionSettings(for: owner)
    }

    /// 对话框出现前先隐藏 Palette：它悬浮在上层，其后的 sheet 无法操作。
    func confirmUninstall(_ app: AppEntry) {
        guard let (owner, _) = extensions.resolve(app) else { return }
        confirmUninstall(owner)
    }

    func confirmUninstall(_ owner: InstalledExtension) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        NSApp.activate(ignoringOtherApps: true)
        Task {
            guard
                await core.confirm(
                    title: "Uninstall \(owner.title)?",
                    message:
                        "Removes the extension and everything it stored — its preferences, its cache "
                        + "and its own files. Its commands leave the launcher.",
                    symbol: "trash", confirmTitle: "Uninstall")
            else { return }
            await extensions.uninstall(owner)
        }
    }

    /// 破坏性操作：遗留的 support 目录属于扩展自身文件，因此先询问。
    func confirmCleanup(_ report: ExtensionCleanup.Report) async {
        guard !report.isEmpty else { return }
        let size = ExtensionCleanup.formatted(bytes: report.bytes)
        guard
            await core.confirm(
                title: "Clean up \(size)?",
                message:
                    "Removes build files left by an interrupted install, and the storage of "
                    + "extensions that are no longer installed. Installed extensions are untouched.",
                symbol: "trash", confirmTitle: "Clean Up")
        else { return }

        let installed = Set(extensions.installed.map(\.manifest.name))
        let roots = ExtensionCleanup.defaultRoots()
        let freed = await Task.detached(priority: .userInitiated) {
            ExtensionCleanup.clean(installed: installed, in: roots)
        }.value
        core.showMessage(
            freed.isEmpty
                ? "Nothing to clean up" : "Reclaimed \(ExtensionCleanup.formatted(bytes: freed.bytes))")
    }

    /// 索引不会清理的部分：若保留下来，会让快捷键或排名指向已消失的命令。
    func removeExtensionReferences(entryIDs: [String]) {
        for entryID in entryIDs {
            let action = HotKeyAction.extensionCommand(entryID: entryID)
            if core.hotKeys.recordingAction == action { core.hotKeys.recordingAction = nil }
            core.hotKeys.setBinding(nil, for: action)
            core.launcherRanking.reset(itemKey: entryID)
        }
        core.favorites.remove(keys: Set(entryIDs))
        core.visibility.removeItemKeys(Set(entryIDs))
        core.aliases.removeKeys(Set(entryIDs))
    }

    /// view 命令接管 Palette；no-view 命令则关闭 Palette 并静默运行。
    func runExtensionCommand(
        _ app: AppEntry, arguments: [String: String] = [:], fallbackText: String? = nil,
        launchType: ExtensionLaunchType = .userInitiated,
        launchContext: [String: RenderValue] = [:]
    ) {
        guard let (owner, command) = extensions.resolve(app) else { return }
        run(
            owner, command: command, arguments: arguments, fallbackText: fallbackText,
            launchType: launchType, launchContext: launchContext)
    }

    private func run(
        _ owner: InstalledExtension, command: ExtensionCommand, arguments: [String: String],
        fallbackText: String? = nil, launchType: ExtensionLaunchType = .userInitiated,
        launchContext: [String: RenderValue] = [:]
    ) {
        switch command.mode {
        case .view:
            // 先切换 Palette，使用户看到的是启动中的状态。
            paletteCoordinator.navigate(to: .extensionCommand)
            // 快捷键可能在被隐藏时触发，此时 view 命令无处渲染。
            if !paletteCoordinator.isVisible {
                paletteCoordinator.showPalette(mode: .extensionCommand)
            }
            if let fallbackText, !fallbackText.isEmpty { palette.query = fallbackText }
        case .noView, .menuBar:
            // no-view 命令自身的 HUD 就是反馈，因此让 Palette 避让。
            if launchType == .userInitiated { paletteCoordinator.hidePalette(restoreFocus: false) }
        }
        Task {
            await extensions.run(
                owner, command: command, arguments: arguments, fallbackText: fallbackText,
                launchType: launchType, launchContext: launchContext)
        }
    }

    /// 查询某菜单栏命令是否已启用。
    func menuBarIsEnabled(_ reference: ExtensionCommandRef) -> Bool {
        extensions.menuBarIsEnabled(reference)
    }

    /// 启用或停用某菜单栏命令。
    func setMenuBarEnabled(_ enabled: Bool, reference: ExtensionCommandRef) {
        extensions.setMenuBarEnabled(enabled, reference: reference)
    }

    /// 某行声明的参数；为 nil 或空时决定表头是否显示内联输入框。
    func commandArguments(for entry: AppEntry?) -> [ExtensionCommandArgument]? {
        guard let entry, entry.kind == .extensionCommand,
            let (_, command) = extensions.resolve(entry), !command.arguments.isEmpty
        else { return nil }
        return command.arguments
    }

    /// 在空搜索框中按 Escape：先弹出扩展自身的导航栈，再退出命令。
    func exitExtensionScreen() {
        Task {
            if await extensions.popNavigation() { return }
            await extensions.stop()
            if !palette.pop() { paletteCoordinator.hidePalette() }
        }
    }

    /// 来自扩展的 `popToRoot()`——回到全新的根搜索，并拆除命令。
    func popExtensionToRoot() {
        Task {
            await extensions.stop()
            palette.prepare(mode: .launcher)
        }
    }

    /// 打开设置并定位到指定扩展。
    func showExtensionSettings(for owner: InstalledExtension) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        settingsCoordinator.showSettings(
            tab: .extensions, revealing: .row(.extensionsInstalled, owner.manifest.name))
    }

    // MARK: - Host callbacks, routed here so the manager never touches a window itself

    /// 与剪贴板和 emoji 粘贴路径使用相同的记录目标。
    var pasteTarget: NSRunningApplication? { paletteCoordinator.targetApp }

    /// `getApplications()` 报告启动器自身索引的内容，从而使二者不会不一致。
    var applicationURLs: [URL] { SearchScopes.appBundles(in: settings.searchScopes) }

    /// Palette 在屏时返回 true——此时吐司才有地方渲染。
    var isPaletteVisible: Bool { paletteCoordinator.isVisible }

    /// OAuth 授权流程正在等待回调时返回 true。
    var isAuthorizing: Bool { extensions.isAuthorizing }

    /// 宿主回调：隐藏 Palette。
    func closeMainWindow() {
        paletteCoordinator.hidePalette(restoreFocus: false)
    }

    /// 宿主回调：重新显示 Palette，并按是否有运行中的命令选择模式。
    func reopenPalette(hasRunningCommand: Bool) {
        paletteCoordinator.showPalette(
            mode: hasRunningCommand ? .extensionCommand : .launcher, restoreAnyMode: true)
    }

    /// 宿主回调：清空搜索框。
    func clearSearchBar() {
        palette.query = ""
    }

    /// 使用独立窗口：no-view 命令会在提示条结束前就关闭 Palette。
    func showHUD(_ message: String) {
        core.showMessage(message)
    }

    /// 对话框优先级高于 Palette，因此 view 命令的界面保留在其后方。
    func confirmExtensionAlert(_ alert: ExtensionAlert) async -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        return await core.confirm(
            title: alert.title, message: alert.message,
            symbol: alert.isDestructive ? "exclamationmark.triangle" : "questionmark.circle",
            confirmTitle: alert.primaryTitle,
            tone: alert.isDestructive ? .danger : .neutral,
            confirmRole: alert.isDestructive ? .destructive : .standard,
            dismissTitle: alert.dismissTitle)
    }
}
