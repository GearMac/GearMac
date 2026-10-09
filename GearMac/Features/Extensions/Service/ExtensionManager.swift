// 文件职责：扩展功能的中央管理者，持有已安装扩展集合、扩展运行时与当前运行中的命令，负责安装/卸载/更新、启动命令、后台刷新调度、菜单栏项以及调色板会话状态。
// 分层：Service（@MainActor @Observable）；作为 ExtensionRuntimeDelegate 与 ExtensionHostContext 的实现方，桥接扩展运行时与 UI 层。
import AppKit
import Foundation

/// 调色板针对当前正在运行的命令所展示的状态。
enum ExtensionSessionState: Equatable {
    case idle
    case launching
    case rendered(RenderTree)
    case failed(String)
    /// 无界面（no-view）命令已执行完成。
    case finished
}

/// 持有已安装扩展集合、扩展运行时以及当前正在运行的命令。
@MainActor
@Observable
final class ExtensionManager: ExtensionRuntimeDelegate, ExtensionHostContext {
    private(set) var installed: [InstalledExtension] = []
    /// 商店中每个已安装扩展的更新版本（存在更新时才有值），以 manifest name 为键。
    private(set) var updates: [String: ExtensionListing] = [:]
    private(set) var updating: Set<String> = []
    private(set) var menuBars: ExtensionMenuBarManager?
    private(set) var state: ExtensionSessionState = .idle
    /// 当前会话处于活动状态的命令（若有）。
    private(set) var running: ExtensionCommandRef?
    /// 运行中命令请求展示的 toast，最新的一条在末尾。
    private(set) var toasts: [ExtensionToast] = []
    /// 扩展自身导航栈的深度；大于 1 表示按 Escape 应当出栈而不是关闭。
    private(set) var navigationDepth = 1
    /// 每个搜索栏下拉框的选择值，以节点为键，使被推入的页面各自保留自己的选择。
    private(set) var accessoryValues: [Int: String] = [:]

    /// 关闭时不扫描、不发布、不持有任何内容：该功能仅占用一个未使用的存储属性。
    private(set) var isEnabled = false
    /// 命令是否会进入启动器；与 `isEnabled` 相互独立。
    private(set) var showsInLauncher = true

    var isAuthorizing: Bool { oauthSession.isAuthorizing }

    let storage: ExtensionStorage
    /// 扩展作用域的状态，启动器与设置界面经由这里读取，用法同 `storage`。
    let appearances = ExtensionAppearanceStore()
    private let commandMetadata = ExtensionCommandMetadataStore(
        fileURL: ExtensionCatalog.commandMetadataFile())
    private let storeVersions = ExtensionVersionStore(fileURL: ExtensionCatalog.storeVersionsFile())
    @ObservationIgnored private let runtime: ExtensionRuntime
    @ObservationIgnored private let bridge: ExtensionHostBridge
    @ObservationIgnored private let oauthSession = ExtensionOAuthSession()
    @ObservationIgnored private weak var appIndex: AppIndex?
    @ObservationIgnored private weak var coordinator: ExtensionCoordinator?

    /// 卸载操作使其失效的 entry id 列表，供其他功能丢弃以它们为键的数据。
    @ObservationIgnored var onDidUninstall: (([String]) -> Void)?

    @ObservationIgnored private var sessionID: String?
    @ObservationIgnored private var backgroundSessionID: String?
    @ObservationIgnored private var backgroundRef: ExtensionCommandRef?
    @ObservationIgnored private var backgroundContinuation: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var backgroundFailure: String?
    @ObservationIgnored private var backgroundTask: Task<Void, Never>?
    @ObservationIgnored private var nextToastID = 1
    @ObservationIgnored private var lastOAuthExtensionName: String?

    /// 构建管理器：装配存储、宿主桥接与运行时，并把自身注册为桥接的 context。
    init(clipboardStore: ClipboardStore) {
        storage = ExtensionStorage(directory: ExtensionCatalog.storageDirectory())
        bridge = ExtensionHostBridge(clipboardStore: clipboardStore)
        runtime = ExtensionRuntime(hostAPI: bridge)
        bridge.context = self
    }

    /// 仅完成协作者的装配；是否执行扫描由 coordinator 决定。
    func start(appIndex: AppIndex, coordinator: ExtensionCoordinator) {
        self.appIndex = appIndex
        self.coordinator = coordinator
        runtime.setDelegate(self)
        // 不受 `isEnabled` 限制：无论功能是否开启，遗留的 workspace 都由我们负责清理。
        let temp = FileManager.default.temporaryDirectory
        Task.detached(priority: .utility) { ExtensionCleanup.sweepWorkspaces(in: temp) }
    }

    // MARK: - The switches

