// 文件职责：在回送地址 127.0.0.1:4962 上监听 HTTP 回调，接收 OAuth 授权码并解析出结果。
// 分层：Service；@MainActor 管理本地监听器与 continuation 状态，不 import AppKit/SwiftUI。
// 双路径：macOS 26 用 NetworkListener（新 API）；macOS 25 及以下用 NWListener——老 API 在
// macOS 26 上已被系统拒绝（bind EINVAL），而新 API 在旧系统不存在，因此无法共用一条路径。
// start() 顶部的分派是本功能唯一的系统判断点，两条路径各自完整可用。
import Foundation
import Network

/// 监听回送回调的本机 HTTP 监听器，用 continuation 把授权码或错误可靠地回传给调用方。
@MainActor
final class MCPOAuthListener {
    /// OAuth 授权服务器回调时使用的固定重定向地址。
    nonisolated static let redirectURI = "http://127.0.0.1:4962/callback"
    private var task: Task<Void, Never>?
    private var ready: CheckedContinuation<Void, Error>?
    private var reply: CheckedContinuation<String, Error>?
    private var result: Result<String, Error>?
    private var accepted = false

    isolated deinit { task?.cancel() }

    /// 启动本地监听器并在 timeout 内等待回调；超时或监听失败则抛出对应错误。
    func start(
        state: String, issuer: String, requiresIssuer: Bool, timeout: Duration = .seconds(300)
    ) async throws {
        guard result == nil else { throw CancellationError() }
        if #available(macOS 26.0, *) {
            try await awaitCallback26(
                state: state, issuer: issuer, requiresIssuer: requiresIssuer, timeout: timeout)
        } else {
            try await awaitCallbackLegacy(
                state: state, issuer: issuer, requiresIssuer: requiresIssuer, timeout: timeout)
        }
    }

    /// 等待并返回到达的授权码，支持取消传播。
    func code() async throws -> String {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            if let result { return try result.get() }
            return try await withCheckedThrowingContinuation { reply = $0 }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    /// 主动取消监听，以 CancellationError 结束等待。
    func cancel() { finish(.failure(CancellationError())) }

    /// 记录首次结果并唤醒所有等待中的 continuation（重复调用无效果）。
    private func finish(_ result: Result<String, Error>) {
        guard self.result == nil else { return }
        self.result = result
        if case .failure(let error) = result {
            ready?.resume(throwing: error)
        } else {
            ready?.resume(throwing: CancellationError())
        }
        ready = nil
        reply?.resume(with: result)
        reply = nil
        task?.cancel()
        task = nil
    }

    /// 两条路径共用的编排：注册 ready、运行监听与超时的竞速组、处理取消。
    private func orchestrate(
        timeout: Duration, runListener: @escaping @Sendable () async throws -> Void
    ) async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                ready = continuation
                task = Task { [weak self] in
                    do {
                        try await withThrowingTaskGroup(of: Void.self) { group in
                            group.addTask { try await runListener() }
                            group.addTask {
                                try await Task.sleep(for: timeout)
                                throw MCPOAuth.Failure.timedOut
                            }
                            defer { group.cancelAll() }
                            _ = try await group.next()
                        }
                    } catch {
                        self?.finish(.failure(error))
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    /// 一次回调请求的判定结果：未成形（静默断开）、成形但无效（回 400）、或已接受。
    private enum CallbackOutcome {
        case incomplete
        case invalid
        case accepted(Result<String, Error>)
    }

    /// 解析请求首行并校验回调参数，生成判定与对应的 HTTP 响应；两条路径共用。
    private static func handleCallback(
        _ bytes: Data, state: String, issuer: String, requiresIssuer: Bool
    ) -> (CallbackOutcome, String) {
        guard let request = String(bytes: bytes, encoding: .utf8), request.contains("\r\n\r\n")
        else { return (.incomplete, "") }
        let line = request.components(separatedBy: "\r\n").first ?? ""
        let parts = line.split(separator: " ")
        var outcome: Result<String, Error>?
        if parts.count == 3, parts[0] == "GET" {
            do {
                let code = try MCPOAuth.callback(
                    String(parts[1]), state: state, issuer: issuer,
                    requiresIssuer: requiresIssuer)
                outcome = .success(code)
            } catch MCPOAuth.Failure.denied {
                outcome = .failure(MCPOAuth.Failure.denied)
            } catch { outcome = nil }
        }
        let page =
            outcome == nil ? "Invalid sign-in response." : "Return to GearMac. You can close this tab."
        let response =
            "HTTP/1.1 \(outcome == nil ? "400 Bad Request" : "200 OK")"
            + "\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Cache-Control: no-store\r\nContent-Security-Policy: default-src 'none'\r\n"
            + "Connection: close\r\nContent-Length: \(page.utf8.count)\r\n\r\n\(page)"
        return (outcome.map(CallbackOutcome.accepted) ?? .invalid, response)
    }

    // MARK: - macOS 26 路径（NetworkListener）

    /// 启动监听并等待回调：macOS 26 的 NetworkListener 实现，与历史版本行为一致。
    @available(macOS 26.0, *)
    private func awaitCallback26(
        state: String, issuer: String, requiresIssuer: Bool, timeout: Duration
    ) async throws {
        let listener = try NetworkListener(
            using: .parameters { TCP() }
                .localEndpoint(.hostPort(host: .ipv4(.loopback), port: 4962)))
        listener.newConnectionLimit = 16
        try await orchestrate(timeout: timeout) { [weak self] in
            try await self?.run26(
                listener, state: state, issuer: issuer, requiresIssuer: requiresIssuer)
        }
    }

    /// 监听器就绪后接受连接，就绪失败时直接返回错误。
    @available(macOS 26.0, *)
    private func run26(
        _ listener: NetworkListener<TCP>, state: String, issuer: String, requiresIssuer: Bool
    ) async throws {
        try await listener.onStateUpdate { [weak self] _, status in
            switch status {
            case .ready:
                self?.ready?.resume()
                self?.ready = nil
            case .waiting, .failed:
                self?.finish(.failure(MCPOAuth.Failure.listenerUnavailable))
            default: break
            }
        }.run { [weak self] connection in
            await self?.receive26(
                connection, state: state, issuer: issuer, requiresIssuer: requiresIssuer)
        }
    }

    /// 读取一次回调请求，解析出授权码并回写 HTML 响应页面。
    @available(macOS 26.0, *)
    private func read26(
        _ connection: NetworkConnection<TCP>, state: String, issuer: String, requiresIssuer: Bool
    ) async throws {
        var bytes = Data()
        while bytes.count < 8192 {
            let message = try await connection.receive(atLeast: 1, atMost: 8192 - bytes.count)
            bytes.append(message.content)
            if bytes.range(of: Data("\r\n\r\n".utf8)) != nil { break }
            if message.metadata.endOfStream { return }
        }
        guard !accepted else { return }
        let (outcome, response) = Self.handleCallback(
            bytes, state: state, issuer: issuer, requiresIssuer: requiresIssuer)
        if case .incomplete = outcome { return }
        if case .accepted = outcome { accepted = true }
        do {
            try await connection.send(Data(response.utf8), endOfStream: true)
        } catch {
            if case .accepted(let result) = outcome { finish(result) }
            throw error
        }
        if case .accepted(let result) = outcome { finish(result) }
    }

    /// 处理一条连接，并设置 5 秒超时避免长时间占用。
    @available(macOS 26.0, *)
    private func receive26(
        _ connection: NetworkConnection<TCP>, state: String, issuer: String, requiresIssuer: Bool
    ) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                _ = try? await self?.read26(
                    connection, state: state, issuer: issuer, requiresIssuer: requiresIssuer)
            }
            group.addTask { try? await Task.sleep(for: .seconds(5)) }
            await group.next()
            group.cancelAll()
        }
    }

    // MARK: - macOS 15 路径（NWListener；老 API 在 macOS 26 上已被系统拒绝）

    /// 启动监听并等待回调：macOS 15 的 NWListener 实现。
    private func awaitCallbackLegacy(
        state: String, issuer: String, requiresIssuer: Bool, timeout: Duration
    ) async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: 4962)
        let listener = try NWListener(using: parameters)
        listener.newConnectionLimit = 16
        try await orchestrate(timeout: timeout) { [weak self] in
            try await self?.runLegacy(
                listener, state: state, issuer: issuer, requiresIssuer: requiresIssuer)
        }
    }

    /// 回调式 API 在 `queue: .main` 上派发，handler 内用 assumeIsolated 回到主隔离域；
    /// start 之后挂起等待取消（对应新 API `run` 事件循环的生命周期）。
    private func runLegacy(
        _ listener: NWListener, state: String, issuer: String, requiresIssuer: Bool
    ) async throws {
        listener.stateUpdateHandler = { [weak self] nwState in
            MainActor.assumeIsolated {
                switch nwState {
                case .ready:
                    self?.ready?.resume()
                    self?.ready = nil
                case .waiting, .failed:
                    self?.finish(.failure(MCPOAuth.Failure.listenerUnavailable))
                default: break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated {
                connection.start(queue: .main)
                Task { [weak self] in
                    await self?.receiveLegacy(
                        connection, state: state, issuer: issuer, requiresIssuer: requiresIssuer)
                }
            }
        }
        listener.start(queue: .main)
        while true {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(1))
        }
    }

    /// 读取一次回调请求，解析出授权码并回写 HTML 响应页面。
    private func readLegacy(
        _ connection: NWConnection, state: String, issuer: String, requiresIssuer: Bool
    ) async throws {
        var bytes = Data()
        while bytes.count < 8192 {
            let (chunk, endOfStream) = try await Self.receiveOnce(
                connection, atMost: 8192 - bytes.count)
            bytes.append(chunk)
            if bytes.range(of: Data("\r\n\r\n".utf8)) != nil { break }
            if endOfStream { return }
        }
        guard !accepted else { return }
        let (outcome, response) = Self.handleCallback(
            bytes, state: state, issuer: issuer, requiresIssuer: requiresIssuer)
        if case .incomplete = outcome { return }
        if case .accepted = outcome { accepted = true }
        do {
            try await Self.sendOnce(connection, Data(response.utf8))
        } catch {
            if case .accepted(let result) = outcome { finish(result) }
            throw error
        }
        if case .accepted(let result) = outcome { finish(result) }
    }

    /// 处理一条连接，并设置 5 秒超时避免长时间占用。
    private func receiveLegacy(
        _ connection: NWConnection, state: String, issuer: String, requiresIssuer: Bool
    ) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                _ = try? await self?.readLegacy(
                    connection, state: state, issuer: issuer, requiresIssuer: requiresIssuer)
            }
            group.addTask { try? await Task.sleep(for: .seconds(5)) }
            await group.next()
            group.cancelAll()
        }
    }

    /// 老回调式 receive 的 async 包装：返回（数据，流是否结束）。
    private static func receiveOnce(
        _ connection: NWConnection, atMost: Int
    ) async throws -> (Data, Bool) {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: atMost) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (data ?? Data(), isComplete))
                }
            }
        }
    }

    /// 老回调式 send 的 async 包装：发完并关闭连接（对应新 API 的 endOfStream）。
    private static func sendOnce(_ connection: NWConnection, _ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: data, contentContext: .defaultMessage, isComplete: true,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                    connection.cancel()
                })
        }
    }
}
