// 文件职责：管理每个 MCP 服务器的 OAuth 登录状态，编排发现、注册、登录、刷新与登出流程。
// 分层：Service（Observable）；@MainActor 维护状态并在 UI 读取前完成 Keychain 交互。
import AppKit
import Observation

/// MCP OAuth 登录状态机，向 UI 暴露每个服务器的登录进展并统一处理 token 刷新。
@MainActor
@Observable
final class MCPOAuthManager {
    /// 单个服务器的登录阶段。
    enum Status: Equatable {
        case signedOut
        case signingIn
        case signedIn
        case required
        case failed(String)

        /// 供 UI 直接展示的状态文案。
        func label(_ language: AppLanguage) -> String {
            switch self {
            case .signedOut: return L10n.string(MCPKey.statusNotSignedIn, language: language)
            case .signingIn: return L10n.string(MCPKey.statusWaitingSignIn, language: language)
            case .signedIn: return L10n.string(MCPKey.statusSignedIn, language: language)
            case .required: return L10n.string(MCPKey.statusSignInRequired, language: language)
            case .failed(let message): return message
            }
        }
    }

    private(set) var statuses: [UUID: Status] = [:]
    @ObservationIgnored private let secrets: MCPSecretStore
    @ObservationIgnored private var revisions: [UUID: UUID] = [:]
    @ObservationIgnored private var refreshes: [UUID: Task<String, Error>] = [:]
    @ObservationIgnored private var listener: MCPOAuthListener?
    @ObservationIgnored private var signingIn: UUID?

    init(secrets: MCPSecretStore = MCPSecretStore()) { self.secrets = secrets }

    /// 由调用方传入已读到的凭证：视图 body 询问状态，不得直接读 Keychain。
    func status(for server: MCPServer, stored credentials: MCPOAuth.Credentials?) -> Status {
        if let status = statuses[server.id] { return status }
        guard let registration = credentials?.registration,
            registration.resource == Self.resource(of: server),
            let token = credentials?.token
        else { return .signedOut }
        return token.needsRefresh(now: Date()) && token.refreshToken == nil ? .required : .signedIn
    }

    /// 执行完整的授权码登录流程（发现、注册、PKCE、浏览器授权、换取 token）并持久化凭证。
    func signIn(server: MCPServer, credentials: MCPOAuth.Credentials) async throws {
        guard signingIn == nil else { throw MCPOAuth.Failure.signInInProgress }
        guard case .http(let url, _) = server.transport else { throw MCPOAuth.Failure.invalidMetadata }
        let revision = UUID()
        revisions[server.id] = revision
        refreshes.removeValue(forKey: server.id)?.cancel()
        signingIn = server.id
        statuses[server.id] = .signingIn
        let callback = MCPOAuthListener()
        listener = callback
        defer {
            callback.cancel()
            listener = nil
            signingIn = nil
        }
        do {
            let discovery = try await MCPOAuthService.discover(url)
            try checkRevision(server.id, revision)
            let registration = try await MCPOAuthService.registration(
                for: discovery, credentials: credentials)
            let pair = try MCPOAuthService.pkce()
            let state = MCPOAuth.base64URL(try MCPOAuthService.random())
            try await callback.start(
                state: state, issuer: registration.issuer,
                requiresIssuer: discovery.metadata.authorization_response_iss_parameter_supported == true)
            let authorize = try MCPOAuth.authorizeURL(
                metadata: discovery.metadata, registration: registration,
                challenge: pair.challenge, state: state, scope: discovery.scope)
            try checkRevision(server.id, revision)
            guard NSWorkspace.shared.open(authorize) else { throw MCPOAuth.Failure.network }
            let code = try await callback.code()
            let token = try await MCPOAuthService.token(
                registration: registration, code: code, verifier: pair.verifier)
            try checkRevision(server.id, revision)
            var stored = secrets.secrets(for: server.id)
            var signedIn = credentials
            signedIn.registration = registration
            signedIn.token = token
            stored.oauth = signedIn
            try secrets.save(stored, for: server.id)
            statuses[server.id] = .signedIn
        } catch {
            if revisions[server.id] == revision {
                statuses[server.id] =
                    error is CancellationError ? .signedOut : .failed(error.localizedDescription)
            }
            throw error
        }
    }

