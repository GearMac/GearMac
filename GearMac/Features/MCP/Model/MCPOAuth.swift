// 文件职责：MCP 的 OAuth 2.0 客户端：端点发现、PKCE、授权 URL、回调校验与令牌解析。
// 分层：Model；不得 import AppKit/SwiftUI，仅做协议计算与校验，不发起网络请求。
import Foundation

/// MCP 的 OAuth 2.0 支持：元数据发现、PKCE、授权与令牌处理。
enum MCPOAuth {
    /// 登录过程中的失败类型，附带面向用户的描述。
    enum Failure: LocalizedError, Equatable {
        case invalidMetadata
        case unsupportedPKCE
        case clientRequired
        case issuerChanged
        case invalidCallback
        case denied
        case invalidToken
        case signInRequired
        case network
        case registration
        case listenerUnavailable
        case signInInProgress
        case timedOut

        var errorDescription: String? { message(.english) }

        /// 按指定语言解析错误描述。
        func message(_ language: AppLanguage) -> String {
            switch self {
            case .invalidMetadata:
                return L10n.string(MCPKey.oauthInvalidMetadata, language: language)
            case .unsupportedPKCE:
                return L10n.string(MCPKey.oauthPKCEUnsupported, language: language)
            case .clientRequired:
                return L10n.string(MCPKey.oauthClientRequired, language: language)
            case .issuerChanged:
                return L10n.string(MCPKey.oauthIssuerChanged, language: language)
            case .invalidCallback:
                return L10n.string(MCPKey.oauthInvalidCallback, language: language)
            case .denied: return L10n.string(MCPKey.oauthDeclined, language: language)
            case .invalidToken: return L10n.string(MCPKey.oauthNoToken, language: language)
            case .signInRequired:
                return L10n.string(MCPKey.oauthSignInRequired, language: language)
            case .network: return L10n.string(MCPKey.oauthNetwork, language: language)
            case .registration: return L10n.string(MCPKey.oauthRegistration, language: language)
            case .listenerUnavailable:
                return L10n.string(MCPKey.oauthPortUnavailable, language: language)
            case .signInInProgress:
                return L10n.string(MCPKey.oauthInProgress, language: language)
            case .timedOut: return L10n.string(MCPKey.oauthTimedOut, language: language)
            }
        }
    }

    /// 已保存的 OAuth 凭据：客户端 ID/密钥、注册信息与令牌。
    struct Credentials: Codable, Equatable, Sendable {
        var clientID: String = ""
        var clientSecret: String = ""
        var registration: Registration?
        var token: Token?

        /// 粘贴的 ID 常以换行结尾，而 Google 会因此返回 "client not found"。
        static func supplied(clientID: String, clientSecret: String) -> Credentials {
            Credentials(
                clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
                clientSecret: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// 动态客户端注册的结果：客户端 ID、端点与回调地址。
    struct Registration: Codable, Equatable, Sendable {
        let resource: String
        let issuer: String
        let clientID: String
        let clientSecret: String?
        let tokenEndpoint: String
        let authMethod: String
        let redirectURI: String
    }

    /// OAuth 访问令牌及其刷新令牌、过期时间与授权范围。
    struct Token: Codable, Equatable, Sendable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
        let scope: String?

        /// 判断令牌是否将在给定余量内过期而需要刷新。
        func needsRefresh(now: Date, within margin: TimeInterval = 60) -> Bool {
            expiresAt.map { $0.timeIntervalSince(now) <= margin } ?? false
        }
    }

    /// 受保护资源元数据（RFC 9728）。
    struct ResourceMetadata: Decodable, Sendable {
        let resource: String
        let authorization_servers: [String]
        let scopes_supported: [String]?
    }

    /// 授权服务器元数据（RFC 8414 / OIDC 发现）。
    struct ServerMetadata: Decodable, Sendable {
        let issuer: String
        let authorization_endpoint: String
        let token_endpoint: String
        let registration_endpoint: String?
        let code_challenge_methods_supported: [String]?
        let token_endpoint_auth_methods_supported: [String]?
        let scopes_supported: [String]?
        let authorization_response_iss_parameter_supported: Bool?
    }

    /// 校验并返回 OAuth 端点 URL；带用户信息或 fragment 时视为非法。
    static func endpoint(_ value: String) throws -> URL {
        let url = try AIEndpointPolicy.validate(value)
        guard url.user == nil, url.password == nil, url.fragment == nil else { throw Failure.invalidMetadata }
        return url
    }

    /// 规范化 resource 标识：小写 scheme/host，去掉根路径的斜杠。
    static func resource(_ value: String) throws -> String {
        let url = try endpoint(value)
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw Failure.invalidMetadata
        }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = parts.host?.lowercased()
        if parts.path == "/" { parts.path = "" }
        guard let result = parts.string else { throw Failure.invalidMetadata }
        return result
    }

