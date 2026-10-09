// 文件职责：自定义命令的协调器：管理命令库、唯一的运行入口（含参数补全与确认门）、输出窗口与删除时的引用清理。
// 分层：Coordinator；@MainActor，所有状态变更都在主 actor 上进行，命令执行经 ShellCommandRunner 异步完成。
import AppKit

/// 掌管自定义命令：命令库、唯一的运行入口及其各道门槛，以及删除时的引用清理。
@MainActor
final class CustomCommandCoordinator {
    private let store: CustomCommandStore
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let paletteCoordinator: PaletteCoordinator
    private let settingsCoordinator: SettingsCoordinator
    private let hotKeys: HotKeyManager
    private let favorites: FavoritesStore
    private let visibility: VisibilityStore
    private let ranking: LauncherRankingStore
    private let aliases: AliasStore
    /// 只用于弹窗与消息 HUD 展示，绝不用于持有本类型自己的状态。
    private unowned let core: AppCore
    /// 首次使用时构建；其中的窗口会等到确有输出需要展示的运行才弹出。
    private lazy var outputPresenter = CommandOutputPresenter(
        settings: settings,
        activation: activationPolicy,
        rerun: { [unowned self] in self.rerunOutput(id: $0) },
        stop: { [unowned self] in self.stopOutputRun(id: $0) },
        openSettings: { [unowned self] in self.settingsCoordinator.showSettings(tab: .commands) })
    private let activationPolicy: ActivationPolicy
    /// 被新运行取代时不会碰它——只有停止按钮才会真正结束命令。
    private var liveRun: (id: UUID, stop: @Sendable () -> Void)?
    /// 最近一次兜底 shell 命令行；它不在命令库中，窗口的 Rerun 找不到对应条目。
    private var lastShellCommand: (id: UUID, text: String)?

    /// 注入命令库、设置、索引与各协作者；`core` 仅用于弹窗展示。
    init(
        store: CustomCommandStore,
        settings: AppSettings,
        appIndex: AppIndex,
        paletteCoordinator: PaletteCoordinator,
        settingsCoordinator: SettingsCoordinator,
        hotKeys: HotKeyManager,
        favorites: FavoritesStore,
        visibility: VisibilityStore,
        ranking: LauncherRankingStore,
        aliases: AliasStore,
        activationPolicy: ActivationPolicy,
        core: AppCore
    ) {
        self.store = store
        self.settings = settings
        self.appIndex = appIndex
        self.paletteCoordinator = paletteCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.hotKeys = hotKeys
        self.favorites = favorites
        self.visibility = visibility
        self.ranking = ranking
        self.aliases = aliases
        self.activationPolicy = activationPolicy
        self.core = core
    }

    // MARK: - Feature presence

    /// 按「启用 + 在启动器中显示」两个开关决定是否把命令列表注册进索引。
    func applyCustomCommandsPresence() {
        let visible = settings.customCommandsEnabled && settings.customCommandsShowInLauncher
        appIndex.setCustomCommands(visible ? store.commands : [])
    }

    // MARK: - Library

    /// 新增一条自定义命令。
    @discardableResult
    func addCustomCommand(_ draft: CustomCommand) throws -> CustomCommand {
        try store.add(draft)
    }

    /// 更新一条已存在的自定义命令。
    func updateCustomCommand(_ draft: CustomCommand) throws {
        try store.update(draft)
    }

    /// 保留命令及其快捷键，但把它从所有能够运行它的入口中撤下。
    func setCustomCommandEnabled(_ enabled: Bool, id: UUID) {
        store.setEnabled(enabled, id: id)
    }

    /// 删除命令，并清理它在快捷键、收藏、可见性、别名与排序中留下的引用。
    func deleteCustomCommand(id: UUID) {
        guard let command = store.command(id: id) else { return }
        removeCustomCommandReferences(ids: [id], entryIDs: [command.entryID])
        store.remove(id: id)
    }

    /// 整体替换命令集（备份导入），并清理已消失命令的引用，返回保留的条数。
    @discardableResult
    func replaceCustomCommands(_ commands: [CustomCommand]) -> Int {
        let previous = Dictionary(uniqueKeysWithValues: store.commands.map { ($0.id, $0) })
        let count = store.replace(with: commands)
        let liveIDs = Set(store.commands.map(\.id))
        let removed = Set(previous.keys).subtracting(liveIDs)
        let removedEntryIDs = Set(removed.compactMap { previous[$0]?.entryID })
        removeCustomCommandReferences(ids: removed, entryIDs: removedEntryIDs)
        return count
    }

    // MARK: - Importing