    /// 双向幂等，因此启动流程与开关走同一次调用。
    func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        guard enabled else {
            menuBars?.stop()
            menuBars = nil
            await stop()
            backgroundTask?.cancel()
            backgroundTask = nil
            installed = []
            appIndex?.setExtensionCommands([])
            return
        }
        if let coordinator {
            menuBars = ExtensionMenuBarManager(
                storage: storage,
                commandMetadata: commandMetadata,
                supportDirectory: ExtensionCatalog.supportRoot(),
                makeExecution: { [weak self, weak coordinator] owner, command, type in
                    guard let self, let coordinator else { return nil }
                    let host = ExtensionMenuBarHost(
                        owner: owner, command: command, launchType: type, storage: self.storage,
                        manager: self, coordinator: coordinator)
                    let bridge = self.bridge.scoped(to: host)
                    return .init(
                        runtime: ExtensionRuntime(
                            hostAPI: bridge,
                            priority: type == .background ? .utility : .userInitiated),
                        stop: {
                            host.stop()
                            bridge.context = nil
                        }, enableInteraction: { host.enableInteraction() })
                },
                onError: { [weak coordinator] message, owner, needsPreferences in
                    coordinator?.showHUD(message)
                    if needsPreferences { coordinator?.showExtensionSettings(for: owner) }
                })
        }
        await refresh()
        ensureBackgroundLoop()
    }

    /// 设置命令是否出现在启动器中，变化时重新发布启动器条目。
    func setShowsInLauncher(_ shows: Bool) {
        guard shows != showsInLauncher else { return }
        showsInLauncher = shows
        publishLauncherEntries()
    }

    // MARK: - Installed set

    /// 重新扫描已安装扩展；集合变化时重新发布启动器条目并重启后台循环。
    func refresh() async {
        guard isEnabled else { return }
        let found = await Task.detached(priority: .utility) { ExtensionCatalog.scan() }.value
        guard isEnabled else { return }
        if found != installed {
            installed = found
            publishLauncherEntries()
            restartBackgroundLoop()
        }
        menuBars?.synchronize(found)
    }

    func extensionNamed(_ name: String) -> InstalledExtension? {
        installed.first { $0.manifest.name == name }
    }

    /// 由已安装集合构造，而非依赖 `AppIndex`：快捷键可能在条目行尚未创建前就触发。
    func launcherEntry(forEntryID entryID: String) -> AppEntry? {
        guard let reference = ExtensionCommandRef(entryID: entryID),
            let owner = extensionNamed(reference.extensionName),
            let command = owner.command(named: reference.commandName)
        else { return nil }
        return entry(for: command, in: owner)
    }

    private func publishLauncherEntries() {
        guard isEnabled, showsInLauncher else {
            appIndex?.setExtensionCommands([])
            return
        }
        let entries =
            installed
            .flatMap { owner in owner.manifest.commands.map { entry(for: $0, in: owner) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        appIndex?.setExtensionCommands(entries)
    }

    /// 把单个命令表示为一个启动器条目；用户选择的外观会替换全部条目的内置图标。
    private func entry(for command: ExtensionCommand, in owner: InstalledExtension) -> AppEntry {
        let appearance = appearances.appearance(for: owner.manifest.name)
        let reference = ExtensionCommandRef(
            extensionName: owner.manifest.name, commandName: command.name)
        let metadata = commandMetadata.metadata(
            extension: owner.manifest.name, command: command.name)
        // 一旦 `interval` 被移除，即使存储的标志位仍是旧值，也一并取消刷新指示点。
        let schedulable = ExtensionRefreshPolicy.isSchedulable(
            mode: command.mode, interval: command.interval)
        return AppEntry(
            id: reference.entryID,
            name: command.title,
            url: owner.directory,
            bundleID: nil,
            kind: .extensionCommand,
            subtitle: ExtensionRefreshPolicy.displaySubtitle(
                manifest: command.subtitle, override: metadata.subtitle, ownerTitle: owner.title),
            backgroundRefresh: ExtensionRefreshPolicy.indicator(
                schedulable: schedulable, backgroundEnabled: metadata.backgroundEnabled,
                lastError: metadata.lastError),
            keywords: command.keywords,
            iconOverride: icon(for: command, in: owner, appearance: appearance),
            ownerName: owner.title, installedAt: owner.installedAt)
    }

    /// 持久化并立即重新发布，使用户当场看到条目变化，而不用等下一次扫描。
    func setAppearance(_ appearance: ExtensionAppearance?, for extensionName: String) {
        appearances.set(appearance, for: extensionName)
        publishLauncherEntries()
    }

    /// 用户外观优先，否则使用内置图标；启动器拿到的就是这个结果。
    private func icon(
        for command: ExtensionCommand, in owner: InstalledExtension,
        appearance: ExtensionAppearance?
    ) -> EntryIcon {
        if let appearance {
            return .tintedSymbol(name: appearance.symbol, tint: appearance.tint.symbolTint)
        }
        guard let path = commandIconPath(command, in: owner) ?? owner.iconPath else {
            return .symbol("puzzlepiece.extension")
        }
        return .artwork(path: path, extent: ExtensionIconCache.extent)
    }

    private func commandIconPath(_ command: ExtensionCommand, in owner: InstalledExtension) -> String? {
        guard let icon = command.icon else { return nil }
        let candidate = owner.directory.appendingPathComponent("assets").appendingPathComponent(icon)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate.path : nil
    }

    // MARK: - Install / uninstall

    func install(from source: URL) async throws {
        untrack(try ExtensionCatalog.install(from: source).manifest.name)
        await refresh()
    }

    /// 在主线程之外扫描：每个目录都要读取 manifest，而完整的 Raycast 安装有数十个扩展。
    func raycastImportCandidates() async -> [RaycastImportCandidate] {
        let candidates = await Task.detached(priority: .userInitiated) {
            ExtensionCatalog.importableFromRaycast()
        }.value
        let have = Set(installed.map(\.manifest.name))
        return candidates.map {
            RaycastImportCandidate(installed: $0, isInstalled: have.contains($0.manifest.name))
        }
    }

    func install(
        _ listing: ExtensionListing,
        onProgress: @Sendable @escaping (ExtensionInstaller.Progress) -> Void
    ) async throws {
        try await installFromStore(listing, onProgress: onProgress)
        await refresh()
    }

    /// 进度按步骤上报：从源码构建可能耗时数分钟。
    @discardableResult
    func install(
        _ source: ExtensionGitHubSource, packageManager: ExtensionPackageManager,
        additionalSearchPaths: [String],
        onProgress: @Sendable @escaping (ExtensionInstaller.Progress) -> Void
    ) async throws -> InstalledExtension {
        let installer = ExtensionInstaller(
            packageManager: packageManager, additionalSearchPaths: additionalSearchPaths)
        let installed = try await installer.install(source, onProgress: onProgress)
        untrack(installed.manifest.name)
        await refresh()
        return installed
    }

    /// 结束时统一刷新一次，并返回失败项，便于界面点名。
    @discardableResult
    func importAllFromRaycast(
        _ candidates: [InstalledExtension], onProgress: (Int) -> Void = { _ in }
    ) async -> [String] {
        var failed: [String] = []
        for (index, candidate) in candidates.enumerated() {
            do {
                let name = try ExtensionCatalog.install(from: candidate.directory).manifest.name
                storeVersions.record(nil, for: name)
                updates[name] = nil
            } catch {
                failed.append(candidate.title)
            }
            onProgress(index + 1)
        }
        await refresh()
        return failed
    }

    // MARK: - Updates

    /// 在设置界面打开时调用；查询失败的项直接跳过，不向上报告。
    func checkForUpdates() async {
        guard isEnabled else { return }
        let tracked = storeVersions.tracked
        let lookups = installed.map(\.manifest).filter { tracked.contains($0.name) }
        let client = ExtensionStoreClient()
        let latest = await withTaskGroup(of: ExtensionListing?.self) { group in
            for manifest in lookups {
                let (handle, name) = (manifest.storeHandle, manifest.name)
                group.addTask { try? await client.lookup(handle: handle, name: name) }
            }
            var found: [ExtensionListing] = []
            for await listing in group {
                if let listing { found.append(listing) }
            }
            return found
        }
        guard !Task.isCancelled else { return }
        updates = Dictionary(
            storeVersions.reconcile(with: latest).map { ($0.name, $0) }, uniquingKeysWith: { $1 })
    }

    /// 与导入一样逐个执行；返回失败的标题，便于界面点名。
    func update(_ names: [String]) async -> [String] {
        updating.formUnion(names)
        var failed: [String] = []
        for name in names {
            defer { updating.remove(name) }
            guard let listing = updates[name] else { continue }
            do {
                try await installFromStore(listing, onProgress: { _ in })
            } catch {
                failed.append(listing.title)
            }
        }
        await refresh()
        return failed
    }

    /// 仅替换扩展所在目录，因此其偏好设置与存储得以保留。
    private func installFromStore(
        _ listing: ExtensionListing,
        onProgress: @Sendable @escaping (ExtensionInstaller.Progress) -> Void
    ) async throws {
        let installed = try await ExtensionInstaller().install(listing, onProgress: onProgress)
        storeVersions.record(listing.commitSHA, for: installed.manifest.name)
        updates[installed.manifest.name] = nil
    }

    /// 从文件夹或 GitHub 安装的是用户自己的副本，商店对它没有可提供的更新。
    private func untrack(_ name: String) {
        storeVersions.forget(name)
        updates[name] = nil
    }

    /// 连带清除所有以它为键的数据：文件、存储、图标及其快捷键。
    func uninstall(_ installedExtension: InstalledExtension) async {
        menuBars?.remove(extensionName: installedExtension.manifest.name)
        if running?.extensionName == installedExtension.manifest.name { await stop() }
        if backgroundRef?.extensionName == installedExtension.manifest.name {
            await abortBackgroundRun()
        }
        let entryIDs = installedExtension.manifest.commands.map {
            ExtensionCommandRef(
                extensionName: installedExtension.manifest.name, commandName: $0.name
            ).entryID
        }
        ExtensionOAuthKeychain.removeAllTokens(extensionName: installedExtension.manifest.name)
        try? ExtensionCatalog.uninstall(installedExtension)
        storage.removeAll(extension: installedExtension.manifest.name)
        commandMetadata.removeAll(extension: installedExtension.manifest.name)
        untrack(installedExtension.manifest.name)
        appearances.set(nil, for: installedExtension.manifest.name)
        onDidUninstall?(entryIDs)
        await refresh()
    }

    // MARK: - Running a command

    /// 把启动器条目解析为命令；若该条目不是扩展命令则返回 nil。
    func resolve(_ entry: AppEntry) -> (InstalledExtension, ExtensionCommand)? {
        guard let reference = ExtensionCommandRef(entryID: entry.id),
            let owner = extensionNamed(reference.extensionName),
            let command = owner.command(named: reference.commandName)
        else { return nil }
        return (owner, command)
    }

    /// 深链接指定 owner/extension/command；owner 只是提示，真正的判定依据是标识（slug）。
    func resolve(_ link: ExtensionDeepLink) -> (InstalledExtension, ExtensionCommand)? {
        let candidates = installed.filter { link.matches(manifestName: $0.manifest.name) }
        guard
            let owner = link.extensionCandidates.lazy.compactMap({ want in
                candidates.first { $0.manifest.name.lowercased() == want.lowercased() }
            }).first ?? candidates.first,
            let command = owner.manifest.commands.first(where: {
                $0.name.lowercased() == link.commandName.lowercased()
            })
        else { return nil }
        return (owner, command)
    }

    func run(_ entry: AppEntry, arguments: [String: String] = [:]) async {
        guard let (owner, command) = resolve(entry) else {
            state = .failed(ExtensionLaunchError.unknownCommand(entry.id).localizedDescription)
            return
        }
        await run(owner, command: command, arguments: arguments)
    }

    func run(
        _ owner: InstalledExtension, command: ExtensionCommand, arguments: [String: String] = [:],
        fallbackText: String? = nil, launchType: ExtensionLaunchType = .userInitiated,
        launchContext: [String: RenderValue] = [:]
    ) async {
        guard isEnabled else { return }
        if command.mode == .menuBar || (command.mode == .noView && launchType == .background) {
            menuBars?.run(
                owner, command: command, arguments: arguments, type: launchType, context: launchContext)
            return
        }
        await stop()
        guard isEnabled else { return }
        let schemas = owner.manifest.preferences + command.preferences
        let missing = storage.missingRequiredPreferences(
            extension: owner.manifest.name, schemas: schemas)
        guard missing.isEmpty else {
            running = ExtensionCommandRef(
                extensionName: owner.manifest.name, commandName: command.name)
            state = .failed(ExtensionLaunchError.missingPreferences(missing).localizedDescription)
            return
        }
        guard let bundle = owner.bundleURL(for: command) else {
            running = ExtensionCommandRef(
                extensionName: owner.manifest.name, commandName: command.name)
            state = .failed(ExtensionLaunchError.notBuilt(command.title).localizedDescription)
            return
        }

        running = ExtensionCommandRef(extensionName: owner.manifest.name, commandName: command.name)
        navigationDepth = 1
        state = .launching

        // 运行时只持有一个 context：进行中的后台任务会让位给手动运行。
        await abortBackgroundRun()

        // Raycast 在首次手动打开时激活调度；这次运行本身就是第一次刷新。
        if ExtensionRefreshPolicy.isSchedulable(mode: command.mode, interval: command.interval) {
            commandMetadata.activateBackgroundRefresh(
                extension: owner.manifest.name, command: command.name, now: Date())
            restartBackgroundLoop()
        }

        let supportPath = ExtensionCatalog.supportPath(for: owner.manifest.name)
        try? FileManager.default.createDirectory(at: supportPath, withIntermediateDirectories: true)

        do {
            // context 已就绪时为空操作；在 `stop()` 之后会构建一个全新的 context。
            try await runtime.boot(config: .current(supportDirectory: supportPath))
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        // 读取数百 KB 的 bundle 属于 IO 操作；放到主 actor 之外执行。
        let code = await Task.detached(priority: .userInitiated) {
            (try? String(contentsOf: bundle, encoding: .utf8)) ?? ""
        }.value
        guard !code.isEmpty else {
            state = .failed(ExtensionLaunchError.notBuilt(command.title).localizedDescription)
            return
        }

        let session = UUID().uuidString
        sessionID = session
        let context = makeLaunchContext(
            owner: owner, command: command, arguments: arguments, supportPath: supportPath,
            fallbackText: fallbackText,
            launchType: command.mode == .view ? .userInitiated : launchType,
            launchContext: launchContext)

        await runtime.start(
            session: session, code: code, file: bundle, mode: command.mode, context: context)
    }

    private func makeLaunchContext(
        owner: InstalledExtension, command: ExtensionCommand, arguments: [String: String],
        supportPath: URL, fallbackText: String? = nil, launchType: ExtensionLaunchType,
        launchContext: [String: RenderValue] = [:]
    ) -> ExtensionLaunchContext {
        let schemas = owner.manifest.preferences + command.preferences
        return ExtensionLaunchContext(
            extensionName: owner.manifest.name,
            extensionTitle: owner.title,
            commandName: command.name,
            commandMode: command.mode,
            assetsPath: owner.assetsPath,
            supportPath: supportPath.path,
            preferences: storage.resolvedPreferences(
                extension: owner.manifest.name, schemas: schemas),
            caches: storage.caches(extension: owner.manifest.name),
            arguments: command.completeArguments(arguments),
            fallbackText: fallbackText,
            launchType: launchType,
            isDarkAppearance: NSApp.effectiveAppearance.isDark,
            launchContext: launchContext)
    }

    /// 停止当前会话并重置会话状态。
    func stop() async {
        oauthSession.cancel()
        guard let sessionID else {
            resetSessionState()
            return
        }
        self.sessionID = nil
        await runtime.stop(session: sessionID)
        // 直接丢弃 context，确保没有任何残留影响下一次运行。
        runtime.shutdown()
        storage.flush()
        resetSessionState()
    }

    private func resetSessionState() {
        state = .idle
        running = nil
        toasts = []
        navigationDepth = 1
        accessoryValues = [:]
    }

    // MARK: - Background refresh

    func backgroundInfo(extension name: String, command: String) -> ExtensionCommandMetadata {
        commandMetadata.metadata(extension: name, command: command)
    }

    func setBackgroundEnabled(_ enabled: Bool, extension name: String, command: String) {
        commandMetadata.setBackgroundEnabled(enabled, extension: name, command: command)
        if !enabled { commandMetadata.clearBackgroundError(extension: name, command: command) }
        publishLauncherEntries()
        restartBackgroundLoop()
    }

    func menuBarIsEnabled(_ reference: ExtensionCommandRef) -> Bool {
        commandMetadata.metadata(
            extension: reference.extensionName, command: reference.commandName
        ).menuBarEnabled
    }

    /// 开启即运行：菜单栏项展示的内容由该次运行渲染决定。
    func setMenuBarEnabled(_ enabled: Bool, reference: ExtensionCommandRef) {
        guard enabled else {
            menuBars?.disable(reference.entryID)
            return
        }
        guard let owner = extensionNamed(reference.extensionName),
            let command = owner.command(named: reference.commandName)
        else { return }
        menuBars?.run(owner, command: command)
    }

    /// 操作菜单是否可以为该条目提供刷新相关控件。
    func isBackgroundSchedulable(for entry: AppEntry) -> Bool {
        guard let (_, command) = resolve(entry) else { return false }
        return ExtensionRefreshPolicy.isSchedulable(mode: command.mode, interval: command.interval)
    }

    func isBackgroundEnabled(for entry: AppEntry) -> Bool {
        guard let reference = ExtensionCommandRef(entryID: entry.id) else { return false }
        return commandMetadata.metadata(
            extension: reference.extensionName, command: reference.commandName
        ).backgroundEnabled
    }

    /// 切换某条目的后台刷新开关，并重启后台循环使变更立即生效。
    func toggleBackgroundRefresh(for entry: AppEntry) {
        guard let reference = ExtensionCommandRef(entryID: entry.id),
            isBackgroundSchedulable(for: entry)
        else { return }
        let enabled = commandMetadata.metadata(
            extension: reference.extensionName, command: reference.commandName
        ).backgroundEnabled
        setBackgroundEnabled(!enabled, extension: reference.extensionName, command: reference.commandName)
    }

    /// 立即执行一次无界面运行，不改变启用标志，也不影响调色板。
    func refreshNow(_ entry: AppEntry) {
        guard let (owner, command) = resolve(entry),
            ExtensionRefreshPolicy.isSchedulable(mode: command.mode, interval: command.interval)
        else { return }
        let reference = ExtensionCommandRef(
            extensionName: owner.manifest.name, commandName: command.name)
        if let refusal = ExtensionRefreshPolicy.refreshNowRefusal(
            foregroundRunning: running != nil,
            refreshingCommand: backgroundRef?.entryID,
            command: reference.entryID)
        {
            coordinator?.showHUD(refusal)
            return
        }
        Task { [weak self] in
            await self?.runInBackground(owner, command: command)
            self?.restartBackgroundLoop()
        }
    }

    /// 只在有命令需要时才启动一次循环：没有任何启用项时不存在任务，
    /// 因此未使用的调度不产生任何开销。
    private func ensureBackgroundLoop() {
        guard isEnabled, backgroundTask == nil, hasEnabledBackgroundCommands else { return }
        backgroundTask = Task { [weak self] in await self?.backgroundLoop() }
    }

    /// 当前是否有任何已安装命令需要后台周期性触发。
    private var hasEnabledBackgroundCommands: Bool {
        schedulableCommands().contains { owner, command in
            commandMetadata.metadata(extension: owner.manifest.name, command: command.name)
                .backgroundEnabled
        }
    }

    private func restartBackgroundLoop() {
        backgroundTask?.cancel()
        backgroundTask = nil
        ensureBackgroundLoop()
    }

    private func backgroundLoop() async {
        try? await Task.sleep(for: .seconds(5))
        while !Task.isCancelled {
            guard isEnabled else { return }
            await runDueBackgroundCommands()
            if Task.isCancelled { return }
            // 最后一个调度移除后循环会自动停止；重新启用会再次启动它。
            guard hasEnabledBackgroundCommands else {
                backgroundTask = nil
                return
            }
            try? await Task.sleep(for: .seconds(nextBackgroundDelay()))
        }
    }

    private func schedulableCommands() -> [(InstalledExtension, ExtensionCommand)] {
        installed.flatMap { owner in
            owner.manifest.commands.compactMap { command in
                guard
                    ExtensionRefreshPolicy.isSchedulable(mode: command.mode, interval: command.interval)
                else { return nil }
                return (owner, command)
            }
        }
    }

    /// 同一时间窗内到期的命令会合并成一批执行，使相邻触发共享一次唤醒。
    private func runDueBackgroundCommands() async {
        guard running == nil, backgroundSessionID == nil else { return }
        let now = Date()
        let due = schedulableCommands().filter { owner, command in
            let reference = ExtensionCommandRef(
                extensionName: owner.manifest.name, commandName: command.name)
            let metadata = commandMetadata.metadata(
                extension: owner.manifest.name, command: command.name)
            guard metadata.backgroundEnabled, let interval = command.interval else { return false }
            return ExtensionRefreshPolicy.nextDue(
                lastRun: metadata.lastRun, now: now, interval: interval,
                consecutiveFailures: metadata.consecutiveFailures, entryID: reference.entryID)
                <= now.addingTimeInterval(ExtensionRefreshPolicy.coalescingWindow)
        }
        guard !due.isEmpty else { return }
        for (owner, command) in due {
            guard !Task.isCancelled, isEnabled, running == nil else { break }
            await runInBackground(owner, command: command)
        }
    }

    /// 设有上限，使安装或开关操作无需重启循环即可被感知。
    private func nextBackgroundDelay() -> TimeInterval {
        guard running == nil else { return ExtensionRefreshPolicy.coalescingWindow }
        let now = Date()
        var delay = ExtensionRefreshPolicy.idleHeartbeat
        for (owner, command) in schedulableCommands() {
            let reference = ExtensionCommandRef(
                extensionName: owner.manifest.name, commandName: command.name)
            let metadata = commandMetadata.metadata(
                extension: owner.manifest.name, command: command.name)
            guard metadata.backgroundEnabled, let interval = command.interval else { continue }
            let due = ExtensionRefreshPolicy.nextDue(
                lastRun: metadata.lastRun, now: now, interval: interval,
                consecutiveFailures: metadata.consecutiveFailures, entryID: reference.entryID)
            delay = min(delay, max(due.timeIntervalSince(now), 5))
        }
        return delay
    }

    /// 一次无界面的 `no-view` 运行：调色板不发生任何变化，也不触发反馈，只有副标题可能更新。
    private func runInBackground(_ owner: InstalledExtension, command: ExtensionCommand) async {
        guard backgroundSessionID == nil, running == nil, let interval = command.interval else {
            return
        }
        guard let bundle = owner.bundleURL(for: command) else { return }
        let reference = ExtensionCommandRef(
            extensionName: owner.manifest.name, commandName: command.name)
        let supportPath = ExtensionCatalog.supportPath(for: owner.manifest.name)
        try? FileManager.default.createDirectory(at: supportPath, withIntermediateDirectories: true)

        let session = UUID().uuidString
        backgroundSessionID = session
        backgroundRef = reference
        backgroundFailure = nil
        var succeeded = false
        defer {
            // 运行中途消失意味着已被卸载：此时记录结果会重新创建其存储文件。
            if extensionNamed(reference.extensionName) != nil {
                commandMetadata.recordBackgroundResult(
                    extension: reference.extensionName, command: reference.commandName,
                    success: succeeded, error: succeeded ? nil : (backgroundFailure ?? "Timed out."),
                    now: Date())
            }
            backgroundSessionID = nil
            backgroundRef = nil
            backgroundFailure = nil
            backgroundContinuation = nil
            publishLauncherEntries()
            storage.flush()
            commandMetadata.flush()
        }

        do {
            try await runtime.boot(config: .current(supportDirectory: supportPath))
        } catch {
            backgroundFailure = error.localizedDescription
            return
        }
        let code = await Task.detached(priority: .utility) {
            (try? String(contentsOf: bundle, encoding: .utf8)) ?? ""
        }.value
        guard !code.isEmpty else {
            backgroundFailure = ExtensionLaunchError.notBuilt(command.title).localizedDescription
            return
        }
        let context = makeLaunchContext(
            owner: owner, command: command, arguments: [:], supportPath: supportPath,
            launchType: .background)
        await runtime.start(
            session: session, code: code, file: bundle, mode: command.mode, context: context)
        succeeded = await waitForBackgroundResult(
            timeout: ExtensionRefreshPolicy.timeout(interval: interval))
        // 中止操作已经拆掉了会话；此时再操作 runtime 会连带影响手动运行新建的 context。
        guard backgroundSessionID == session else { return }
        await runtime.stop(session: session)
        runtime.shutdown()
    }

    private func waitForBackgroundResult(timeout: TimeInterval) async -> Bool {
        await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            group.addTask { [weak self] in await self?.backgroundSettled() ?? false }
            group.addTask { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(timeout))
                } catch {
                    // 循环被取消属于抢占该次触发；只有真正的超时才算失败。
                    await self?.resumeBackground(with: true)
                    return true
                }
                await self?.resumeBackground(with: false)
                return false
            }
            defer { group.cancelAll() }
            return await group.next() ?? false
        }
    }

    /// 挂起直到运行结束、超时或被抢占；所有退出路径都经由 `resumeBackground`。
    private func backgroundSettled() async -> Bool {
        await withCheckedContinuation { continuation in backgroundContinuation = continuation }
    }

    /// 将进行中的后台运行按成功结束，使其调度在本次抢占后继续保留。
    private func abortBackgroundRun() async {
        guard let session = backgroundSessionID else { return }
        backgroundSessionID = nil
        backgroundRef = nil
        await runtime.stop(session: session)
        runtime.shutdown()
        resumeBackground(with: true)
    }

    /// 在主 actor 上串行执行，确保上述退出路径不会重复恢复同一个 continuation。
    private func resumeBackground(with result: Bool) {
        guard let continuation = backgroundContinuation else { return }
        backgroundContinuation = nil
        continuation.resume(returning: result)
    }

    // MARK: - Events from the palette

    /// 把调色板发起的 handler 调用转发给扩展运行时。
    func dispatch(handler: String, arguments: [Any] = []) {
        guard let sessionID else { return }
        let payload = ExtensionRuntime.jsonString(from: arguments)
        Task { await runtime.dispatch(session: sessionID, handler: handler, payload: payload) }
    }

    // MARK: - Search-bar dropdowns

    /// 下拉框展示的内容：若由扩展自身控制则为它的 `value`，否则为用户的选项。
    func accessorySelection(_ accessory: ExtensionSearchAccessory) -> String? {
        accessory.controlledValue ?? accessoryValues[accessory.nodeID]
    }

    /// 用户选择会持久化到下拉框指定的位置，然后通知扩展。
    func chooseAccessorySelection(_ accessory: ExtensionSearchAccessory, value: String) {
        accessoryValues[accessory.nodeID] = value
        if let key = accessory.storageKey, let name = running?.extensionName {
            storage.setAccessoryValue(extension: name, key: key, value: value)
        }
        guard let handler = accessory.onChange else { return }
        dispatch(handler: handler, arguments: [value])
    }

    /// Raycast 通过 `onChange` 上报下拉框的初始选择，而按该值过滤行的扩展在收到前不会绘制任何内容。由扩展自身控制的下拉框无需处理。
    private func seedSearchBarAccessory(in tree: RenderTree) {
        guard
            let accessory = ExtensionSearchAccessory(
                node: tree.activeRoot?.node("searchBarAccessory")),
            accessory.controlledValue == nil, accessoryValues[accessory.nodeID] == nil,
            let value = accessory.initialValue(stored: storedAccessoryValue(accessory))
        else { return }
        accessoryValues[accessory.nodeID] = value
        guard let handler = accessory.onChange else { return }
        dispatch(handler: handler, arguments: [value])
    }

    private func storedAccessoryValue(_ accessory: ExtensionSearchAccessory) -> String? {
        guard let key = accessory.storageKey, let name = running?.extensionName else { return nil }
        return storage.accessoryValue(extension: name, key: key)
    }

    /// 弹出扩展导航栈；无可弹出项、应由调色板关闭时返回 false。
    func popNavigation() async -> Bool {
        guard let sessionID, navigationDepth > 1 else { return false }
        return await runtime.popNavigation(session: sessionID)
    }

    func runToastAction(token: String) {
        Task { await runtime.runToastAction(token: token) }
    }

    // MARK: - ExtensionRuntimeDelegate

    func runtime(_ runtime: ExtensionRuntime, session: String, didRender tree: RenderTree) {
        guard session == sessionID else { return }
        state = .rendered(tree)
        navigationDepth = tree.depth
        seedSearchBarAccessory(in: tree)
    }

    func runtime(_ runtime: ExtensionRuntime, session: String, didFail message: String) {
        if session == backgroundSessionID {
            backgroundFailure = message
            resumeBackground(with: false)
            return
        }
        guard session == sessionID else { return }
        state = .failed(message)
    }

    func runtime(_ runtime: ExtensionRuntime, session: String, navigationDepth depth: Int) {
        guard session == sessionID else { return }
        navigationDepth = depth
    }

    func runtime(_ runtime: ExtensionRuntime, session: String, didFinish: Void) {
        if session == backgroundSessionID {
            resumeBackground(with: true)
            return
        }
        guard session == sessionID else { return }
        // 无界面命令已完成：调色板已在关闭，只需释放会话。
        state = .finished
        Task { await stop() }
    }

    func runtime(_ runtime: ExtensionRuntime, log level: String, message: String) {
        #if DEBUG
            print("[extension \(level)] \(message)")
        #endif
    }

    // MARK: - ExtensionHostContext

    var activeExtensionName: String? { backgroundRef?.extensionName ?? running?.extensionName }
    var activeLaunchType: ExtensionLaunchType {
        backgroundSessionID != nil ? .background : .userInitiated
    }
    var pasteTarget: NSRunningApplication? { coordinator?.pasteTarget }
    var applicationURLs: [URL] { coordinator?.applicationURLs ?? [] }

    func closeMainWindow(clearRootSearch: Bool) {
        coordinator?.closeMainWindow()
    }

    func reopenPalette() {
        coordinator?.reopenPalette(hasRunningCommand: running != nil)
    }

    func popToRoot() {
        coordinator?.popExtensionToRoot()
    }

    func clearSearchBar() {
        coordinator?.clearSearchBar()
    }

    func openPreferences(scope: String) {
        guard let running, let owner = extensionNamed(running.extensionName) else { return }
        coordinator?.showExtensionSettings(for: owner)
    }

    /// 更新运行中命令的条目元数据；键缺失时保持副标题不变。
    func updateCommandMetadata(subtitle: String?) {
        guard let reference = backgroundRef ?? running else { return }
        updateCommandMetadata(subtitle: subtitle, for: reference)
    }

    func updateCommandMetadata(subtitle: String?, for reference: ExtensionCommandRef) {
        commandMetadata.setSubtitle(
            subtitle, extension: reference.extensionName, command: reference.commandName)
        publishLauncherEntries()
    }

    func present(toast: ExtensionToast) -> Int {
        var stamped = toast
        stamped.id = nextToastID
        nextToastID += 1
        // 无界面命令的 toast 没有可显示的调色板，因此改用 HUD 呈现。
        guard coordinator?.isPaletteVisible == true else {
            coordinator?.showHUD(
                [toast.title, toast.message].compactMap { $0 }.joined(separator: " — "))
            return stamped.id
        }
        toasts = [stamped]
        // 非动画 toast 会自动消失；动画 toast 会一直保留，直到命令主动隐藏。
        if stamped.style != .animated { scheduleToastDismissal(id: stamped.id) }
        return stamped.id
    }

    func update(toast id: Int, with toast: ExtensionToast) {
        guard let index = toasts.firstIndex(where: { $0.id == id }) else { return }
        var stamped = toast
        stamped.id = id
        toasts[index] = stamped
        if stamped.style != .animated { scheduleToastDismissal(id: id) }
    }

    func hide(toast id: Int) {
        toasts.removeAll { $0.id == id }
    }

    private func scheduleToastDismissal(id: Int) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.hide(toast: id)
        }
    }

    func showHUD(_ text: String) {
        coordinator?.showHUD(text)
    }

    func confirmAlert(_ alert: ExtensionAlert) async -> Bool {
        await coordinator?.confirmExtensionAlert(alert) ?? false
    }

    func openWithPicker(path: String) async {
        let target = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let candidates = NSWorkspace.shared.urlsForApplications(toOpen: target)
        guard candidates.count > 1 else {
            NSWorkspace.shared.open(target)
            return
        }
        let panel = NSAlert()
        panel.messageText = "Open With"
        panel.informativeText = target.lastPathComponent
        for candidate in candidates.prefix(4) {
            panel.addButton(withTitle: candidate.deletingPathExtension().lastPathComponent)
        }
        panel.addButton(withTitle: "Cancel")
        let response = panel.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard response >= 0, response < min(candidates.count, 4) else { return }
        NSWorkspace.shared.open(
            [target], withApplicationAt: candidates[Int(response)],
            configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    /// 运行中命令调用的 `launchCommand`：除非显式指定其他扩展，否则沿用同一扩展。
    func launch(
        command name: String, extensionName: String?, arguments: [String: String],
        fallbackText: String?, launchType: ExtensionLaunchType, launchContext: [String: RenderValue]
    ) throws {
        let owningName = extensionName ?? activeExtensionName
        guard let owningName, let owner = extensionNamed(owningName),
            let command = owner.command(named: name)
        else { throw ExtensionLaunchError.unknownCommand(name) }
        guard isEnabled else { throw ExtensionLaunchError.unsupported("Extensions are disabled.") }
        guard launchType != .background || command.mode != .view else {
            throw ExtensionLaunchError.unsupported("A view command cannot run in the background.")
        }
        coordinator?.runExtensionCommand(
            entry(for: command, in: owner), arguments: arguments, fallbackText: fallbackText,
            launchType: launchType, launchContext: launchContext)
    }

    func launch(_ link: ExtensionDeepLink) throws {
        guard let (owner, command) = resolve(link) else {
            throw ExtensionLaunchError.unknownCommand(link.commandName)
        }
        coordinator?.runExtensionCommand(
            entry(for: command, in: owner), arguments: link.arguments,
            fallbackText: link.fallbackText, launchType: link.launchType)
    }

    func authorizeOAuth(options: ExtensionOAuthAuthorizeOptions) async throws -> ExtensionOAuthAuthorizeResult
    {
        lastOAuthExtensionName = running?.extensionName
        return try await oauthSession.authorize(options: options)
    }

    func getOAuthTokens(providerId: String) -> String? {
        guard let extName = running?.extensionName ?? lastOAuthExtensionName else { return nil }
        return ExtensionOAuthKeychain.getTokens(extensionName: extName, providerId: providerId)
    }

    func setOAuthTokens(providerId: String, tokens: String) {
        guard let extName = running?.extensionName ?? lastOAuthExtensionName else { return }
        ExtensionOAuthKeychain.setTokens(tokens, extensionName: extName, providerId: providerId)
    }

    func removeOAuthTokens(providerId: String) {
        guard let extName = running?.extensionName ?? lastOAuthExtensionName else { return }
        ExtensionOAuthKeychain.removeTokens(extensionName: extName, providerId: providerId)
    }
}
