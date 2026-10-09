// 文件职责：管理单个 MCP 服务器的连接生命周期，涵盖握手、工具列表获取与工具调用。
// 分层：Service（Observable）；@MainActor 串行切换连接状态，底层传输可替换（HTTP 或 stdio）。
import Foundation
import Observation

/// 一个已配置服务器的完整状态：从握手到工具列表再到调用，底层传输类型可变。
@MainActor
@Observable
final class MCPServerConnection {
    private(set) var status: MCPServerStatus = .stopped
    private(set) var tools: [MCPTool] = []

    @ObservationIgnored private let oauth: MCPOAuthManager?
    @ObservationIgnored let server: MCPServer
    @ObservationIgnored private let secrets: MCPSecretStore.Secrets
    @ObservationIgnored private var transport: (any MCPTransport)?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var listTask: Task<Void, Never>?

    init(server: MCPServer, secrets: MCPSecretStore.Secrets, oauth: MCPOAuthManager? = nil) {
        self.oauth = oauth
        self.server = server
        self.secrets = secrets
    }

    /// 失败过的服务器可以重新启动：下次进入聊天就是重试偶发故障的时机。
    var isIdle: Bool {
        switch status {
        case .stopped, .failed, .signInRequired: return true
        case .connecting, .ready: return false
        }
    }

    /// 启动连接：建立传输、完成 initialize 握手并拉取工具列表；需要登录时转入待登录状态。
    func start() async {
        guard isIdle else { return }
        status = .connecting
        let generation = generation
        do {
            let transport = try makeTransport()
            self.transport = transport
            try await transport.connect()
            _ = try await transport.request("initialize", Self.handshake)
            guard self.generation == generation, !Task.isCancelled else { return }
            try transport.notify("notifications/initialized", nil)
            let result = try await transport.request("tools/list")
            guard self.generation == generation, !Task.isCancelled else { return }
            tools = MCPTool.list(
                result, serverID: server.id,
                serverSlug: server.slug, serverTitle: server.title)
            status = .ready(tools: tools.count)
        } catch MCPOAuth.Failure.signInRequired {
            guard self.generation == generation else { return }
            requireSignIn()
        } catch {
            guard self.generation == generation else { return }
            fail(error.localizedDescription)
        }
    }

    /// 调用指定工具并返回展平后的文本输出与是否出错的标记。
    func call(_ name: String, arguments: JSONValue) async throws -> (String, Bool) {
        guard let transport, status.isReady else { throw MCPTransportError.notRunning }
        do {
            let result = try await transport.request(
                "tools/call", ["name": name, "arguments": arguments.jsonObject])
            return MCPToolOutput.flatten(result)
        } catch MCPOAuth.Failure.signInRequired {
            requireSignIn()
            throw MCPOAuth.Failure.signInRequired
        }
    }

    /// 停止连接：递增 generation 使未完成的异步任务失效，关闭传输并清空工具列表。
    func stop() {
        generation = UUID()
        listTask?.cancel()
        listTask = nil
        transport?.close()
        transport = nil
        tools = []
        status = .stopped
    }

    /// 转入待登录状态，并同步通知 OAuth 管理器。
    private func requireSignIn() {
        stop()
        status = .signInRequired
        oauth?.requireSignIn(server)
    }

    /// 进入失败状态，关闭传输并清空工具列表。
    private func fail(_ message: String) {
        transport?.close()
        transport = nil
        tools = []
        status = .failed(message)
    }

    /// 根据服务器配置创建对应传输；HTTP 且启用 OAuth 时注入 token 获取回调。
    private func makeTransport() throws -> any MCPTransport {
        switch server.transport {
        case .http(let url, let headerName):
            var authorization: ((String?) async throws -> String)?
            if server.oauth == true {
                let server = server
                authorization = { [weak oauth] rejected in
                    guard let oauth else { throw MCPOAuth.Failure.signInRequired }
                    return try await oauth.accessToken(for: server, rejectedToken: rejected)
                }
            }
            let transport = try MCPHTTPTransport(
                url: url, headerName: headerName, headerValue: secrets.headerValue,
                authorization: authorization)
            transport.onNotification = { [weak self] method, _ in self?.received(method) }
            return transport
        case .stdio(let command, let arguments, _):
            let transport = MCPStdioTransport(
                command: command, arguments: arguments, environment: secrets.environment)
            transport.onNotification = { [weak self] method, _ in self?.received(method) }
            transport.onExit = { [weak self] message in self?.fail(message) }
            return transport
        }
    }

    /// 服务端可能在运行中增减工具，且只会通过通知告知。
    private func received(_ method: String) {
        guard method == "notifications/tools/list_changed", listTask == nil else { return }
        listTask = Task { [weak self] in
            defer { self?.listTask = nil }
            guard let self, let transport = self.transport else { return }
            let generation = self.generation
            do {
                let listed = try await transport.request("tools/list")
                guard self.generation == generation, !Task.isCancelled else { return }
                self.tools = MCPTool.list(
                    listed, serverID: self.server.id, serverSlug: self.server.slug,
                    serverTitle: self.server.title)
                self.status = .ready(tools: self.tools.count)
            } catch MCPOAuth.Failure.signInRequired {
                if self.generation == generation { self.requireSignIn() }
            } catch { return }
        }
    }

    /// initialize 握手请求体：声明协议版本、能力集与客户端信息。
    private static let handshake: [String: Any] = [
        "protocolVersion": MCPProtocol.version,
        "capabilities": [:],
        "clientInfo": [
            "name": "gearmac",
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        ]
    ]
}
