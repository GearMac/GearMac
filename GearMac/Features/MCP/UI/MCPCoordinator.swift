// 文件职责：作为 MCP 的统一入口，编排服务器启停、工具暴露、调用许可与登录/登出操作。
// 分层：Coordinator（Observable）；@MainActor 联结 AppCore、设置存储与服务器管理器。
import Foundation
import Observation

/// MCP 的操作入口：哪些服务器在运行、模型可以调用什么，以及先询问谁。
@MainActor
@Observable
final class MCPCoordinator {
    private let settings: AppSettings
    private let store: MCPSettingsStore
    private let manager: MCPServerManager
    private unowned let core: AppCore

    /// 每个会话被授予的服务器集合；用字典存储，因为确认弹窗的存活时间可能超过一次会话切换。
    @ObservationIgnored private var chatGrants: [UUID: Set<UUID>] = [:]

    init(
        settings: AppSettings, store: MCPSettingsStore, manager: MCPServerManager, core: AppCore
    ) {
        self.settings = settings
        self.store = store
        self.manager = manager
        self.core = core
    }

    var isActive: Bool { settings.aiEnabled && settings.mcpEnabled }

    /// 关闭就是彻底关闭：不建立连接、不保留常驻进程、也不向模型提供任何工具。
    func applyEnabled() {
        defer { dropWithdrawnServers() }
        guard isActive else {
            core.mcpOAuth.stop()
            manager.stop()
            return
        }
        manager.reconcile(ownServers)
    }

    /// Codex 辅助进程只保留启动时拿到的服务器，因此被移除的服务器也要从它那里撤下。
    private func dropWithdrawnServers(besides withdrawn: UUID? = nil) {
        let offered = store.enabledServers.filter { $0.trust != .never && $0.id != withdrawn }
        core.chatGPTSubscription.dropWithdrawnServers(
            keeping: isActive ? Set(offered.map(\.slug)) : [])
    }

    /// 进入聊天前预先连接，使首次发送不必逐个等待握手。
    func warmUp() {
        guard isActive else { return }
        manager.reconcile(ownServers)
    }

    /// GearMac 自己运行的服务器；Codex 与 Claude 会各自启动本地服务器的副本。
    private var ownServers: [MCPServer] {
        let cliRoute = core.aiChatCoordinator.everyChatRunsItsOwnTools
        return store.enabledServers.filter { $0.runsInGearMac(whileCLIRouteSelected: cliRoute) }
    }

    /// 当前启用服务器的 slug 集合；MCP 关闭时为空。
    var slugs: Set<String> {
        guard isActive else { return [] }
        return Set(store.enabledServers.map(\.slug))
    }

    /// 聊天工具菜单列出的内容；MCP 关闭时为空。
    var servers: [MCPServer] {
        guard isActive else { return [] }
        return store.enabledServers
    }

    /// 按 slug 查找已启用服务器；MCP 关闭时返回 nil。
    func server(slug: String) -> MCPServer? {
        guard isActive else { return nil }
        return store.enabledServers.first { $0.slug == slug }
    }

    /// 本轮可访问的工具范围：全部已启用服务器，或在 `@slug` 指定时仅该服务器。
    func tools(scopedTo slug: String?) -> [AITool] {
        guard isActive else { return [] }
        return manager.tools
            .filter { tool in
                guard slug == nil || tool.serverSlug == slug else { return false }
                return store.server(id: tool.serverID)?.trust != .never
            }
            .map(\.aiTool)
    }

    /// CLI 路径下的同类列表；它会启动自己的副本，因此 GearMac 侧的连接无需就绪。
    func toolServers(scopedTo slug: String?) async -> [AIToolServer] {
        guard isActive else { return [] }
        let secrets = MCPSecretStore()
        var result: [AIToolServer] = []
        for server in store.enabledServers
        where server.trust != .never && (slug == nil || server.slug == slug) {
            let stored = secrets.secrets(for: server.id)
            var bearer: String?
            if server.oauth == true { bearer = try? await core.mcpOAuth.lentToken(for: server) }
            guard
                let toolServer = server.toolServer(
                    headerValue: stored.headerValue, environment: stored.environment,
                    bearerToken: bearer)
            else { continue }
            result.append(toolServer)
        }
        return result
    }

    /// 为厂商 CLI 发起的调用获取同意，走同一套策略与同一个确认弹窗。
    func permit(_ call: AIToolServerCall, in chat: UUID) async -> Bool {
        guard isActive, let server = server(slug: call.handle) else { return false }
        return await isPermitted(server, tool: call.tool, in: chat)
    }

