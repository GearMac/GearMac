// 文件职责：以子进程方式驱动 Codex app-server，完成 JSON-RPC 握手、请求/通知分发与进程生命周期管理。
// 分层：Service；主 actor 上运行，子进程的 stdout/stderr 读取与退出事件都回到主 actor 处理。
import Foundation

/// Codex app-server 客户端：管理与子进程的连接，并把 JSON-RPC 消息对应到请求与回调。
@MainActor
final class CodexAppServerClient {
    /// 客户端错误：覆盖可执行文件缺失、启动失败、进程退出、请求失败与超时。
    enum ClientError: LocalizedError {
        case executableMissing
        case launchFailed(String)
        case processExited(String)
        case requestFailed(String)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .executableMissing:
                return "Install the Codex CLI to use your Codex account."
            case .launchFailed(let detail): return "Codex could not start: \(detail)"
            case .processExited(let detail), .requestFailed(let detail): return detail
            case .timedOut: return "Codex did not respond in time."
            }
        }
    }

    /// 一个已发出但尚未得到响应的请求：等待中的 continuation 及其超时任务。
    private struct PendingRequest {
        let continuation: CheckedContinuation<[String: JSONValue], Error>
        let timeout: Task<Void, Never>
    }

    var onNotification: ((String, [String: JSONValue]) -> Void)?
    var onExit: ((String) -> Void)?
    /// 回答一次工具调用的征询；返回 nil 或 false 都表示拒绝。
    var onElicitation: ((CodexElicitation) async -> Bool)?
    /// 即将用新启动替换正在运行的进程，该进程的线程也会随之消失。
    var onRelaunch: (() -> Void)?
    /// 用户的命令路径与环境变量；每次启动时询问，使修改能在下一次启动生效。
    var launchSettings: () -> InstalledAILaunch = { InstalledAILaunch() }

    private let codexHome: URL?
    let workspace: URL
    /// 最后一次启动所执行的命令；进程停止后仍保留，使设置页能继续显示它。
    private(set) var executable: URL?
    private var process: Process?
    private var processID: UUID?
    private var input: FileHandle?
    private var outputBuffer = Data()
    private var stderrBuffer = Data()
    private var nextID = 1
    private var pending: [Int: PendingRequest] = [:]
    /// 进程启动时的参数；它们在 exec 时已固定，因此清单不同就会重新启动。
    private(set) var toolServers: [AIToolServer] = []
    private var elicitations: [(threadID: String?, task: Task<Void, Never>)] = []
    private var pendingLaunch: (id: UUID, servers: [AIToolServer], task: Task<Void, Error>)?
    /// 由 `stop` 递增，使一个仍在读清单的启动不会在它之后再起进程。
    private var generation = 0

    init(codexHome: URL? = nil, workspace: URL) {
        self.codexHome = codexHome
        self.workspace = workspace
    }

    /// 仅作用于本进程，绝不写入用户的配置；`plugins=false` 关掉插件自带的服务器。
    nonisolated private static let configurationFlags = [
        "-c", "check_for_update_on_startup=false",
        "-c", "features.apps=false",
        "-c", "features.plugins=false",
        "-c", "features.remote_plugin=false",
        "-c", "features.plugin_sharing=false",
        "-c", "features.shell_tool=false",
        "-c", "features.unified_exec=false",
        "-c", "features.browser_use=false",
        "-c", "features.in_app_browser=false",
        "-c", "features.computer_use=false",
        "-c", "features.image_generation=false",
        "-c", "features.multi_agent=false",
        "-c", "features.hooks=false",
        "-c", "features.workspace_dependencies=false",
        "-c", "memories.use_memories=false"
    ]

    /// 用户自己的服务器清单，在 app-server 的参数下读取；读取失败时返回 `nil`。
    nonisolated static func foreignServerNames(
        executable: URL, workspace: URL, codexHome: URL?,
        inherited: [String: String] = ProcessInfo.processInfo.environment
    ) async -> [String]? {
        var environment = ExecutableLocator.environment(running: executable, inherited: inherited)
        if let codexHome { environment["CODEX_HOME"] = codexHome.path }
        let result = await InstalledAIProbe.run(
            executable: executable, arguments: configurationFlags + ["mcp", "list", "--json"],
            workspace: workspace, environment: environment)
        guard result.status == 0 else { return nil }
        return CodexMCPLaunch.foreignNames(listing: result.output)
    }

    /// 进程是否正在运行。
    var isRunning: Bool { process?.isRunning == true }

    /// 同一时刻只允许一次启动（含握手）；同一清单的所有调用方都会等待它完成。
    func start(toolServers: [AIToolServer] = []) async throws {
        while let pending = pendingLaunch {
            if pending.servers == toolServers { return try await pending.task.value }
            _ = await pending.task.result
        }
        if isRunning, self.toolServers == toolServers { return }
        let id = UUID()
        let task = Task {
            defer { if pendingLaunch?.id == id { pendingLaunch = nil } }
            try await launch(toolServers)
        }
        pendingLaunch = (id, toolServers, task)
        try await task.value
    }

    /// 状态检查没有自己的清单：它加入任何待处理或正在运行的启动。
    func startForCheck() async throws {
        // 启动失败不会回答这次检查，因此它会自行以无清单方式重新启动。
        while let pending = pendingLaunch { _ = await pending.task.result }
        if isRunning { return }
        try await start()
    }

    private func launch(_ toolServers: [AIToolServer]) async throws {
        let generation = self.generation
        let settings = launchSettings()
        let executable: URL
        switch settings.command() {
        case .executable(let url):
            executable = url
        case .missing(let path):
            throw ClientError.launchFailed(InstalledAILaunch.missingCommandMessage(path))
        case .automatic:
            guard let found = await ExecutableLocator.locate("codex") else {
                throw ClientError.executableMissing
            }
            executable = found
        }
        self.executable = executable
        let inherited = settings.inherited(for: .codex)
        try checkNotStopped(since: generation)
        // 清单只能在启动时读取，因此无法说服旧进程改用新清单。
        if isRunning {
            onRelaunch?()
            stop(error: ClientError.processExited("Codex stopped."))
        }
        guard let secrets = CodexMCPLaunch.environment(servers: toolServers) else {
            throw ClientError.launchFailed("Two MCP servers' secrets would share one variable.")
        }
        do {
            try FileManager.default.createDirectory(
                at: workspace, withIntermediateDirectories: true)
            if let codexHome {
                try FileManager.default.createDirectory(
                    at: codexHome, withIntermediateDirectories: true)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o700], ofItemAtPath: codexHome.path)
            }
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: workspace.path)
        } catch {
            throw ClientError.launchFailed("Its private support folder could not be prepared.")
        }

        // 若无法读取，用户自己的服务器就会在聊天里启动；因此 Codex 也不能启动。
        guard
            let foreign = await Self.foreignServerNames(
                executable: executable, workspace: workspace, codexHome: codexHome,
                inherited: inherited)
        else {
            throw ClientError.launchFailed(
                "GearMac could not read which MCP servers your Codex configuration runs, so it "
                    + "could not keep them out of the chat. Run \u{201C}codex mcp list\u{201D} "
                    + "in Terminal to see why.")
        }
        try checkNotStopped(since: generation)
        if let name = CodexMCPLaunch.unaddressableName(foreign) {
            throw ClientError.launchFailed(
                "Your Codex MCP server \u{201C}\(name)\u{201D} cannot be kept out of a GearMac "
                    + "chat, because a dot or an equals sign in its name cannot be addressed. "
                    + "Rename it in your Codex configuration.")
        }
        if let taken = CodexMCPLaunch.takenName(servers: toolServers, foreignNames: foreign) {
            throw ClientError.launchFailed(
                "Your Codex configuration has its own MCP server named \u{201C}\(taken)\u{201D}. "
                    + "Rename it to use this GearMac server with Codex.")
        }
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executable
        process.arguments =
            Self.configurationFlags
            + CodexMCPLaunch.arguments(servers: toolServers, disabling: foreign)
            + ["app-server"]
        process.currentDirectoryURL = workspace
        var environment = ExecutableLocator.environment(
            running: executable, adding: secrets, inherited: inherited)
        // 测试可以隔离 app-server 状态；生产环境则有意继承用户自己的 Codex home。
        if let codexHome { environment["CODEX_HOME"] = codexHome.path }
        process.environment = environment
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.consumeOutput(data) }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.consumeStderr(data) }
        }
        let launchID = UUID()
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor in self?.didExit(launchID, status: status) }
        }
        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            throw ClientError.launchFailed(error.localizedDescription)
        }
        self.process = process
        processID = launchID
        // 服务端在写入中途死掉时，写入必须返回失败，而不是让 GearMac 收到 SIGPIPE。
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        input = stdin.fileHandleForWriting
        self.toolServers = toolServers

        // 若握手失败，否则会让一个未初始化的服务器仍被当作 `isRunning`。
        do {
            _ = try await request(
                method: "initialize",
                params: [
                    "clientInfo": [
                        "name": "gearmac",
                        "title": "GearMac",
                        "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                            ?? "0"
                    ],
                    "capabilities": ["experimentalApi": false]
                ])
            try send(CodexAppServerProtocol.notification(method: "initialized"))
        } catch {
            stop()
            throw error
        }
    }

    /// 发送一次请求并等待其响应；未运行时抛错，超时或取消都会结束等待。
    func request(
        method: String, params: [String: Any] = [:], timeout: Duration = .seconds(15)
    ) async throws -> [String: JSONValue] {
        guard isRunning else { throw ClientError.processExited("Codex is not running.") }
        let id = nextID
        nextID += 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    guard !Task.isCancelled else { return }
                    self?.timeoutRequest(id)
                }
                pending[id] = PendingRequest(continuation: continuation, timeout: timeoutTask)
                do {
                    try send(CodexAppServerProtocol.request(id: id, method: method, params: params))
                } catch {
                    finishRequest(id, with: .failure(error))
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.finishRequest(id, with: .failure(CancellationError()))
            }
        }
    }

    /// 仍在排队的征询属于一个已结束的轮次，因此再也不会被提问。
    func cancelElicitations(threadID: String) {
        for elicitation in elicitations where elicitation.threadID == threadID {
            elicitation.task.cancel()
        }
        elicitations.removeAll { $0.threadID == threadID }
    }

    /// 递增代号并停止进程，使进行中的启动也失效。
    func stop() {
        generation += 1
        stop(error: ClientError.processExited("Codex stopped."))
    }

    /// 启动读取清单期间发生的 `stop` 优先于这次启动。
    private func checkNotStopped(since generation: Int) throws {
        guard generation == self.generation else {
            throw ClientError.processExited("Codex stopped.")
        }
    }

    /// 关闭 stdin 是干净退出（服务端遇 EOF 即离开），SIGTERM 只是兜底。
    private func stop(error: ClientError) {
        guard let process else { return }
        process.terminationHandler = nil
        cleanup(error: error)
        Task.detached {
            try? await Task.sleep(for: .seconds(1))
            if process.isRunning { process.terminate() }
        }
    }

    /// 将数据写入子进程 stdin；无可用句柄时抛错。
    private func send(_ data: Data) throws {
        guard let input else { throw ClientError.processExited("Codex is not running.") }
        try input.write(contentsOf: data)
    }

    /// 按行拆分 stdout 并逐条处理；缓冲出现超长未终止行则判定对方不是 app-server 并断开。
    private func consumeOutput(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            handle(CodexAppServerProtocol.parse(Data(line)))
        }
        // 未终止的超大行说明通话对象并不是 app-server。
        guard outputBuffer.count > Self.outputLimit else { return }
        let message = "Codex sent an unterminated oversized response and was disconnected."
        onExit?(message)
        stop(error: ClientError.processExited(message))
    }

    private static let outputLimit = 8 * 1_048_576

    /// 将一条已解析的消息分发到响应回调、通知或服务端发起的请求。
    private func handle(_ message: CodexAppServerProtocol.Message) {
        switch message {
        case .response(let id, let result):
            finishRequest(id, with: .success(result))
        case .failure(let id, let message):
            finishRequest(id, with: .failure(ClientError.requestFailed(message)))
        case .notification(let method, let params):
            onNotification?(method, params)
        case .request(let id, let method, let params):
            guard method == "mcpServer/elicitation/request",
                let elicitation = CodexElicitation(params: params), let onElicitation
            else {
                declineServerRequest(id: id, method: method)
                return
            }
            let task = Task { [weak self] in
                let action: CodexElicitation.Action =
                    await onElicitation(elicitation) ? .accept : .decline
                // `persist` 永不会被应答：只有设置页才能改变一个长期生效的决定。
                try? self?.send(
                    CodexAppServerProtocol.response(id: id, result: ["action": action.rawValue]))
            }
            elicitations.append((elicitation.threadID, task))
        case .invalid:
            break
        }
    }

    /// 以拒绝语义回答 GearMac 不处理的各类服务端请求。
    private func declineServerRequest(id: CodexAppServerProtocol.RequestID, method: String) {
        let result: [String: Any]
        switch method {
        case "item/commandExecution/requestApproval", "item/fileChange/requestApproval":
            result = ["decision": "cancel"]
        case "item/permissions/requestApproval":
            result = [
                "permissions": [
                    "fileSystem": ["entries": []],
                    "network": ["enabled": false]
                ]
            ]
        case "tool/requestUserInput":
            result = ["answers": [:]]
        case "mcpServer/elicitation/request":
            // 一个表单，或者一个未装载任何工具的轮次上的调用：二者都不是 GearMac 会提的问题。
            result = ["action": CodexElicitation.Action.decline.rawValue]
        default:
            try? send(
                CodexAppServerProtocol.errorResponse(
                    id: id, message: "GearMac does not expose Codex tools."))
            return
        }
        try? send(CodexAppServerProtocol.response(id: id, result: result))
    }

    /// 保留 stderr 尾部若干字节，仅作退出时的错误详情使用；
    private func consumeStderr(_ data: Data) {
        stderrBuffer.append(data)
        if stderrBuffer.count > 8_192 { stderrBuffer.removeFirst(stderrBuffer.count - 8_192) }
    }

    /// 以超时错误收束某个请求的等待。
    private func timeoutRequest(_ id: Int) {
        finishRequest(id, with: .failure(ClientError.timedOut))
    }

    /// 结束一个待处理请求：取消其超时任务并以给定结果恢复 continuation。
    private func finishRequest(_ id: Int, with result: Result<[String: JSONValue], Error>) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeout.cancel()
        request.continuation.resume(with: result)
    }

    /// 已被本客户端替换或停止的进程无需再做清理。
    private func didExit(_ exited: UUID, status: Int32) {
        guard exited == processID else { return }
        let detail = String(decoding: stderrBuffer, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let message = detail.isEmpty ? "Codex exited with status \(status)." : detail
        onExit?(message)
        cleanup(error: ClientError.processExited(message))
    }

    /// 清理进程、管道、缓冲与待处理请求，并把错误传播给所有等待中的调用方。
    private func cleanup(error: Error) {
        for elicitation in elicitations { elicitation.task.cancel() }
        elicitations = []
        toolServers = []
        process?.terminationHandler = nil
        (process?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        (process?.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        try? input?.close()
        process = nil
        processID = nil
        input = nil
        outputBuffer.removeAll(keepingCapacity: false)
        stderrBuffer.removeAll(keepingCapacity: false)
        let requests = pending
        pending.removeAll()
        for request in requests.values {
            request.timeout.cancel()
            request.continuation.resume(throwing: error)
        }
    }
}