    /// 受保护资源元数据的候选 URL：优先挑战中给出的地址，否则探测 well-known。
    static func protectedMetadataURLs(resource: String, challenge: [String: String]) throws -> [URL] {
        if let location = challenge["resource_metadata"] { return [try endpoint(location)] }
        return try wellKnown(
            resource, suffixes: ["oauth-protected-resource"], appendOIDC: false, rootFallback: true)
    }

    /// 授权服务器元数据的候选 well-known URL 列表。
    static func serverMetadataURLs(issuer: String) throws -> [URL] {
        let url = try endpoint(issuer)
        guard url.query == nil else { throw Failure.invalidMetadata }
        return try wellKnown(
            issuer, suffixes: ["oauth-authorization-server", "openid-configuration"], appendOIDC: true)
    }

    /// 按后缀拼接 `/.well-known/...` 候选地址，并追加 OIDC 或根回退路径。
    private static func wellKnown(
        _ value: String, suffixes: [String], appendOIDC: Bool, rootFallback: Bool = false
    ) throws -> [URL] {
        let url = try endpoint(value)
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw Failure.invalidMetadata
        }
        let encoded = parts.percentEncodedPath
        let path = encoded.hasSuffix("/") ? String(encoded.dropLast()) : encoded
        parts.query = nil
        var results: [URL] = []
        for suffix in suffixes {
            parts.percentEncodedPath = "/.well-known/\(suffix)\(path)"
            if let url = parts.url { results.append(url) }
        }
        if !path.isEmpty {
            if appendOIDC {
                parts.percentEncodedPath = path + "/.well-known/openid-configuration"
            } else if rootFallback {
                parts.percentEncodedPath = "/.well-known/\(suffixes[0])"
            }
            if let url = parts.url, !results.contains(url) { results.append(url) }
        }
        return results
    }

