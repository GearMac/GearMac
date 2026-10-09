// 文件职责：探测与维护各已安装 CLI 的状态（版本、登录、模型目录），并据此构造对应提供方。
// 分层：Service；主 actor 上运行，启动探测会在独立任务中执行，避免阻塞 UI。
import Foundation
import Observation

/// 已安装 CLI 管理器：持有各工具的探测状态，并提供刷新、等待就绪与构造提供方的入口。
@MainActor
@Observable
final class InstalledAIManager {
    private(set) var statuses = Dictionary(
        uniqueKeysWithValues: InstalledAIKind.allCases.map { ($0, InstalledAIStatus()) })

    @ObservationIgnored private let workspace: URL
    @ObservationIgnored private var refreshTasks: [InstalledAIKind: Task<Void, Never>] = [:]
    /// 用户的命令路径与环境变量；每次启动时询问，使修改能在下一次启动生效。
    @ObservationIgnored var launchSettings: (InstalledAIKind) -> InstalledAILaunch = { _ in
        InstalledAILaunch()
    }

    /// 管理员下发的 MCP 策略会让 Claude 同时拒绝两个 MCP 参数；测试环境可将此指向他处。
    nonisolated static var hasManagedMCPPolicy: Bool {
        let path =
            ProcessInfo.processInfo.environment["TC_CLAUDE_MANAGED_MCP"]
            ?? "/Library/Application Support/ClaudeCode/managed-mcp.json"
        return FileManager.default.fileExists(atPath: path)
    }

