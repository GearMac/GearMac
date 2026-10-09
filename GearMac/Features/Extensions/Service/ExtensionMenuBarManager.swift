// 文件职责：菜单栏扩展项的管理器，负责按命令队列串行执行菜单栏/no-view 命令，维护 NSStatusItem 控制器、刷新调度、超时与空闲回收。
// 分层：Service（@MainActor）；作为 ExtensionRuntimeDelegate 接收运行时回调，所有 UI 交互通过注入的 makeExecution / onError 闭包完成。
import AppKit
import os

/// 菜单栏命令的调度与展示中心：串行执行命令并维护状态栏项。
@MainActor
final class ExtensionMenuBarManager: ExtensionRuntimeDelegate {
    private let storage: ExtensionStorage
    private let commandMetadata: ExtensionCommandMetadataStore
    private let supportDirectory: URL
    private let executionTimeout: Duration
    private let showsStatusItems: Bool
    private let makeExecution: (InstalledExtension, ExtensionCommand, ExtensionLaunchType) -> Execution?
    private let onError: (String, InstalledExtension, Bool) -> Void
    private var installed: [InstalledExtension] = []
    private var controllers: [String: ExtensionMenuBarController] = [:]
    private var requests: [Request] = []
    private var active: Session?
    private var launchTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    /// 一次命令执行所需的外部依赖：运行时，以及停止它和开启交互的回调。
    struct Execution {
        let runtime: ExtensionRuntime
        var stop: () -> Void
        var enableInteraction: () -> Void = {}
    }

    var isRunning: Bool { active != nil }

    private struct Request {
        let reference: ExtensionCommandRef
        var type: ExtensionLaunchType = .background
        var arguments: [String: String] = [:]
        var context: [String: RenderValue] = [:]
        var scheduled = false
    }

    private final class Session {
        /// 供运行时回调识别会话的唯一标识。
        let id = UUID().uuidString
        let request: Request
        let owner: InstalledExtension
        let mode: ExtensionCommandMode
        let execution: Execution
        var runtime: ExtensionRuntime { execution.runtime }
        var isLoading = true
        var pendingActions = 0
        var isInteractive: Bool

        /// 创建会话；userInitiated 类型默认即处于交互模式。
        init(request: Request, owner: InstalledExtension, mode: ExtensionCommandMode, execution: Execution) {
            self.request = request
            self.owner = owner
            self.mode = mode
            self.execution = execution
            isInteractive = request.type == .userInitiated
        }

        func enableInteraction() {
            isInteractive = true
            execution.enableInteraction()
        }
    }

    /// 构建管理器；executionTimeout 为单次执行超时，showsStatusItems 控制是否真正创建状态栏项。
    init(
        storage: ExtensionStorage, commandMetadata: ExtensionCommandMetadataStore, supportDirectory: URL,
        executionTimeout: Duration = .seconds(60), showsStatusItems: Bool = true,
        makeExecution: @escaping (InstalledExtension, ExtensionCommand, ExtensionLaunchType) -> Execution?,
        onError: @escaping (String, InstalledExtension, Bool) -> Void
    ) {
        self.storage = storage
        self.commandMetadata = commandMetadata
        self.supportDirectory = supportDirectory
        self.executionTimeout = executionTimeout
        self.showsStatusItems = showsStatusItems
        self.makeExecution = makeExecution
        self.onError = onError
    }

    /// 用最新的已安装集合同步状态：已失效的命令被禁用，已有快照的项立即回放。
    func synchronize(_ installed: [InstalledExtension]) {
        self.installed = installed
        for reference in menuBarReferences() {
            guard let (owner, command) = resolve(reference), command.mode == .menuBar
            else {
                disable(reference.entryID)
                continue
            }
            if let snapshot = metadata(reference).menuBarSnapshot {
                controller(for: reference, owner: owner).update(snapshot)
            }
        }
        scheduleRefresh()
    }

    /// 将一次菜单栏/no-view 运行入队；用户手动打开菜单栏命令时顺带启用其菜单栏开关。
    func run(
        _ owner: InstalledExtension, command: ExtensionCommand, arguments: [String: String] = [:],
        type: ExtensionLaunchType = .userInitiated, context: [String: RenderValue] = [:]
    ) {
        let reference = ExtensionCommandRef(extensionName: owner.manifest.name, commandName: command.name)
        if command.mode == .menuBar, type == .userInitiated, !metadata(reference).menuBarEnabled {
            commandMetadata.setMenuBarEnabled(
                true, extension: reference.extensionName,
                command: reference.commandName)
        }
        enqueue(Request(reference: reference, type: type, arguments: arguments, context: context))
    }

