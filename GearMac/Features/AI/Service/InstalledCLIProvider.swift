// 文件职责：通过子进程驱动已安装的 CLI（Claude/OpenCode/Grok/Cursor）完成一轮生成，并解析其流式输出。
// 分层：Service；主 actor 上持有进程与缓冲，一次只能有一轮进行，结束时会清理临时文件与会话。
import Foundation

/// 已安装 CLI 提供方：把流式请求转发给内部的轮次运行器。
struct InstalledCLIProvider: AIProvider {
    private let runner: InstalledCLITurnRunner

    /// 构造时把参数交给轮次运行器；运行器在主 actor 上持有。
    @MainActor
    init(
        kind: InstalledAIKind, executable: URL?, model: String, effort: String?, workspace: URL,
        launch: InstalledAILaunch = InstalledAILaunch(), toolServers: AIToolServerSession? = nil
    ) {
        runner = InstalledCLITurnRunner(
            kind: kind, executable: executable, model: model, effort: effort,
            workspace: workspace, launch: launch, toolServers: toolServers)
    }

    /// 把流式请求转发给内部的轮次运行器。
    func stream(_ request: AIRequest) -> AIProviderStream {
        runner.stream(request)
    }
}

/// 已安装 CLI 的一轮运行：启动子进程、写入提示词、解析输出并维护会话与临时文件。
@MainActor
private final class InstalledCLITurnRunner {
    private static let safetyInstructions = """
        You are generating text inside GearMac. Do not invoke tools, read files, inspect the \
        environment, access external resources, or modify anything. Use only the conversation and \
        instructions in this request.
        """
    /// 同样的边界，但对象是唯一被交出工具的路由：其余一切保持关闭。
    private static let toolSafetyInstructions = """
        You are generating text inside GearMac. The only tools you may use are the MCP tools \
        supplied with this request. Do not read files, inspect the environment, access external \
        resources, or modify anything else.
        """

    /// 单行输出的字节上限（可由环境变量覆盖），超过即判定响应异常。
    private static var maximumPartialLineBytes: Int {
        if let raw = ProcessInfo.processInfo.environment["TC_INSTALLED_MAX_LINE_BYTES"],
            let value = Int(raw), value > 0
        {
            return value
        }
        return 8 * 1_048_576
    }

    /// 单个流的引用标识。
    private final class TurnToken: Sendable {}

    private let kind: InstalledAIKind
    private let configuredExecutable: URL?
    private let model: String
    private let effort: String?
    private let workspace: URL
    private let launch: InstalledAILaunch
    private let toolServers: AIToolServerSession?

    private var token: TurnToken?
    private var process: Process?
    private var continuation: AIProviderStream.Continuation?
    private var outputBuffer = Data()
    private var errorBuffer = Data()
    private var turnSessionID: String?
    private var promptFileURL: URL?
    private var activeExecutable: URL?
    /// 本轮装载的服务器；未装载任何服务器的路由与轮次都为空。
    private var activeServers: [AIToolServer] = []
    private var mcpConfigURL: URL?
    private var input: FileHandle?
    private var consents: [Task<Void, Never>] = []
    /// 串行而非并发：两个写入竞争同一管道会交错出一行残缺的内容。
    private var writes: Task<Void, Never> = Task {}

    /// 保存本轮参数；可执行文件与工具服务器均为可选。
    init(
        kind: InstalledAIKind, executable: URL?, model: String, effort: String?, workspace: URL,
        launch: InstalledAILaunch, toolServers: AIToolServerSession? = nil
    ) {
        self.kind = kind
        self.launch = launch
        configuredExecutable = executable
        self.model = model
        self.effort = effort
        self.workspace = workspace
        self.toolServers = toolServers
    }

    /// 以流的形式发起一轮：内部启动任务驱动，流终止时取消任务并收尾。
    nonisolated func stream(_ request: AIRequest) -> AIProviderStream {
        AIProviderStream { continuation in
            let token = TurnToken()
            let task = Task { [weak self] in
                await self?.start(request, continuation: continuation, token: token)
            }
            continuation.onTermination = { [weak self] _ in
                task.cancel()
                Task { @MainActor in self?.cancel(token) }
            }
        }
    }