    /// 登出：取消进行中的登录与刷新，清除已存 token 并将状态置为未登录。
    func signOut(_ id: UUID) throws {
        cancelSignIn(id)
        revisions[id] = UUID()
        refreshes.removeValue(forKey: id)?.cancel()
        var stored = secrets.secrets(for: id)
        stored.oauth?.token = nil
        try secrets.save(stored, for: id)
        statuses[id] = .signedOut
    }

    /// 取消指定服务器正在进行的登录；已发出的刷新仍会自然结束（轮换式服务端可能已消耗旧 token）。
    func cancelSignIn(_ id: UUID) {
        guard signingIn == id else { return }
        revisions[id] = UUID()
        listener?.cancel()
        statuses[id] = .signedOut
    }

    /// 停止所有进行中的登录流程。
    func stop() {
        if let signingIn { cancelSignIn(signingIn) }
    }

    /// 为 CLI 借出 token：一个 turn 内持用，因此可行时给剩余有效期至少十分钟的 token。
    func lentToken(for server: MCPServer) async throws -> String {
        do {
            return try await accessToken(for: server, lasting: 600)
        } catch let failure as MCPOAuth.Failure where failure == .signInRequired {
            throw failure
        } catch {
            return try await accessToken(for: server)
        }
    }

    /// 获取可用 access token；必要时合并并发刷新，并在 token 被拒或过期时自动刷新。
    func accessToken(
        for server: MCPServer, rejectedToken: String? = nil, lasting margin: TimeInterval = 60
    ) async throws -> String {
        guard statuses[server.id] != .required else { throw MCPOAuth.Failure.signInRequired }
        let credentials = secrets.secrets(for: server.id).oauth
        guard let registration = credentials?.registration,
            registration.resource == Self.resource(of: server),
            let token = credentials?.token
        else {
            requireSignIn(server, stored: credentials)
            throw MCPOAuth.Failure.signInRequired
        }
        if let pending = refreshes[server.id] { return try await pending.value }
        // 没有 refresh token 就无法续期，主动请求续期反而会结束会话。
        let within = token.refreshToken == nil ? 60 : margin
        if rejectedToken != token.accessToken, !token.needsRefresh(now: Date(), within: within) {
            return token.accessToken
        }
        let revision = revisions[server.id] ?? UUID()
        revisions[server.id] = revision
        let task = Task { [weak self] in
            let refreshed = try await MCPOAuthService.token(registration: registration, previous: token)
            guard let self else { throw CancellationError() }
            try self.checkRevision(server.id, revision)
            var stored = self.secrets.secrets(for: server.id)
            guard stored.oauth?.registration == registration else { throw CancellationError() }
            stored.oauth?.token = refreshed
            try self.secrets.save(stored, for: server.id)
            return refreshed.accessToken
        }
        refreshes[server.id] = task
        defer { if refreshes[server.id] == task { refreshes[server.id] = nil } }
        do {
            let value = try await task.value
            try checkRevision(server.id, revision)
            statuses[server.id] = .signedIn
            return value
        } catch MCPOAuth.Failure.signInRequired {
            // 只有被拒绝的 grant 才会结束会话；离线刷新失败会在下次请求时重试。
            if revisions[server.id] == revision { statuses[server.id] = .required }
            throw MCPOAuth.Failure.signInRequired
        }
    }

    /// 将指定服务器标记为需要重新登录（使用已存凭证）。
    func requireSignIn(_ server: MCPServer) {
        requireSignIn(server, stored: secrets.secrets(for: server.id).oauth)
    }

    /// 对编辑过的 URL 做 Test Connection 不能代表已保存服务器持有的会话。
    private func requireSignIn(_ server: MCPServer, stored: MCPOAuth.Credentials?) {
        if let resource = stored?.registration?.resource, resource != Self.resource(of: server) { return }
        statuses[server.id] = .required
    }

    /// 由服务器传输配置推导其 OAuth resource 标识；非 HTTP 传输返回 nil。
    private static func resource(of server: MCPServer) -> String? {
        guard case .http(let url, _) = server.transport else { return nil }
        return try? MCPOAuth.resource(url)
    }

    /// 校验当前操作所属的版本号仍为最新，否则以 CancellationError 放弃。
    private func checkRevision(_ id: UUID, _ revision: UUID) throws {
        try Task.checkCancellation()
        guard revisions[id] == revision else { throw CancellationError() }
    }
}