    /// 禁用一个菜单栏项：移出队列、移除控制器并清除元数据开关。
    func disable(_ entryID: String) {
        requests.removeAll { $0.reference.entryID == entryID }
        controllers.removeValue(forKey: entryID)?.remove()
        if let reference = ExtensionCommandRef(entryID: entryID) {
            commandMetadata.setMenuBarEnabled(
                false, extension: reference.extensionName,
                command: reference.commandName)
        }
        if active?.request.reference.entryID == entryID { finish() }
        runNext()
        scheduleRefresh()
    }

    /// 卸载扩展时调用：清除其全部请求与状态栏项，必要时结束当前会话。
    func remove(extensionName: String) {
        requests.removeAll { $0.reference.extensionName == extensionName }
        if active?.owner.manifest.name == extensionName { finish() }
        for reference in menuBarReferences() where reference.extensionName == extensionName {
            disable(reference.entryID)
        }
        runNext()
    }

    /// 完全停止：取消刷新任务、清空队列、结束会话并移除所有状态栏项。
    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        requests.removeAll()
        finish()
        for controller in controllers.values { controller.remove() }
        controllers.removeAll()
        installed = []
    }

    private func resolve(_ reference: ExtensionCommandRef) -> (InstalledExtension, ExtensionCommand)? {
        guard let owner = installed.first(where: { $0.manifest.name == reference.extensionName }),
            let command = owner.command(named: reference.commandName)
        else { return nil }
        return (owner, command)
    }

    private func metadata(_ reference: ExtensionCommandRef) -> ExtensionCommandMetadata {
        commandMetadata.metadata(extension: reference.extensionName, command: reference.commandName)
    }

    private func menuBarReferences() -> [ExtensionCommandRef] {
        commandMetadata.menuBarCommands().map {
            ExtensionCommandRef(extensionName: $0.extension, commandName: $0.command)
        }
    }

    private func enqueue(_ request: Request) {
        if request.scheduled, requests.contains(where: { $0.reference == request.reference }) { return }
        requests.removeAll { $0.reference == request.reference && $0.scheduled }
        requests.append(request)
        if active == nil { runNext() }
    }

    /// 串行执行的下一个请求：校验模式与偏好，构造启动上下文并异步载入 bundle。
    private func runNext() {
        guard active == nil, !requests.isEmpty else { return }
        let request = requests.removeFirst()
        let entryID = request.reference.entryID
        guard let (owner, command) = resolve(request.reference),
            command.mode == .noView || metadata(request.reference).menuBarEnabled
        else { runNext(); return }
        if command.mode == .menuBar {
            commandMetadata.recordMenuBarRun(
                extension: request.reference.extensionName,
                command: request.reference.commandName, now: Date())
            scheduleRefresh()
        }

        let missing = storage.missingRequiredPreferences(
            extension: owner.manifest.name,
            schemas: owner.manifest.preferences + command.preferences)
        guard missing.isEmpty, let bundle = owner.bundleURL(for: command) else {
            let message =
                missing.isEmpty
                ? ExtensionLaunchError.notBuilt(command.title).localizedDescription
                : ExtensionLaunchError.missingPreferences(missing).localizedDescription
            controllers[entryID]?.showError(message)
            if request.type == .userInitiated || controllers[entryID]?.isOpen == true {
                onError(message, owner, !missing.isEmpty)
            }
            runNext()
            return
        }
        guard let execution = makeExecution(owner, command, request.type) else { runNext(); return }
        let runtime = execution.runtime
        runtime.setDelegate(self)
        let session = Session(request: request, owner: owner, mode: command.mode, execution: execution)
        active = session
        if controllers[entryID]?.isOpen == true { session.enableInteraction() }
        let support = supportDirectory.appendingPathComponent(ExtensionCatalog.safeName(owner.manifest.name))
        let context = ExtensionLaunchContext(
            extensionName: owner.manifest.name, extensionTitle: owner.title, commandName: command.name,
            commandMode: command.mode, assetsPath: owner.assetsPath, supportPath: support.path,
            preferences: storage.resolvedPreferences(
                extension: owner.manifest.name,
                schemas: owner.manifest.preferences + command.preferences),
            caches: storage.caches(extension: owner.manifest.name),
            arguments: command.completeArguments(request.arguments),
            fallbackText: nil, launchType: request.type,
            isDarkAppearance: NSApp.effectiveAppearance.isDark, launchContext: request.context)
        launchTask = Task { [weak self] in
            do {
                let code = try await Task.detached(priority: .utility) {
                    try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
                    return try String(contentsOf: bundle, encoding: .utf8)
                }.value
                guard !Task.isCancelled else { return }
                try await runtime.boot(config: .current(supportDirectory: support))
                guard !Task.isCancelled else { runtime.shutdown(); return }
                await runtime.start(
                    session: session.id, code: code, file: bundle, mode: command.mode, context: context)
            } catch {
                self?.runtime(runtime, session: session.id, didFail: error.localizedDescription)
            }
        }
        armDeadline(session)
    }

    /// 取得（必要时创建）某个命令对应的状态栏控制器，并装配其打开/关闭/操作回调。
    func controller(
        for reference: ExtensionCommandRef, owner: InstalledExtension
    ) -> ExtensionMenuBarController {
        if let controller = controllers[reference.entryID] { return controller }
        let controller = ExtensionMenuBarController(
            entryID: reference.entryID, assetsPath: owner.assetsPath,
            isVisible: showsStatusItems)
        controller.onOpen = { [weak self] in
            guard let self else { return }
            if self.active?.request.reference == reference {
                self.idleTask?.cancel()
                self.active?.enableInteraction()
                return
            }
            let queued = self.requests.firstIndex { $0.reference == reference && !$0.scheduled }
            let request =
                queued.map { self.requests.remove(at: $0) }
                ?? Request(reference: reference, type: .userInitiated)
            self.requests.removeAll { $0.reference == reference && $0.scheduled }
            self.requests.insert(request, at: 0)
            self.releaseIfIdle()
            self.runNext()
        }
        controller.onClose = { [weak self] in
            guard let self, let active = self.active, active.request.reference == reference else { return }
            self.armDeadline(active)
            self.releaseIfIdle()
        }
        controller.onAction = { [weak self] session, handler, type in
            guard let self, let active = self.active, active.id == session else { return }
            self.idleTask?.cancel()
            active.enableInteraction()
            active.pendingActions += 1
            self.armDeadline(active)
            Task {
                await active.runtime.dispatch(
                    session: session, handler: handler,
                    payload: ExtensionRuntime.jsonString(from: [["type": type]]),
                    completesSession: true)
            }
        }
        controller.onActionUnavailable = { [weak self] in
            self?.onError("This menu item changed. Open the menu and try again.", owner, false)
        }
        controllers[reference.entryID] = controller
        return controller
    }

    /// 为会话设置执行超时：菜单已打开且无待处理操作时不判超时。
    private func armDeadline(_ session: Session) {
        deadlineTask?.cancel()
        let timeout = executionTimeout
        deadlineTask = Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard let self, self.active?.id == session.id else { return }
            if self.controllers[session.request.reference.entryID]?.isOpen == true,
                !session.isLoading, session.pendingActions == 0
            {
                return
            }
            self.runtime(session.runtime, session: session.id, didFail: "The menu bar command timed out.")
        }
    }

    /// 会话已加载完成、无待处理操作且菜单已关闭时，延迟一拍后结束会话并执行下一个。
    private func releaseIfIdle() {
        idleTask?.cancel()
        guard let active, !active.isLoading, active.pendingActions == 0,
            controllers[active.request.reference.entryID]?.isOpen != true
        else { return }
        idleTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            await active.runtime.drainHostCalls()
            // 已完结的宿主调用会在稍后的 React tick 上提交其渲染。
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            guard !Task.isCancelled, let self, self.active?.id == active.id,
                !active.isLoading, active.pendingActions == 0,
                self.controllers[active.request.reference.entryID]?.isOpen != true
            else { return }
            self.finish()
            self.runNext()
        }
    }

    /// 结束当前会话：取消各任务、停止执行并释放运行时。
    private func finish() {
        launchTask?.cancel()
        deadlineTask?.cancel()
        idleTask?.cancel()
        launchTask = nil
        deadlineTask = nil
        idleTask = nil
        guard let session = active else { return }
        active = nil
        session.execution.stop()
        session.runtime.shutdown()
        storage.flush()
        controllers[session.request.reference.entryID]?.clearMenu()
    }

    /// 按最近的到期时间安排下一次刷新定时任务。
    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        guard let next = dueDates().values.min() else { return }
        refreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow)), tolerance: .seconds(1))
            } catch { return }
            guard !Task.isCancelled, let self else { return }
            let now = Date()
            for (reference, date) in self.dueDates() where date <= now {
                guard self.active?.request.reference != reference else { continue }
                self.enqueue(Request(reference: reference, scheduled: true))
            }
            self.scheduleRefresh()
        }
    }

    /// 后台循环的节奏：基于 lastRun 计算，包含退避与每个命令各自的相位。
    private func dueDates() -> [ExtensionCommandRef: Date] {
        var dates: [ExtensionCommandRef: Date] = [:]
        let now = Date()
        for reference in menuBarReferences() {
            guard let (_, command) = resolve(reference), let interval = command.interval else { continue }
            let record = metadata(reference)
            dates[reference] = ExtensionRefreshPolicy.nextDue(
                lastRun: record.lastRun, now: now, interval: interval,
                consecutiveFailures: record.consecutiveFailures, entryID: reference.entryID)
        }
        return dates
    }

    func runtime(_ runtime: ExtensionRuntime, session: String, didRender tree: RenderTree) {
        guard let active, active.id == session else { return }
        let reference = active.request.reference
        let root = tree.activeRoot
        guard root == nil || root?.type == "MenuBarExtra" else {
            self.runtime(
                runtime, session: session, didFail: "A menu bar command must render MenuBarExtra or null.")
            return
        }
        let wasLoading = active.isLoading
        active.isLoading = root?.bool("isLoading") == true
        if !wasLoading, active.isLoading { armDeadline(active) }
        if let root {
            let snapshot = ExtensionMenuBarSnapshot(node: root)
            let controller = controller(for: reference, owner: active.owner)
            if !active.isLoading || metadata(reference).menuBarSnapshot == nil { controller.update(snapshot) }
            controller.showMenu(root, session: session)
            if !active.isLoading, active.mode == .menuBar {
                commandMetadata.setMenuBarSnapshot(
                    snapshot, extension: reference.extensionName,
                    command: reference.commandName)
                commandMetadata.clearBackgroundError(
                    extension: reference.extensionName,
                    command: reference.commandName)
            }
        } else {
            controllers.removeValue(forKey: reference.entryID)?.remove()
            if active.mode == .menuBar {
                commandMetadata.setMenuBarSnapshot(
                    nil, extension: reference.extensionName,
                    command: reference.commandName)
            }
        }
        releaseIfIdle()
    }

    func runtime(_ runtime: ExtensionRuntime, session: String, didFail message: String) {
        guard let active, active.id == session else { return }
        let reference = active.request.reference
        // 记为一次失败的刷新，使已损坏的项退避而不是持续重试。
        if active.mode == .menuBar {
            commandMetadata.recordBackgroundResult(
                extension: reference.extensionName, command: reference.commandName, success: false,
                error: message, now: Date())
        }
        controllers[active.request.reference.entryID]?.showError(message)
        if active.isInteractive { onError(message, active.owner, false) }
        finish()
        runNext()
    }

    func runtime(_ runtime: ExtensionRuntime, session: String, navigationDepth: Int) {}

    func runtime(_ runtime: ExtensionRuntime, session: String, didFinish: Void) {
        guard let active, active.id == session else { return }
        active.pendingActions = max(0, active.pendingActions - 1)
        if active.mode == .noView { active.isLoading = false }
        releaseIfIdle()
    }

    func runtime(_ runtime: ExtensionRuntime, log level: String, message: String) {
        if level == "error" {
            Logger(subsystem: "com.gearmac", category: "extension-menu-bar").error(
                "\(message, privacy: .public)")
        }
    }
}

extension ExtensionMenuBarSnapshot {
    /// 从渲染节点构造快照；图标以 JSON 形式传递，因为渲染出的 prop 不是 Codable。
    init(node: RenderNode) {
        title = node.string("title")
        tooltip = node.string("tooltip")
        if let value = node.props["icon"],
            let data = try? JSONSerialization.data(
                withJSONObject: value.jsonValue, options: .fragmentsAllowed)
        {
            iconJSON = String(bytes: data, encoding: .utf8)
        } else {
            iconJSON = nil
        }
        hasMenu = !node.children.isEmpty
    }

    var icon: RenderValue? {
        guard let data = iconJSON?.data(using: .utf8),
            let value = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        else { return nil }
        return RenderValue(json: value)
    }
}