    /// 执行模型发起的工具调用：校验路由与许可后交给对应连接，并刷新空闲计时。
    func invoke(_ call: AIToolCall, in chat: UUID) async -> AIToolResult {
        guard let route = MCPToolName.parse(call.name),
            let server = server(slug: route.slug),
            let connection = manager.connection(slug: route.slug)
        else {
            return .failure(call.id, settings.text(MCPKey.toolNoLongerConnected))
        }
        guard await isPermitted(server, tool: route.tool, in: chat) else {
            return .failure(call.id, settings.text(MCPKey.toolDeclined))
        }
        manager.markUsed()
        do {
            let (content, isError) = try await connection.call(
                route.tool, arguments: JSONValue(data: Data(call.arguments.utf8)) ?? .object([:]))
            return AIToolResult(callID: call.id, content: content, isError: isError)
        } catch {
            return .failure(call.id, error.localizedDescription)
        }
    }

    /// 断开现有连接并执行 OAuth 登录，成功后由后续请求获取新 token。
    func signIn(_ server: MCPServer, credentials: MCPOAuth.Credentials) async throws {
        guard isActive else { throw MCPOAuth.Failure.signInRequired }
        manager.disconnect(server.id)
        try await core.mcpOAuth.signIn(server: server, credentials: credentials)
    }

    /// 断开连接并清除该服务器的 OAuth 登录状态。
    func signOut(_ id: UUID) throws {
        manager.disconnect(id)
        try core.mcpOAuth.signOut(id)
        dropWithdrawnServers(besides: id)
    }

    /// 取消进行中的登录。
    func cancelSignIn(_ id: UUID) { core.mcpOAuth.cancelSignIn(id) }

    /// 查询指定服务器的连接状态。
    func status(of id: UUID) -> MCPServerStatus { manager.status(of: id) }

    /// 保存服务器与凭证，并重建连接使新配置立即生效。
    func save(_ server: MCPServer, secrets: MCPSecretStore.Secrets) throws {
        try MCPSecretStore().save(secrets, for: server.id)
        core.mcpOAuth.cancelSignIn(server.id)
        manager.disconnect(server.id)
        store.save(server)
        applyEnabled()
    }

    /// 删除服务器及其凭证，并同步运行中的连接。
    func remove(_ id: UUID) throws {
        core.mcpOAuth.cancelSignIn(id)
        try MCPSecretStore().remove(for: id)
        store.remove(id: id)
        applyEnabled()
    }

    /// 丢弃新建设置面板中未保存的服务器：取消登录并清理已写入的凭证。
    func discardUnsaved(_ id: UUID) {
        cancelSignIn(id)
        if store.server(id: id) == nil { try? MCPSecretStore().remove(for: id) }
    }

    /// 查询指定服务器的 OAuth 登录状态。
    func authenticationStatus(
        _ server: MCPServer, stored: MCPOAuth.Credentials?
    ) -> MCPOAuthManager.Status {
        core.mcpOAuth.status(for: server, stored: stored)
    }

    /// 临时建立一次连接来验证服务器是否可用，结束后立即关闭。
    func test(_ server: MCPServer, secrets: MCPSecretStore.Secrets) async -> MCPServerStatus {
        if server.oauth == true {
            let stored = MCPSecretStore().secrets(for: server.id).oauth
            guard stored?.clientID == secrets.oauth?.clientID,
                stored?.clientSecret == secrets.oauth?.clientSecret
            else { return .signInRequired }
        }
        let connection = MCPServerConnection(server: server, secrets: secrets, oauth: core.mcpOAuth)
        defer { connection.stop() }
        await connection.start()
        return connection.status
    }

    /// 按信任策略决定是否允许调用，必要时弹出确认弹窗并根据选择更新授权。
    private func isPermitted(_ server: MCPServer, tool: String, in chat: UUID) async -> Bool {
        switch MCPTrustPolicy.decide(
            trust: server.trust, isGrantedForChat: chatGrants[chat]?.contains(server.id) == true)
        {
        case .allow: return true
        case .refuse: return false
        case .ask: break
        }
        switch await ask(server, tool: tool) {
        case .always:
            store.setTrust(.always, for: server.id)
            return true
        case .thisChat:
            chatGrants[chat, default: []].insert(server.id)
            return true
        case .refuse:
            return false
        }
    }

    /// Esc 只拒绝本次调用：弹窗可以授予某个服务器，但只有设置才能收回。
    private func ask(_ server: MCPServer, tool: String) async -> MCPTrustChoice {
        let choices: [MCPTrustChoice] = [.always, .thisChat, .refuse]
        let index = await core.choose(
            title: String(format: settings.text(MCPKey.toolRunTitle), server.title),
            message: String(format: settings.text(MCPKey.toolRunMessage), tool),
            symbol: "wrench.and.screwdriver",
            options: [
                DialogAction(title: settings.text(MCPKey.toolAlwaysAllow)),
                DialogAction(title: settings.text(MCPKey.toolAllowThisChat)),
                DialogAction(title: settings.text(MCPKey.toolDontAllow), role: .cancel),
            ],
            defaultIndex: 1)
        return choices.indices.contains(index) ? choices[index] : .refuse
    }
}