    /// 导入一个目录下的 Raycast 脚本命令，跳过命令库中已存在的同名项。
    func importScriptDirectory() async {
        guard let directory = chooseScriptDirectory() else { return }
        let drafts = await Task.detached(priority: .userInitiated) {
            RaycastScriptImport.scan(directory: directory)
        }.value
        guard !drafts.isEmpty else {
            await core.showNotice(
                title: settings.text(CustomCommandsKey.importNothing),
                message: settings.text(CustomCommandsKey.importNoneFound),
                symbol: CustomCommand.sfSymbol, tone: .neutral)
            return
        }
        guard await confirmScriptImport(count: drafts.count) else { return }
        let added = store.add(contentsOf: drafts)
        // 待导入的项全部已存在，于是明确说明，而不是报「导入 0 条」。
        guard added > 0 else {
            await core.showNotice(
                title: settings.text(CustomCommandsKey.importNothing),
                message: settings.text(CustomCommandsKey.importAllPresent),
                symbol: CustomCommand.sfSymbol, tone: .neutral)
            return
        }
        await core.showNotice(
            title: settings.text(CustomCommandsKey.importDone),
            message: importSummary(added: added, offered: drafts.count),
            symbol: CustomCommand.sfSymbol, tone: .success)
    }

    /// 配件型应用必须先激活，否则面板会开在最前应用之后。
    private func chooseScriptDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = settings.text(CustomCommandsKey.importPanelPrompt)
        panel.message = settings.text(CustomCommandsKey.importPanelMessage)
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// 脚本会执行任意代码，因此这里的警告力度与导入自定义命令备份一致。
    private func confirmScriptImport(count: Int) async -> Bool {
        await core.confirm(
            title: count == 1
                ? settings.text(CustomCommandsKey.importConfirmOne)
                : String(format: settings.text(CustomCommandsKey.importConfirmMany), count),
            message: settings.text(CustomCommandsKey.importConfirmMessage),
            symbol: CustomCommand.sfSymbol,
            confirmTitle: settings.text(CustomCommandsKey.importConfirmAction),
            confirmRole: .standard)
    }

    /// 生成导入结果文案，有跳过项时附带说明跳过的数量。
    private func importSummary(added: Int, offered: Int) -> String {
        let imported =
            added == 1
            ? settings.text(CustomCommandsKey.importSummaryOne)
            : String(format: settings.text(CustomCommandsKey.importSummaryMany), added)
        guard offered > added else { return imported }
        return imported
            + String(
                format: settings.text(CustomCommandsKey.importSummarySkipped), offered - added)
    }

    // MARK: - Running

    /// 唯一的运行入口，确保任何调用路径都不会绕过必填参数与确认步骤。
    func runCustomCommand(id: UUID, values: [String: String] = [:]) {
        // 这里同时也是功能开关：关闭后，即使已注册的快捷键也必须什么都不执行。
        guard settings.customCommandsEnabled else { return }
        guard let command = store.command(id: id), command.isEnabled else { return }
        guard let arguments = command.positionalValues(from: values) else {
            paletteCoordinator.showArguments(of: AppEntry(command), values: values)
            return
        }
        perform(command, arguments: arguments)
    }

    /// 启动器兜底：一次性的 shell 命令行，流式写入所有运行共用的那个窗口。
    func runShellCommand(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        // 会加载其 shell 配置：有人在启动器里输入 `ll`，指的正是他自己的别名。
        // 不指定工作目录，运行器将其理解为用户主目录——对启动器而言这是唯一合理的 cwd。
        let command = CustomCommand(
            name: CommandID.runShellCommand.name, command: text, loadsShellEnvironment: true,
            showsOutput: true)
        lastShellCommand = (command.id, text)
        Task { await streamOutput(of: command, arguments: []) }
    }

    /// 窗口的 Rerun。临时 shell 命令行不在命令库中，因此在这里重放。
    private func rerunOutput(id: UUID) {
        guard let last = lastShellCommand, last.id == id else { return runCustomCommand(id: id) }
        runShellCommand(last.text)
    }

    /// 命令运行期间点击 Dock 图标应归给它的输出窗口，而不是新开一个启动器。
    func focusOutputWindow() -> Bool {
        outputPresenter.focusExisting()
    }