    /// 一轮的主流程：解析可执行文件与工具、写入私有临时文件、启动进程并送入提示词。
    private func start(
        _ request: AIRequest, continuation: AIProviderStream.Continuation, token: TurnToken
    ) async {
        guard kind != .codex else {
            continuation.finish(
                throwing: AIProviderError.unavailable("Codex requires its app-server adapter."))
            return
        }
        guard
            request.messages.contains(where: {
                $0.role == .user
                    && (!$0.images.isEmpty
                        || !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            })
        else {
            continuation.finish(
                throwing: AIProviderError.unavailable("There is no user message to send."))
            return
        }
        let resolvedExecutable: URL?
        switch launch.command() {
        case .executable(let url):
            resolvedExecutable = url
        case .missing(let path):
            continuation.finish(
                throwing: AIProviderError.unavailable(
                    InstalledAILaunch.missingCommandMessage(path)))
            return
        case .automatic:
            if let configuredExecutable {
                resolvedExecutable = configuredExecutable
            } else {
                resolvedExecutable = await ExecutableLocator.locate(
                    kind.command, extraHomePaths: kind.extraExecutablePaths)
            }
        }
        guard let executable = resolvedExecutable else {
            continuation.finish(
                throwing: AIProviderError.unavailable(
                    "Install " + kind.title + " before using this model."))
            return
        }
        if Task.isCancelled {
            continuation.finish(throwing: CancellationError())
            return
        }
        cancelActiveTurn()
        do {
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: workspace.path)
        } catch {
            continuation.finish(
                throwing: AIProviderError.unavailable(
                    "GearMac could not prepare its private AI workspace."))
            return
        }

        activeServers = await resolvedToolServers()
        let prompt = prompt(for: request)
        var configURL: URL?
        if !activeServers.isEmpty {
            let url = workspace.appending(path: ClaudeMCPLaunch.configurationFileName())
            do {
                try await Self.writePrivateFile(
                    ClaudeMCPLaunch.configuration(servers: activeServers), to: url)
            } catch {
                try? FileManager.default.removeItem(at: url)
                activeServers = []
                continuation.finish(
                    throwing: AIProviderError.unavailable(
                        "GearMac could not write its private MCP configuration."))
                return
            }
            configURL = url
        }

        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executable
        process.currentDirectoryURL = workspace
        process.environment = environment(for: executable)
        var grokPrompt: URL?
        if kind == .grok {
            let url = workspace.appending(path: "gearmac-prompt-\(UUID().uuidString).txt")
            do {
                try await Self.writePromptFile(prompt, to: url)
            } catch {
                try? FileManager.default.removeItem(at: url)
                continuation.finish(
                    throwing: AIProviderError.unavailable(
                        "GearMac could not write its private AI prompt."))
                return
            }
            grokPrompt = url
            process.standardInput = FileHandle.nullDevice
        } else {
            process.standardInput = stdin
        }
        process.arguments = arguments(promptFile: grokPrompt, mcpConfig: configURL)
        process.standardOutput = stdout
        process.standardError = stderr
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.consume(data, token: token) }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.consumeError(data, token: token) }
        }
        // 有意强引用：运行器必须比它的提供方活得更久，才能在进程退出时做清理。
        process.terminationHandler = { [self] process in
            let status = process.terminationStatus
            Task { @MainActor in self.didExit(status: status, token: token) }
        }
        if Task.isCancelled {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            if let grokPrompt { try? FileManager.default.removeItem(at: grokPrompt) }
            if let configURL { try? FileManager.default.removeItem(at: configURL) }
            continuation.finish(throwing: CancellationError())
            return
        }
        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            if let grokPrompt { try? FileManager.default.removeItem(at: grokPrompt) }
            if let configURL { try? FileManager.default.removeItem(at: configURL) }
            continuation.finish(
                throwing: AIProviderError.responseFailed(
                    kind.title + " could not start: " + error.localizedDescription))
            return
        }
        promptFileURL = grokPrompt
        mcpConfigURL = configURL
        self.process = process
        activeExecutable = executable
        self.token = token
        self.continuation = continuation
        guard kind != .grok else { return }
        input = stdin.fileHandleForWriting
        // 子进程在读取前退出时，写入必须返回失败，而不是让 GearMac 收到 SIGPIPE。
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        guard kind == .claude else {
            write(Data(prompt.utf8), closing: true)
            return
        }
        // 以 JSON 帧格式发送，使图片作为内容块与文本并列。
        let images = request.messages.last { $0.role == .user }?.images ?? []
        guard let line = ClaudeControlProtocol.userMessage(prompt, images: images) else {
            fail("GearMac could not frame the request for " + kind.title + ".")
            return
        }
        // 工具循环会在同一管道上应答，因此已装配的轮次保持 stdin 打开。
        write(line, closing: activeServers.isEmpty)
    }

    /// 管道写入一旦超出缓冲区就会阻塞直到子进程读取，因此绝不在主 actor 上执行。
    private func write(_ data: Data, closing: Bool) {
        guard let input else { return }
        if closing { self.input = nil }
        let previous = writes
        writes = Task.detached {
            await previous.value
            try? input.write(contentsOf: data)
            if closing { try? input.close() }
        }
    }

    /// 将提示词写入临时文件（Grok 路由使用）。
    nonisolated private static func writePromptFile(_ prompt: String, to url: URL) async throws {
        try await Task.detached {
            try Data(prompt.utf8).write(to: url)
        }.value
    }

    /// 以 `0600` 创建：`createFile` 会先写一个 `0644` 临时文件，事后再收权限。
    nonisolated private static func writePrivateFile(_ text: String, to url: URL) async throws {
        try await Task.detached {
            let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
            guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
            let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            try file.write(contentsOf: Data(text.utf8))
            try file.close()
        }.value
    }

    /// 本轮可提供的工具：除非路由是 Claude 且已装配 MCP，否则一律为空。
    private func resolvedToolServers() async -> [AIToolServer] {
        guard kind == .claude, let toolServers, !InstalledAIManager.hasManagedMCPPolicy else {
            return []
        }
        return await toolServers.servers()
    }

    /// 无可调用工具时只需一次请求；已装配的轮次采用用户的轮数上限，可能为无上限。
    private var roundCap: Int? { activeServers.isEmpty ? 1 : toolServers?.rounds }

    /// 按路由类型拼装命令行参数。
    private func arguments(promptFile: URL? = nil, mcpConfig: URL? = nil) -> [String] {
        switch kind {
        case .claude:
            var result = [
                "-p",
                "--model", model,
                "--input-format", "stream-json",
                "--output-format", "stream-json",
                // `-p` 运行只有在指定显示方式时才会输出思考文本；此项设置否则会被忽略。
                "--thinking-display", "summarized",
                "--verbose",
                "--include-partial-messages",
                "--no-session-persistence",
                "--disable-slash-commands",
                "--tools", "",
                // `--bare` 不在此列：它会拒绝整个路由所复用的 OAuth 登录。
                "--no-chrome",
                "--system-prompt",
                mcpConfig == nil ? Self.safetyInstructions : Self.toolSafetyInstructions
            ]
            if let mcpConfig {
                result += ClaudeMCPLaunch.arguments(
                    configurationPath: mcpConfig.path, handles: activeServers.map(\.handle),
                    rounds: roundCap)
            } else {
                // 无可调用工具的路由会关掉所有工具，并把轮次限制为一次请求。
                result += ["--disallowedTools", "*", "--max-turns", "1"]
                result += InstalledAIManager.claudeWithoutMCPArguments
            }
            if let effort { result += ["--effort", effort] }
            return result
        case .openCode:
            var result = [
                "run", "--pure", "--format", "json", "--model", model,
                "--dir", workspace.path, "--title", "GearMac"
            ]
            if let effort { result += ["--variant", effort] }
            return result
        case .grok:
            var result = [
                "--prompt-file", promptFile?.path ?? "",
                "--output-format", "streaming-messages-json",
                "--include-partial-messages",
                "--model", model,
                "--max-turns", "1",
                "--no-subagents",
                "--disable-web-search",
                "--no-plan",
                "--permission-mode", "dontAsk",
                "--tools", "",
                "--deny", "*",
                "--disallowed-tools", "Agent",
                // strict 会在 /var/run/docker.sock 是符号链接时拒绝启动。
                "--sandbox", "workspace",
                "--verbatim",
                "--cwd", workspace.path,
                "--rules", Self.safetyInstructions
            ]
            if let effort { result += ["--effort", effort] }
            return result
        case .cursor:
            return [
                "-p",
                "--mode", "ask",
                "--trust",
                "--workspace", workspace.path,
                "--model", model,
                "--output-format", "stream-json",
                "--stream-partial-output"
            ]
        case .codex:
            return []
        }
    }

    /// 组装子进程环境：定位器提供的基础环境叠加该工具受管的环境变量。
    private func environment(for executable: URL) -> [String: String] {
        ExecutableLocator.environment(
            running: executable, inherited: launch.inherited(for: kind)
        ).merging(kind.managedEnvironment) { _, managed in managed }
    }

    /// 把整轮对话拼成单一提示词文本，含安全边界、指令与各角色消息。
    private func prompt(for request: AIRequest) -> String {
        var sections = [
            activeServers.isEmpty ? Self.safetyInstructions : Self.toolSafetyInstructions
        ]
        if let instructions = request.instructions?.trimmingCharacters(in: .whitespacesAndNewlines),
            !instructions.isEmpty
        {
            sections.append("Instructions:\n" + instructions)
        }
        for message in request.messages {
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let role: String
            switch message.role {
            case .system: role = "System instructions"
            case .user: role = "User"
            case .assistant: role = "Assistant"
            case .tool: role = "Tool result"
            }
            sections.append(role + ":\n" + text)
        }
        return sections.joined(separator: "\n\n")
    }

    /// 按行拆分 stdout 并应用每一帧；单行超限则判定失败。
    private func consume(_ data: Data, token: TurnToken) {
        guard self.token === token else { return }
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            if line.count > Self.maximumPartialLineBytes {
                fail(kind.title + " returned an oversized response.")
                return
            }
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            apply(
                InstalledAIStreamDecoder.decode(
                    Data(line), kind: kind, servers: activeServers), token: token)
        }
        if outputBuffer.count > Self.maximumPartialLineBytes {
            fail(kind.title + " returned an oversized response.")
        }
    }

    /// 应用一帧解析结果：记录会话 ID、应答控制请求、转发事件并判定结束/出错。
    private func apply(_ frame: InstalledAIStreamFrame, token: TurnToken) {
        if let sessionID = frame.sessionID { turnSessionID = sessionID }
        if let request = frame.controlRequest {
            answer(request, token: token)
            return
        }
        if let id = frame.unsupportedRequestID {
            let refusal = "GearMac does not answer this request."
            if let line = ClaudeControlProtocol.error(to: id, message: refusal) {
                write(line, closing: false)
            }
            return
        }
        for event in frame.events { continuation?.yield(event) }
        if frame.stoppedAtRoundCap {
            fail(
                roundCap.map { "Stopped after \($0) rounds of tool calls." }
                    ?? kind.title + " could not finish the response.")
        } else if let error = frame.error {
            fail(error)
        } else if frame.completed {
            continuation?.yield(.finished)
            continuation?.finish()
            continuation = nil
            // stream-json 轮次已应答；关闭 stdin 才是让子进程离开的信号。
            write(Data(), closing: true)
        }
    }

    /// 按用户决定回复工具征询，使用与 BYOK 循环相同的信任策略与对话框。
    private func answer(_ request: ClaudeControlProtocol.Request, token: TurnToken) {
        consents.append(
            Task { [weak self] in
                let allowed = await self?.toolServers?.consent(request.call) ?? false
                guard let self, self.token === token else { return }
                guard
                    let line = ClaudeControlProtocol.response(
                        to: request, allowed: allowed,
                        message: "The user declined this tool call.")
                else { return }
                self.write(line, closing: false)
            })
    }

    /// 仍在排队的征询属于一个已结束的轮次，因此再也不会被提问。
    private func cancelConsents() {
        for consent in consents { consent.cancel() }
        consents = []
    }

    /// 保留 stderr 尾部若干字节，仅供退出时的错误详情使用。
    private func consumeError(_ data: Data, token: TurnToken) {
        guard self.token === token else { return }
        errorBuffer.append(data)
        if errorBuffer.count > 16_384 { errorBuffer.removeFirst(errorBuffer.count - 16_384) }
    }

    /// 子进程退出：未完成时报错，随后删除会话与清理本轮状态。
    private func didExit(status: Int32, token: TurnToken) {
        guard self.token === token else { return }
        if continuation != nil {
            let detail = (String(bytes: errorBuffer, encoding: .utf8) ?? "")
                .replacingOccurrences(
                    of: "\u{001B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = kind.title + " exited with status " + String(status) + "."
            fail(detail.isEmpty ? fallback : detail)
        }
        deleteTurnSession()
        cleanup()
    }

    /// 以错误结束当前流并终止子进程。
    private func fail(_ message: String) {
        continuation?.finish(throwing: AIProviderError.responseFailed(message))
        continuation = nil
        process?.terminate()
    }

    /// 取消指定轮次；非当前轮次则忽略。
    private func cancel(_ token: TurnToken) {
        guard self.token === token else { return }
        cancelActiveTurn()
    }

    /// 取消本轮：停止征询、结束流、终止进程、清空缓冲并删除临时文件。
    private func cancelActiveTurn() {
        cancelConsents()
        continuation?.finish(throwing: CancellationError())
        continuation = nil
        process?.terminate()
        outputBuffer.removeAll(keepingCapacity: false)
        errorBuffer.removeAll(keepingCapacity: false)
        removePrivateFiles()
    }

    /// 两者都是本轮私有：无人可读的提示词，以及一份满是密钥的配置。
    private func removePrivateFiles() {
        if let promptFileURL {
            try? FileManager.default.removeItem(at: promptFileURL)
        }
        promptFileURL = nil
        if let mcpConfigURL {
            try? FileManager.default.removeItem(at: mcpConfigURL)
        }
        mcpConfigURL = nil
    }

    /// 删除本轮在 CLI 侧创建的会话（OpenCode/Grok 调 CLI 删除，Cursor 删本地目录）。
    private func deleteTurnSession() {
        guard let sessionID = turnSessionID else { return }
        turnSessionID = nil
        switch kind {
        case .openCode, .grok:
            guard let executable = activeExecutable else { return }
            let arguments =
                kind == .grok
                ? ["sessions", "delete", sessionID] : ["session", "delete", sessionID, "--pure"]
            let workspace = workspace
            let environment = environment(for: executable)
            Task.detached {
                Self.deleteCLISession(
                    arguments: arguments, executable: executable, workspace: workspace,
                    environment: environment)
            }
        case .cursor:
            let root = Self.cursorChatsRoot()
            Task.detached { Self.deleteCursorChat(sessionID, root: root) }
        case .claude, .codex:
            break
        }
    }

    /// 同步调用 CLI 删除会话，忽略输出与错误。
    nonisolated private static func deleteCLISession(
        arguments: [String], executable: URL, workspace: URL, environment: [String: String]
    ) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workspace
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.runObservingExit().wait()
    }

    /// Cursor CLI 没有删除聊天的命令；聊天保存在 `~/.cursor/chats/<workspace>/<id>` 下。
    nonisolated private static func deleteCursorChat(_ sessionID: String, root: URL) {
        let fm = FileManager.default
        guard let workspaces = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        else { return }
        for workspace in workspaces {
            try? fm.removeItem(
                at: workspace.appending(path: sessionID, directoryHint: .isDirectory))
        }
    }

    /// Cursor 聊天目录的根路径（可由环境变量覆盖，便于测试）。
    private static func cursorChatsRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["TC_CURSOR_CHATS_ROOT"],
            !override.isEmpty
        {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(
            path: ".cursor/chats", directoryHint: .isDirectory)
    }

    /// 清理本轮全部资源：征询、进程回调、缓冲、会话与临时文件。
    private func cleanup() {
        cancelConsents()
        process?.terminationHandler = nil
        (process?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        (process?.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process = nil
        token = nil
        continuation = nil
        outputBuffer.removeAll(keepingCapacity: false)
        errorBuffer.removeAll(keepingCapacity: false)
        turnSessionID = nil
        removePrivateFiles()
        activeExecutable = nil
        activeServers = []
        write(Data(), closing: true)
    }
}