    /// 彻底不使用任何 MCP 服务器，适用于未被交给任何服务器的 Claude 进程：普通轮次或探测。
    nonisolated static var claudeWithoutMCPArguments: [String] {
        hasManagedMCPPolicy ? [] : ["--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#]
    }

    /// 一次无需提示词就能回应的控制请求，使 CLI 不必调用模型即可返回。
    nonisolated private static var claudeControlArguments: [String] {
        [
            "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
            "--no-session-persistence"
        ] + claudeWithoutMCPArguments
    }

    init(supportDirectory: URL = AppPaths.applicationSupport()) {
        workspace = supportDirectory.appending(
            path: "InstalledAI/Workspace", directoryHint: .isDirectory)
        let workspace = workspace
        let launch = Date()
        Task.detached(priority: .utility) {
            Self.removeStaleTurnFiles(in: workspace, olderThan: launch)
        }
    }

    /// 一轮会在结束时删除自己的临时文件，因此早于本次启动的文件必定经历过崩溃。
    nonisolated private static func removeStaleTurnFiles(
        in workspace: URL, olderThan launch: Date
    ) {
        let fileManager = FileManager.default
        guard
            let files = try? fileManager.contentsOfDirectory(
                at: workspace, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        for file in files {
            let name = file.lastPathComponent
            guard
                (name.hasPrefix("gearmac-mcp-") && name.hasSuffix(".json"))
                    || (name.hasPrefix("gearmac-prompt-") && name.hasSuffix(".txt")),
                let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate,
                modified < launch
            else { continue }
            try? fileManager.removeItem(at: file)
        }
    }

    /// 取指定工具的当前状态，未记录过则返回默认状态。
    func status(for kind: InstalledAIKind) -> InstalledAIStatus {
        statuses[kind] ?? InstalledAIStatus()
    }

    /// 按模型来源取对应已安装 CLI 的模型列表；非已安装来源返回空。
    func models(for source: AIModelSource) -> [InstalledAIModel] {
        source.installedKind.map { status(for: $0).models } ?? []
    }

    /// 批量刷新受管 CLI：已启用的重新探测，未启用的则停止。
    @discardableResult
    func refresh(
        enabledKinds: Set<InstalledAIKind> = Set(InstalledAIKind.managedCLIKinds)
    ) -> Task<Void, Never> {
        var tasks: [Task<Void, Never>] = []
        for kind in InstalledAIKind.managedCLIKinds {
            if enabledKinds.contains(kind) {
                tasks.append(refresh(kind: kind))
            } else {
                stop(kind: kind)
            }
        }
        return Task { for task in tasks { await task.value } }
    }

    /// 刷新单个已安装 CLI：取消上一次探测并启动新的探测任务（Codex 除外）。
    @discardableResult
    func refresh(kind: InstalledAIKind) -> Task<Void, Never> {
        guard kind != .codex else { return Task {} }
        refreshTasks[kind]?.cancel()
        statuses[kind] = InstalledAIStatus(phase: .checking)
        let workspace = workspace
        let launch = launchSettings(kind)
        let task = Task { [weak self] in
            guard let self else { return }
            let result = await Self.probe(kind, launch: launch, workspace: workspace)
            guard !Task.isCancelled else { return }
            self.statuses[result.0] = result.1
        }
        refreshTasks[kind] = task
        return task
    }

    /// 确保已启用工具都有状态：未探测过的发起刷新，正在探测的复用其任务，已就绪的跳过。
    func ensure(enabledKinds: Set<InstalledAIKind>) -> Task<Void, Never> {
        var tasks: [Task<Void, Never>] = []
        for kind in InstalledAIKind.managedCLIKinds {
            guard enabledKinds.contains(kind) else {
                stop(kind: kind)
                continue
            }
            switch status(for: kind).phase {
            case .idle:
                tasks.append(refresh(kind: kind))
            case .checking:
                if let task = refreshTasks[kind] { tasks.append(task) }
            case .ready, .signInRequired, .notInstalled, .failed:
                break
            }
        }
        return Task { for task in tasks { await task.value } }
    }

    /// 取消全部探测任务并把所有状态重置为初始值。
    func stop() {
        for task in refreshTasks.values { task.cancel() }
        refreshTasks.removeAll()
        statuses = Dictionary(
            uniqueKeysWithValues: InstalledAIKind.allCases.map { ($0, InstalledAIStatus()) })
    }

    /// 停止并重置单个工具的状态。
    private func stop(kind: InstalledAIKind) {
        refreshTasks[kind]?.cancel()
        refreshTasks[kind] = nil
        statuses[kind] = InstalledAIStatus()
    }

    /// Claude Code 自行为会话命名；在此询问只需一次小请求，而非一整轮对话。
    func claudeTitle(for description: String) async -> String? {
        guard status(for: .claude).isReady, let executable = status(for: .claude).executable,
            let request = InstalledAIModel.claudeTitleRequest(description)
        else { return nil }
        let output = await InstalledAIProbe.request(
            executable: executable, arguments: Self.claudeControlArguments,
            workspace: workspace,
            environment: ExecutableLocator.environment(
                running: executable, inherited: launchSettings(.claude).inherited(for: .claude)),
            input: Data(request.utf8),
            until: { output in
                // 需要整行：ID 先于标题到达，所以一个分块可能在两者之间被切开。
                output.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
                    .contains { $0.contains(InstalledAIModel.claudeTitleRequestID) }
            })
        return InstalledAIModel.claudeTitle(output).flatMap(ChatTitle.sanitize)
    }

    /// 为指定已安装 CLI 构造提供方；Codex 与其他未就绪状态会招错。
    func provider(
        kind: InstalledAIKind, model: String, effort: String?,
        toolServers: AIToolServerSession? = nil
    ) throws -> any AIProvider {
        guard kind != .codex else {
            throw AIProviderError.unavailable("Codex is handled by its app-server connection.")
        }
        let status = status(for: kind)
        guard status.phase != .notInstalled else {
            throw AIProviderError.unavailable("Install " + kind.title + " before using this model.")
        }
        guard status.phase != .signInRequired else {
            throw AIProviderError.unavailable("Sign in with `" + kind.signInCommand + "` first.")
        }
        return InstalledCLIProvider(
            kind: kind, executable: status.executable, model: model, effort: effort,
            workspace: workspace, launch: launchSettings(kind), toolServers: toolServers)
    }

    /// 命令解析结果：找到可执行文件，或因某种原因不可用。
    private enum Command {
        case found(URL)
        case unavailable(InstalledAIStatus.Phase)
    }

    /// 根据启动设置解析要执行的命令：显式路径、路径缺失或自动查找。
    nonisolated private static func command(
        for kind: InstalledAIKind, launch: InstalledAILaunch
    ) async -> Command {
        switch launch.command() {
        case .executable(let url): return .found(url)
        case .missing(let path):
            return .unavailable(.failed(InstalledAILaunch.missingCommandMessage(path)))
        case .automatic:
            let found = await ExecutableLocator.locate(
                kind.command, extraHomePaths: kind.extraExecutablePaths)
            return found.map(Command.found) ?? .unavailable(.notInstalled)
        }
    }

    /// 探测单个已安装 CLI：先验证可运行与版本，再按工具类型检查登录与模型目录。
    nonisolated private static func probe(
        _ kind: InstalledAIKind, launch: InstalledAILaunch, workspace: URL
    ) async -> (InstalledAIKind, InstalledAIStatus) {
        let executable: URL
        switch await command(for: kind, launch: launch) {
        case .found(let url): executable = url
        case .unavailable(let phase): return (kind, InstalledAIStatus(phase: phase))
        }
        let environment = ExecutableLocator.environment(
            running: executable, inherited: launch.inherited(for: kind))
        let versionResult = await InstalledAIProbe.run(
            executable: executable, arguments: ["--version"], workspace: workspace,
            environment: environment)
        guard versionResult.status == 0 else {
            return (
                kind,
                InstalledAIStatus(
                    phase: .failed("The installed command could not run."),
                    executable: executable)
            )
        }
        let version = InstalledAIProbe.version(in: versionResult.output)
        switch kind {
        case .claude:
            let auth = await InstalledAIProbe.run(
                executable: executable, arguments: ["auth", "status", "--json"],
                workspace: workspace, environment: environment)
            let loggedIn = InstalledAIProbe.loggedIn(inStatusJSON: auth.output)
            guard auth.status == 0, loggedIn else {
                return (
                    kind,
                    InstalledAIStatus(
                        phase: .signInRequired, version: version, executable: executable)
                )
            }
            // 请求之后不再跟随提示词，因此 CLI 会应答并退出，不会调用模型。
            let catalog = await InstalledAIProbe.run(
                executable: executable, arguments: claudeControlArguments, workspace: workspace,
                environment: environment,
                input: Data(InstalledAIModel.claudeInitializeRequest.utf8),
                // 用户的 SessionStart 钩子会在 CLI 应答前执行，无论它们多慢。
                timeout: .seconds(30))
            let models = InstalledAIModel.claudeCatalog(catalog.output)
            return (
                kind,
                InstalledAIStatus(
                    phase: models.isEmpty
                        ? .failed("Claude listed no models. Update Claude Code, then Check Again.")
                        : .ready,
                    version: version, executable: executable, models: models,
                    account: InstalledAIModel.claudeAccount(catalog.output))
            )
        case .openCode:
            let models = await InstalledAIProbe.run(
                executable: executable, arguments: ["models", "--pure", "--verbose"],
                workspace: workspace, environment: environment)
            let catalog = InstalledAIModel.openCodeCatalog(models.output)
            return (
                kind,
                InstalledAIStatus(
                    phase: models.status == 0 && !catalog.isEmpty ? .ready : .signInRequired,
                    version: version, executable: executable, models: catalog)
            )
        case .grok:
            let models = await InstalledAIProbe.run(
                executable: executable, arguments: ["models"], workspace: workspace, environment: environment)
            let catalog = InstalledAIModel.grokCatalog(models.output)
            let signedIn = models.status == 0 && InstalledAIModel.grokSignedIn(models.output)
            return (
                kind,
                InstalledAIStatus(
                    phase: signedIn && !catalog.isEmpty ? .ready : .signInRequired,
                    version: version, executable: executable,
                    models: signedIn ? catalog : [])
            )
        case .cursor:
            let auth = await InstalledAIProbe.run(
                executable: executable, arguments: ["status", "--format", "json"],
                workspace: workspace, environment: environment)
            let loggedIn = InstalledAIProbe.loggedIn(inStatusJSON: auth.output)
            guard auth.status == 0, loggedIn else {
                return (
                    kind,
                    InstalledAIStatus(
                        phase: .signInRequired, version: version, executable: executable)
                )
            }
            let models = await InstalledAIProbe.run(
                executable: executable, arguments: ["--list-models"], workspace: workspace,
                environment: environment)
            let catalog = InstalledAIModel.cursorCatalog(models.output)
            return (
                kind,
                InstalledAIStatus(
                    phase: models.status == 0 && !catalog.isEmpty
                        ? .ready
                        : .failed(
                            "Cursor returned no models."),
                    version: version, executable: executable, models: catalog)
            )
        case .codex:
            return (kind, InstalledAIStatus(phase: .idle))
        }
    }
}