    /// 执行命令：按需先确认，再选择流式（展示输出）或批式（仅报告结果）路径。
    private func perform(_ command: CustomCommand, arguments: [String]) {
        guard settings.customCommandsEnabled else { return }
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        Task {
            if command.requiresConfirmation {
                guard
                    // 用中性而非破坏性样式：用户自己的命令只是想要再点一次确认。
                    await core.confirm(
                        title: command.name,
                        message: String(
                            format: settings.text(CustomCommandsKey.runConfirmMessage),
                            command.command),
                        symbol: command.symbol,
                        confirmTitle: settings.text(CustomCommandsKey.runConfirmAction),
                        tone: .neutral, confirmRole: .standard)
                else { return }
            }
            guard !command.showsOutput else {
                await streamOutput(of: command, arguments: arguments)
                return
            }
            let result = await ShellCommandRunner.run(
                command.command, arguments: arguments,
                loadingShellEnvironment: command.loadsShellEnvironment,
                workingDirectory: command.workingDirectory)
            await report(command, result: result)
        }
    }

    /// 在第一个字节之前就打开窗口，让耗时命令在运行过程中始终可见。
    private func streamOutput(of command: CustomCommand, arguments: [String]) async {
        let session = ShellCommandRunner.stream(
            command.command, arguments: arguments,
            loadingShellEnvironment: command.loadsShellEnvironment,
            workingDirectory: command.workingDirectory)
        let runID = outputPresenter.begin(
            commandID: command.id, name: command.name, commandText: command.command,
            symbol: command.symbol)
        liveRun = (runID, session.stop)
        defer { if liveRun?.id == runID { liveRun = nil } }

        for await event in session.events {
            switch event {
            case .output(let text):
                outputPresenter.append(text, to: runID)
            case .finished(let result):
                outputPresenter.finish(
                    CommandOutcome(
                        summary: summary(of: result),
                        hint: shellEnvironmentHint(command: command, result: result),
                        succeeded: result.succeeded, finishedAt: Date()),
                    for: runID)
            }
        }
    }

    /// 停止指定运行的命令（仅当它正是当前 liveRun 时）。
    private func stopOutputRun(id: UUID) {
        guard let liveRun, liveRun.id == id else { return }
        liveRun.stop()
    }

    /// 清理被删除命令在各存储中留下的引用：快捷键、收藏、可见性、别名与排序。
    private func removeCustomCommandReferences(ids: Set<UUID>, entryIDs: Set<String>) {
        for id in ids {
            let action = HotKeyAction.customCommand(id: id)
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

    // MARK: - Reporting

    /// 已经在窗口里展示过结局的运行，不应再弹一次对话框重复说明。
    private func report(_ command: CustomCommand, result: ShellCommandResult) async {
        guard !result.succeeded else {
            // 命令自己输出的内容胜过一句干巴巴的「已运行」；在完成时才报，慢命令因此报得晚。
            if command.showsConfirmation {
                core.showMessage(
                    result.lastOutputLine
                        ?? String(
                            format: settings.text(CustomCommandsKey.reportRan), command.name))
            }
            return
        }
        let hint = shellEnvironmentHint(command: command, result: result)
        guard
            await core.reportFailure(
                title: String(
                    format: settings.text(CustomCommandsKey.reportFailedTitle), command.name),
                message: failureMessage(command: command, result: result),
                symbol: command.symbol,
                recovery: hint == nil ? nil : settings.text(CustomCommandsKey.reportOpenSettings))
        else { return }
        settingsCoordinator.showSettings(tab: .commands)
    }

    /// 把结束状态转成一句话摘要。
    private func summary(of result: ShellCommandResult) -> String {
        switch result.termination {
        case .launchFailed:
            return settings.text(CustomCommandsKey.summaryShellFailed)
        case .stopped: return settings.text(CustomCommandsKey.summaryStopped)
        case .exited(let status):
            return status == 0
                ? settings.text(CustomCommandsKey.summaryFinished)
                : String(format: settings.text(CustomCommandsKey.summaryExited), status)
        }
    }

    /// 拼接失败信息：摘要、启动失败详情、stderr 与环境提示。
    private func failureMessage(command: CustomCommand, result: ShellCommandResult) -> String {
        var parts = [summary(of: result)]
        if case .launchFailed(let detail) = result.termination { parts.append(detail) }
        if let standardError = result.standardError { parts.append(standardError) }
        if let hint = shellEnvironmentHint(command: command, result: result) { parts.append(hint) }
        return parts.joined(separator: "\n\n")
    }

    /// `127` 也可能只是拼错命令，因此这里依据退出状态而非 stderr 来判断。
    private func shellEnvironmentHint(
        command: CustomCommand, result: ShellCommandResult
    ) -> String? {
        guard case .exited(status: 127) = result.termination, !command.loadsShellEnvironment else {
            return nil
        }
        return settings.text(CustomCommandsKey.shellEnvHint)
    }
}