    /// 仅当 scheme、host 与有效端口都未改变时，跳转才可携带凭据。
    static func sameOrigin(_ first: URL, _ second: URL) -> Bool {
        func port(_ url: URL) -> Int { url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80) }
        return first.scheme?.lowercased() == second.scheme?.lowercased()
            && first.host()?.lowercased() == second.host()?.lowercased() && port(first) == port(second)
    }

    /// 判断 resource 是否为 endpoint 的上级（同源且路径为其前缀）。
    static func resourceCovers(_ resource: String, endpoint: String) throws -> Bool {
        let parent = try Self.endpoint(resource)
        let child = try Self.endpoint(endpoint)
        guard sameOrigin(parent, child),
            parent.query == nil || parent.query == child.query
        else { return false }
        let parentPath = parent.path.hasSuffix("/") ? parent.path : parent.path + "/"
        let childPath = child.path.hasSuffix("/") ? child.path : child.path + "/"
        return childPath.hasPrefix(parentPath)
    }

    /// 解析并校验受保护资源元数据；不合规时抛出 `.invalidMetadata`。
    static func parseResource(_ data: Data, expected: String) throws -> ResourceMetadata {
        guard let metadata = try? JSONDecoder().decode(ResourceMetadata.self, from: data),
            try resourceCovers(metadata.resource, endpoint: expected), !metadata.authorization_servers.isEmpty
        else { throw Failure.invalidMetadata }
        for issuer in metadata.authorization_servers { _ = try endpoint(issuer) }
        return metadata
    }

    /// Google 声明的是 `https://accounts.google.com/`，而发布时却不带末尾斜杠。
    static func sameIssuer(_ first: String, _ second: String) -> Bool {
        func bare(_ value: String) -> String { value.hasSuffix("/") ? String(value.dropLast()) : value }
        return bare(first) == bare(second)
    }

    /// 解析并校验授权服务器元数据，要求 issuer 一致且支持 PKCE S256。
    static func parseServer(_ data: Data, issuer: String) throws -> ServerMetadata {
        guard let metadata = try? JSONDecoder().decode(ServerMetadata.self, from: data),
            sameIssuer(metadata.issuer, issuer)
        else { throw Failure.invalidMetadata }
        guard metadata.code_challenge_methods_supported?.contains("S256") == true else {
            throw Failure.unsupportedPKCE
        }
        _ = try endpoint(metadata.authorization_endpoint)
        _ = try endpoint(metadata.token_endpoint)
        if let registration = metadata.registration_endpoint { _ = try endpoint(registration) }
        return metadata
    }

    /// 做 base64url（无填充）编码。
    static func base64URL(_ bytes: Data) -> String {
        bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    /// 由熵生成 PKCE 的 verifier 及其 S256 challenge。
    static func pkce(entropy: Data, sha256: (Data) -> Data) -> (verifier: String, challenge: String) {
        let verifier = base64URL(entropy)
        return (verifier, base64URL(sha256(Data(verifier.utf8))))
    }

    /// 按 key 排序并以 `&` 连接的 form-urlencoded 编码。
    static func form(_ fields: [String: String]) -> Data {
        Data(
            fields.sorted { $0.key < $1.key }.map { "\(escape($0.key))=\(escape($0.value))" }
                .joined(separator: "&").utf8)
    }

    /// 按 RFC 3986 未保留字符集做百分号编码。
    static func escape(_ value: String) -> String {
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    /// 构造授权 URL，覆盖端点原有查询中与本流程保留键冲突的项。
    static func authorizeURL(
        metadata: ServerMetadata, registration: Registration, challenge: String, state: String, scope: String?
    ) throws -> URL {
        let endpoint = try endpoint(metadata.authorization_endpoint)
        guard var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw Failure.invalidMetadata
        }
        var fields = [
            "response_type": "code", "client_id": registration.clientID,
            "redirect_uri": registration.redirectURI, "code_challenge": challenge,
            "code_challenge_method": "S256", "state": state, "resource": registration.resource
        ]
        fields["scope"] = scope
        let reserved = Set(fields.keys).union(["scope"])
        parts.percentEncodedQueryItems =
            (parts.percentEncodedQueryItems ?? []).filter { !reserved.contains($0.name) }
            + fields.sorted { $0.key < $1.key }.map {
                URLQueryItem(name: escape($0.key), value: escape($0.value))
            }
        guard let url = parts.url else { throw Failure.invalidMetadata }
        return url
    }

    /// 校验回调：state 一致、（必要时）iss 匹配、无 error，且返回非空 code。
    static func callback(
        _ target: String, state: String, issuer: String, requiresIssuer: Bool
    ) throws -> String {
        guard target.hasPrefix("/callback?"),
            let parts = URLComponents(string: "http://127.0.0.1" + target), parts.path == "/callback",
            parts.fragment == nil
        else { throw Failure.invalidCallback }
        var fields: [String: String] = [:]
        for part in (parts.percentEncodedQuery ?? "").split(separator: "&") {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2,
                let key = String(pair[0]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding,
                let value = String(pair[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding,
                fields[key] == nil
            else { throw Failure.invalidCallback }
            fields[key] = value
        }
        guard fields["state"] == state,
            fields["iss"].map({ $0 == issuer }) ?? !requiresIssuer
        else { throw Failure.invalidCallback }
        if fields["error"] != nil { throw Failure.denied }
        guard let code = fields["code"], !code.isEmpty else { throw Failure.invalidCallback }
        return code
    }

    /// RFC 6749 §5.2：只有 400 与 401 表示拒绝授权；其它状态码属于服务器故障。
    static func tokenFailure(status: Int) -> Failure {
        status == 400 || status == 401 ? .signInRequired : .network
    }

    /// 解析令牌响应；保留上一次的刷新令牌与 scope 作为回退。
    static func parseToken(_ data: Data, previous: Token?, now: Date) throws -> Token {
        struct Response: Decodable {
            let access_token: String
            let token_type: String
            let refresh_token: String?
            let expires_in: Double?
            let scope: String?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
            response.token_type.lowercased() == "bearer", !response.access_token.isEmpty,
            response.access_token.utf8.allSatisfy({ $0 > 32 && $0 < 127 }),
            response.expires_in.map({ $0.isFinite && $0 > 0 }) ?? true
        else { throw Failure.invalidToken }
        return Token(
            accessToken: response.access_token,
            refreshToken: response.refresh_token ?? previous?.refreshToken,
            expiresAt: response.expires_in.map { now.addingTimeInterval($0) },
            scope: response.scope ?? previous?.scope)
    }
}
