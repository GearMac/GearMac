// 文件职责：通过子进程的 stdin/stdout 与本地 MCP 服务器通信，逐行收发 JSON-RPC 消息。
// 分层：Service；@MainActor 管理进程、按 id 关联请求与响应，不 import AppKit/SwiftUI。
import Foundation

/// 基于子进程 stdin/stdout 的本地服务器，每行一条以换行分隔的 JSON-RPC 消息。
@MainActor
final class MCPStdioTransport: MCPTransport {
    /// 一条已发出但尚未收到响应的请求，及其超时看门狗。
    private struct PendingRequest {
        let continuation: CheckedContinuation<JSONValue, Error>
        let timeout: Task<Void, Never>
    }

    var onNotification: ((String, JSONValue) -> Void)?
    var onExit: ((String) -> Void)?

    private let command: String
    private let arguments: [String]
    private let environment: [String: String]
    private var process: Process?
    private var input: FileHandle?
    private var outputBuffer = Data()
    private var stderrBuffer = Data()
    private var nextID = 1
    private var pending: [Int: PendingRequest] = [:]

    /// 未以换行结尾的一行达到此长度，说明对面通信的并不是 MCP 服务器。
    private static let outputLimit = 8 * 1_048_576
    private static let stderrLimit = 8_192

    init(command: String, arguments: [String], environment: [String: String]) {
        self.command = command
        self.arguments = arguments
        self.environment = environment
    }

    var isRunning: Bool { process?.isRunning == true }

    /// 启动子进程并接管其 stdin/stdout/stderr；已运行时直接返回。
    func connect() async throws {
        if isRunning { return }
        guard let executable = await ExecutableLocator.locate(command) else {
            throw MCPTransportError.launchFailed(
                String(
                    format: L10n.string(MCPKey.errorCommandNotFound, language: .english),
                    command))
        }
        // 在查找可执行文件期间可能有另一个调用方已将其启动。
        if isRunning { return }
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.environment = ExecutableLocator.environment(running: executable, adding: environment)
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
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor in self?.didExit(status: status) }
        }
        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            throw MCPTransportError.launchFailed(error.localizedDescription)
        }
        self.process = process
        // 服务端在写入途中退出时，写入必须报错，而不能以 SIGPIPE 结束 GearMac。
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        input = stdin.fileHandleForWriting
    }

    /// 写入一条请求并等待对应响应，超时按方法区分：tools/call 为 60 秒，其余为 15 秒。
    func request(_ method: String, _ params: [String: Any]?) async throws -> JSONValue {
        guard isRunning else { throw MCPTransportError.notRunning }
        let id = nextID
        nextID += 1
        let timeout: Duration = method == "tools/call" ? .seconds(60) : .seconds(15)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let watchdog = Task { [weak self] in
                    try? await Task.sleep(for: timeout)
                    guard !Task.isCancelled else { return }
                    self?.finish(id, with: .failure(MCPTransportError.timedOut))
                }
                pending[id] = PendingRequest(continuation: continuation, timeout: watchdog)
                do {
                    try send(
                        MCPProtocol.request(
                            id: id, method: method, params: params, newlineTerminated: true))
                } catch {
                    finish(id, with: .failure(error))
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in self?.finish(id, with: .failure(CancellationError())) }
        }
    }

    /// 向子进程写入一条通知，不等待回复。
    func notify(_ method: String, _ params: [String: Any]?) throws {
        try send(MCPProtocol.notification(method: method, params: params, newlineTerminated: true))
    }

    /// 关闭连接，以 notRunning 错误结束未完成的请求。
    func close() {
        stop(error: MCPTransportError.notRunning)
    }

    /// 关闭 stdin 是干净退出的方式——服务端读到 EOF 即退出——SIGTERM 则作为兜底。
    private func stop(error: Error) {
        guard let process else { return }
        process.terminationHandler = nil
        cleanup(error: error)
        Task.detached {
            try? await Task.sleep(for: .seconds(1))
            if process.isRunning { process.terminate() }
        }
    }

    /// 向子进程 stdin 写入原始数据。
    private func send(_ data: Data) throws {
        guard let input else { throw MCPTransportError.notRunning }
        try input.write(contentsOf: data)
    }

    /// 累积 stdout 数据并按换行切分出完整消息；单行超限时断开并报错。
    private func consumeOutput(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            handle(MCPProtocol.parse(Data(line)))
        }
        guard outputBuffer.count > Self.outputLimit else { return }
        let message = "The server sent an unterminated oversized response and was disconnected."
        onExit?(message)
        stop(error: MCPTransportError.requestFailed(message))
    }

    /// 分发一条已解析出的消息：响应呈递结果，通知转发，反向请求直接拒绝。
    private func handle(_ message: MCPProtocol.Message) {
        switch message {
        case .response(let id, let result):
            finish(id, with: .success(result))
        case .failure(let id, let message):
            finish(id, with: .failure(MCPTransportError.requestFailed(message)))
        case .notification(let method, let params):
            onNotification?(method, params)
        case .request(let id, _):
            try? send(MCPProtocol.decline(id: id, newlineTerminated: true))
        case .invalid:
            break
        }
    }

    /// 进程退出可能早于最后一次读取，而服务端退出前打印的内容正是原因所在。
    private func drainStderr() {
        guard let handle = (process?.standardError as? Pipe)?.fileHandleForReading else { return }
        handle.readabilityHandler = nil
        consumeStderr(handle.readDataToEndOfFile())
    }

    /// 累积 stderr 输出，只保留最近 stderrLimit 字节作为退出原因。
    private func consumeStderr(_ data: Data) {
        guard !data.isEmpty else { return }
        stderrBuffer.append(data)
        guard stderrBuffer.count > Self.stderrLimit else { return }
        stderrBuffer.removeFirst(stderrBuffer.count - Self.stderrLimit)
    }

    /// 完成指定 id 的待处理请求，取消其超时看门狗。
    private func finish(_ id: Int, with result: Result<JSONValue, Error>) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeout.cancel()
        request.continuation.resume(with: result)
    }

    /// 子进程退出时的处理：读取剩余 stderr 作为失败原因并同步给未完成的调用。
    private func didExit(status: Int32) {
        drainStderr()
        let detail = String(decoding: stderrBuffer, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let message = detail.isEmpty ? "The server exited with status \(status)." : detail
        // 必须先让未完成的调用失败，再通知持有方；否则关闭流程会覆盖掉真实原因。
        cleanup(error: MCPTransportError.requestFailed(message))
        onExit?(message)
    }

    /// 清理进程句柄与缓冲区，并以给定错误结束全部未完成的请求。
    private func cleanup(error: Error) {
        process?.terminationHandler = nil
        (process?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        (process?.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        try? input?.close()
        process = nil
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
