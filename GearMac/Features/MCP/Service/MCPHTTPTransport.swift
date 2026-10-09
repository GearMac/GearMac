// 文件职责：实现 MCP 的 Streamable HTTP 传输，每条消息发一次 POST，并解析服务端返回的 JSON 或 SSE 帧流。
// 分层：Service；@MainActor 串行维护连接状态与会话 ID，不 import AppKit/SwiftUI。
import Foundation

/// Streamable HTTP 传输：每条消息发一次 POST，服务端以 JSON 或 SSE 帧流作答。
@MainActor
final class MCPHTTPTransport: MCPTransport {
    var onNotification: ((String, JSONValue) -> Void)?

    private let endpoint: URL
    private let headerName: String
    private let headerValue: String
    private let authorization: ((String?) async throws -> String)?
    private var sessionID: String?
    private var protocolVersion = MCPProtocol.version
    private var nextID = 1
    private var isConnected = false

    init(
        url: String, headerName: String, headerValue: String,
        authorization: ((String?) async throws -> String)? = nil
    ) throws {
        do {
            endpoint = try AIEndpointPolicy.validate(url)
        } catch {
            throw MCPTransportError.invalidEndpoint(error.localizedDescription)
        }
        self.headerName = headerName.trimmingCharacters(in: .whitespaces)
        self.headerValue = headerValue
        self.authorization = authorization
    }

    /// 标记为已连接；真正的 HTTP 请求在每次发送时按需建立。
    func connect() async throws {
        isConnected = true
    }

    /// 发送一次请求并等待对应响应，超时按方法区分：tools/call 为 60 秒，其余为 15 秒。
    func request(_ method: String, _ params: [String: Any]?) async throws -> JSONValue {
        guard isConnected else { throw MCPTransportError.notRunning }
        let id = nextID
        nextID += 1
        let body = try MCPProtocol.request(id: id, method: method, params: params)
        let timeout: TimeInterval = method == "tools/call" ? 60 : 15
        let (data, response) = try await post(body, timeout: timeout)
        try check(response)
        // 会话 ID 出现在开启会话的那次响应上，因此每次响应都要尝试读取。
        if let header = response.value(forHTTPHeaderField: "Mcp-Session-Id") { sessionID = header }
        for message in Self.messages(in: data, contentType: response.mimeType) {
            switch message {
            case .response(id, let result): return result
            case .failure(id, let message): throw MCPTransportError.requestFailed(message)
            case .notification(let method, let params): onNotification?(method, params)
            default: continue
            }
        }
        throw MCPTransportError.malformedResponse
    }

    /// 发送一条不需要回复的通知；请求在后台任务中发出，调用方不必等待。
    func notify(_ method: String, _ params: [String: Any]?) throws {
        guard isConnected else { throw MCPTransportError.notRunning }
        let body = try MCPProtocol.notification(method: method, params: params)
        // 发后即忘：通知没有需要等待的回复，202 响应就是全部结果。
        Task { [weak self] in _ = try? await self?.post(body, timeout: 15) }
    }

    /// 关闭连接并清除会话 ID。
    func close() {
        isConnected = false
        sessionID = nil
    }

    /// 构造并发送一次 JSON-RPC POST 请求；遇到 401 时通过授权回调刷新 token 重试一次。
    private func post(
        _ body: Data, timeout: TimeInterval
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        let token = try await authorization?(nil)
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if !headerName.isEmpty, !headerValue.isEmpty {
            request.setValue(headerValue, forHTTPHeaderField: headerName)
        }
        let session = MCPOAuthHTTP.session(followsSameOrigin: true)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw MCPTransportError.malformedResponse
            }
            if response.statusCode == 401, let authorization, let token {
                let refreshed = try await authorization(token)
                request.setValue("Bearer \(refreshed)", forHTTPHeaderField: "Authorization")
                let (retried, reply) = try await session.data(for: request)
                guard let reply = reply as? HTTPURLResponse else { throw MCPTransportError.malformedResponse }
                if reply.statusCode == 401 { throw MCPOAuth.Failure.signInRequired }
                return (retried, reply)
            }
            return (data, response)
        } catch let error as URLError {
            throw MCPTransportError.requestFailed(Self.networkMessage(error.code))
        }
    }

    /// 校验 HTTP 状态码，把非 2xx 响应映射为对应的 MCPTransportError。
    private func check(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200...299: return
        case 401, 403:
            throw MCPTransportError.requestFailed("The server rejected GearMac's credentials.")
        // 会话被丢弃由服务端决定；下一次请求会重新开启一个新会话。
        case 404 where sessionID != nil:
            sessionID = nil
            throw MCPTransportError.requestFailed("The server ended the session.")
        default:
            throw MCPTransportError.requestFailed(
                "The server answered HTTP \(response.statusCode).")
        }
    }

    /// JSON 响应体是一条消息；SSE 响应体则是其中携带的每一个 `data:` 帧。
    private static func messages(in data: Data, contentType: String?) -> [MCPProtocol.Message] {
        guard contentType == "text/event-stream" else { return [MCPProtocol.parse(data)] }
        var parser = SSEParser()
        return (parser.feed(data) + parser.finish()).map { MCPProtocol.parse(Data($0.utf8)) }
    }

    /// 把 URLError 错误码转换为面向用户的英文网络错误文案。
    private static func networkMessage(_ code: URLError.Code) -> String {
        switch code {
        case .notConnectedToInternet: return "No internet connection."
        case .timedOut: return "The server took too long to respond."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "The server could not be reached."
        default: return "The request to the server failed."
        }
    }
}
