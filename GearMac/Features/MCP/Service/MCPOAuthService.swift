// 文件职责：实现 MCP OAuth 的无状态协议交互，包括元数据发现、客户端注册、token 交换与 PKCE 生成。
// 分层：Service；无状态纯函数集合，不持有状态、不 import AppKit/SwiftUI。
import CryptoKit
import Foundation
import Security

/// OAuth 协议交互的静态入口，服务于 MCPOAuthManager 的登录与刷新流程。
enum MCPOAuthService {
    /// 一次发现流程的结果：资源标识、授权服务器元数据及请求的 scope。
    struct Discovery: Sendable {
        let resource: String
        let metadata: MCPOAuth.ServerMetadata
        let scope: String?
    }

    /// 向目标端点发起探测请求，依次发现受保护资源与授权服务器元数据并推导 scope。
    static func discover(_ url: String) async throws -> Discovery {
        let resource = try MCPOAuth.resource(url)
        var probe = URLRequest(url: try MCPOAuth.endpoint(url), timeoutInterval: 15)
        probe.httpMethod = "POST"
        probe.httpBody = try MCPProtocol.request(
            id: 1, method: "initialize",
            params: [
                "protocolVersion": MCPProtocol.version, "capabilities": [:],
                "clientInfo": ["name": "gearmac", "version": "1"]
            ])
        probe.setValue("application/json", forHTTPHeaderField: "Content-Type")
        probe.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        let (_, response) = try await MCPOAuthHTTP.send(probe)
        let challenge = MCPOAuthChallenge.parse(response.value(forHTTPHeaderField: "WWW-Authenticate"))
        let resourceData = try await discoverDocument(
            MCPOAuth.protectedMetadataURLs(resource: resource, challenge: challenge))
        let protected = try MCPOAuth.parseResource(resourceData, expected: resource)
        let issuer = protected.authorization_servers[0]
        let serverData = try await discoverDocument(MCPOAuth.serverMetadataURLs(issuer: issuer))
        let metadata = try MCPOAuth.parseServer(serverData, issuer: issuer)
        var scope = challenge["scope"] ?? protected.scopes_supported?.joined(separator: " ")
        if metadata.scopes_supported?.contains("offline_access") == true {
            var scopes = (scope ?? "").split(separator: " ").map(String.init)
            if !scopes.contains("offline_access") { scopes.append("offline_access") }
            scope = scopes.joined(separator: " ")
        }
        return Discovery(resource: resource, metadata: metadata, scope: scope)
    }

    /// 逐个尝试候选 URL，返回第一个 2xx 响应体；404/405 继续尝试下一个。
    private static func discoverDocument(_ urls: [URL]) async throws -> Data {
        for url in urls {
            let (data, response) = try await MCPOAuthHTTP.send(URLRequest(url: url, timeoutInterval: 15))
            if (200...299).contains(response.statusCode) { return data }
            guard response.statusCode == 404 || response.statusCode == 405 else {
                throw MCPOAuth.Failure.invalidMetadata
            }
        }
        throw MCPOAuth.Failure.invalidMetadata
    }

    /// 返回可复用的客户端注册信息；必要时用已提供的 client ID 或动态注册重新获取。
    static func registration(
        for discovery: Discovery, credentials: MCPOAuth.Credentials
    ) async throws -> MCPOAuth.Registration {
        let metadata = discovery.metadata
        if let stored = credentials.registration,
            stored.resource == discovery.resource, stored.issuer == metadata.issuer,
            stored.tokenEndpoint == metadata.token_endpoint,
            stored.redirectURI == MCPOAuthListener.redirectURI,
            credentials.clientID.isEmpty
                || (stored.clientID == credentials.clientID
                    && stored.clientSecret == credentials.clientSecret.nilIfEmpty)
        {
            return stored
        }
        if !credentials.clientID.isEmpty {
            if let stored = credentials.registration, stored.issuer != metadata.issuer {
                throw MCPOAuth.Failure.issuerChanged
            }
            let methods = metadata.token_endpoint_auth_methods_supported ?? ["client_secret_basic"]
            let method: String
            if credentials.clientSecret.isEmpty {
                method = "none"
            } else if methods.contains("client_secret_basic") {
                method = "client_secret_basic"
            } else if methods.contains("client_secret_post") {
                method = "client_secret_post"
            } else {
                throw MCPOAuth.Failure.invalidMetadata
            }
            return MCPOAuth.Registration(
                resource: discovery.resource, issuer: metadata.issuer,
                clientID: credentials.clientID, clientSecret: credentials.clientSecret.nilIfEmpty,
                tokenEndpoint: metadata.token_endpoint, authMethod: method,
                redirectURI: MCPOAuthListener.redirectURI)
        }
        guard let endpoint = metadata.registration_endpoint else { throw MCPOAuth.Failure.clientRequired }
        let body = try MCPOAuthRequest.registration(redirectURI: MCPOAuthListener.redirectURI)
        let data: Data
        do {
            data = try await MCPOAuthHTTP.json(MCPOAuth.endpoint(endpoint), body: body)
        } catch {
            try Task.checkCancellation()
            throw MCPOAuth.Failure.registration
        }
        struct Registered: Decodable {
            let client_id: String
            let client_secret: String?
            let token_endpoint_auth_method: String?
            let redirect_uris: [String]?
        }
        guard let response = try? JSONDecoder().decode(Registered.self, from: data),
            !response.client_id.isEmpty,
            response.redirect_uris?.contains(MCPOAuthListener.redirectURI) ?? true,
            response.token_endpoint_auth_method == nil || response.token_endpoint_auth_method == "none"
        else { throw MCPOAuth.Failure.registration }
        return MCPOAuth.Registration(
            resource: discovery.resource, issuer: metadata.issuer,
            clientID: response.client_id, clientSecret: response.client_secret,
            tokenEndpoint: metadata.token_endpoint, authMethod: "none",
            redirectURI: MCPOAuthListener.redirectURI)
    }

    /// 交换或刷新 token：code 非空时用授权码交换，previous 非空时用 refresh token 续期。
    static func token(
        registration: MCPOAuth.Registration, code: String? = nil, verifier: String? = nil,
        previous: MCPOAuth.Token? = nil
    ) async throws -> MCPOAuth.Token {
        let request = try MCPOAuthRequest.token(
            registration: registration, code: code,
            verifier: verifier, previous: previous)
        let (data, response) = try await MCPOAuthHTTP.send(request)
        guard (200...299).contains(response.statusCode) else {
            throw MCPOAuth.tokenFailure(status: response.statusCode)
        }
        return try MCPOAuth.parseToken(data, previous: previous, now: Date())
    }

    /// 用系统安全随机数生成 32 字节熵，失败时抛出 invalidCallback。
    static func random() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw MCPOAuth.Failure.invalidCallback
        }
        return Data(bytes)
    }

    /// 基于随机熵生成 PKCE 的 verifier 与 challenge 对。
    static func pkce() throws -> (verifier: String, challenge: String) {
        MCPOAuth.pkce(entropy: try random()) { Data(SHA256.hash(data: $0)) }
    }
}

private extension String {
    /// 空字符串返回 nil，否则返回自身。
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
