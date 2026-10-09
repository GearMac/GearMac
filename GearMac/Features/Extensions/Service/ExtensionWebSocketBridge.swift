// 文件职责：将 JS 侧的 `websocket.*` 宿主调用桥接到 `URLSessionWebSocketTask`，并回收 socket 事件。
// 分层：Service；每个 socket 对应一个 task，由 JS 侧保持的单个 `receive` 读取；连接表用 Mutex 保护。
import Foundation
import Synchronization

/// 每个 socket 对应一个 `URLSessionWebSocketTask`，由 JS 侧保持的单次 `receive` 读取。
final class ExtensionWebSocketBridge: NSObject, Sendable, URLSessionWebSocketDelegate {
    private struct Connection {
        let task: URLSessionWebSocketTask
        var opening: CheckedContinuation<String, Error>?
    }

    private let connections = Mutex<[Int: Connection]>([:])
    private let sessionBox = Mutex<URLSession?>(nil)

    /// WebSocket 桥接可能出现的错误。
    enum SocketError: LocalizedError {
        case badURL(String)
        case closed
        case unknown(String)

        var errorDescription: String? {
            switch self {
            case .badURL(let url): return "Invalid WebSocket URL: \(url)"
            case .closed: return "The WebSocket is closed."
            case .unknown(let method): return "Unknown host call 'websocket.\(method)'."
            }
        }
    }

    /// 宿主调用入口：按 method 分发到 open/receive/send/ping/close。
    func perform(method: String, arguments: [RenderValue]) async throws -> Any? {
        let fields = arguments.first?.objectValue ?? [:]
        switch method {
        case "open": return try await open(fields)
        case "receive": return try await receive(id: whole(arguments.first))
        case "send": return try await send(fields)
        case "ping": return try await ping(whole(fields["id"]))
        case "close":
            close(
                id: whole(fields["id"]), code: whole(fields["code"], or: 1000),
                reason: fields["reason"]?.stringValue ?? "")
            return nil
        default: throw SocketError.unknown(method)
        }
    }

    /// 将 RenderValue 转为整数，无法精确转换时使用 fallback。
    private func whole(_ value: RenderValue?, or fallback: Int = 0) -> Int {
        value?.doubleValue.flatMap(Int.init(exactly:)) ?? fallback
    }

    /// 命令之间上下文会被丢弃，这些连接将不会被再次读取。
    func closeAll() {
        let open = connections.withLock { state -> [Connection] in
            let all = Array(state.values)
            state.removeAll()
            return all
        }
        for connection in open {
            connection.opening?.resume(throwing: SocketError.closed)
            connection.task.cancel(with: .goingAway, reason: nil)
        }
    }

    // MARK: - Calls

    /// 建立连接：校验 URL、写入自定义 headers/protocols，等待握手完成并返回协商结果。
    private func open(_ fields: [String: RenderValue]) async throws -> [String: Any] {
        let text = fields["url"]?.stringValue ?? ""
        guard let url = URL(string: text), url.scheme == "ws" || url.scheme == "wss" else {
            throw SocketError.badURL(text)
        }
        var request = URLRequest(url: url)
        for (name, value) in fields["headers"]?.objectValue ?? [:] {
            guard let header = value.stringValue else { continue }
            request.setValue(header, forHTTPHeaderField: name)
        }
        let protocols = (fields["protocols"]?.arrayValue ?? []).compactMap(\.stringValue)
        if !protocols.isEmpty {
            request.setValue(protocols.joined(separator: ", "), forHTTPHeaderField: "Sec-WebSocket-Protocol")
        }
        let task = session().webSocketTask(with: request)
        let id = task.taskIdentifier
        let negotiated = try await withCheckedThrowingContinuation { continuation in
            connections.withLock { $0[id] = Connection(task: task, opening: continuation) }
            task.resume()
        }
        return ["id": id, "protocol": negotiated]
    }

    /// 接收一条消息；对端关闭或出错时，以 close 事件的形式返回关闭码与原因。
    private func receive(id: Int) async throws -> [String: Any] {
        guard let task = connections.withLock({ $0[id]?.task }) else { throw SocketError.closed }
        do {
            switch try await task.receive() {
            case .string(let text): return ["type": "text", "text": text]
            case .data(let data): return ["type": "binary", "base64": data.base64EncodedString()]
            @unknown default: return ["type": "text", "text": ""]
            }
        } catch {
            connections.withLock { $0[id] = nil }
            let code = task.closeCode
            let clean = code != .invalid
            return [
                "type": "close",
                "code": clean ? code.rawValue : 1006,
                "reason": String(data: task.closeReason ?? Data(), encoding: .utf8) ?? "",
                "abnormal": !clean
            ]
        }
    }

    /// 发送消息：有 base64 字段时发二进制，否则发文本。
    private func send(_ fields: [String: RenderValue]) async throws -> Any? {
        let id = whole(fields["id"])
        guard let task = connections.withLock({ $0[id]?.task }) else { throw SocketError.closed }
        if let base64 = fields["base64"]?.stringValue, let data = Data(base64Encoded: base64) {
            try await task.send(.data(data))
        } else {
            try await task.send(.string(fields["text"]?.stringValue ?? ""))
        }
        return nil
    }

    /// 发送 ping 并等待对端响应。
    private func ping(_ id: Int) async throws -> Any? {
        guard let task = connections.withLock({ $0[id]?.task }) else { throw SocketError.closed }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        return nil
    }

    /// 以给定关闭码与原因主动关闭连接，并从连接表中移除。
    private func close(id: Int, code: Int, reason: String) {
        guard let connection = connections.withLock({ $0.removeValue(forKey: id) }) else { return }
        let closeCode = URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .normalClosure
        connection.task.cancel(with: closeCode, reason: reason.data(using: .utf8))
    }

    // MARK: - Session

    /// 与其余网络出口一致，使用私有且 ephemeral 的会话：无 cookie 存储、无共享缓存。
    private func session() -> URLSession {
        sessionBox.withLock { box in
            if let existing = box { return existing }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            let created = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            box = created
            return created
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    /// 握手成功时唤醒等待中的 open 调用，并回传协商出的子协议。
    func urlSession(
        _ session: URLSession, webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocolName: String?
    ) {
        finishOpening(id: webSocketTask.taskIdentifier, result: .success(protocolName ?? ""))
    }

    /// 握手失败的唯一暴露点：失败时 `receive` 永远不会被调到。
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finishOpening(
            id: task.taskIdentifier,
            result: .failure(error ?? SocketError.closed))
    }

    /// 结束 open 阶段的等待：成功保留连接，失败则从连接表中移除。
    private func finishOpening(id: Int, result: Result<String, Error>) {
        let continuation = connections.withLock { state -> CheckedContinuation<String, Error>? in
            guard let opening = state[id]?.opening else { return nil }
            state[id]?.opening = nil
            if case .failure = result { state[id] = nil }
            return opening
        }
        continuation?.resume(with: result)
    }
}
