// 文件职责：按 OAuth 2.0 组装 MCP 的令牌请求与动态客户端注册请求体。
// 分层：Model；不得 import AppKit/SwiftUI，仅构造 URLRequest/Data，不发起网络请求。
import Foundation

/// OAuth 请求构造：令牌交换/刷新与客户端注册。
enum MCPOAuthRequest {
    /// 构造令牌请求：有 code 时走授权码交换，否则尝试 refresh_token。
    static func token(
        registration: MCPOAuth.Registration, code: String?, verifier: String?, previous: MCPOAuth.Token?
    ) throws -> URLRequest {
        var fields = ["client_id": registration.clientID, "resource": registration.resource]
        if let code, let verifier {
            fields["grant_type"] = "authorization_code"
            fields["code"] = code
            fields["code_verifier"] = verifier
            fields["redirect_uri"] = registration.redirectURI
        } else if let refresh = previous?.refreshToken, !refresh.isEmpty {
            fields["grant_type"] = "refresh_token"
            fields["refresh_token"] = refresh
        } else {
            throw MCPOAuth.Failure.signInRequired
        }
        var request = URLRequest(url: try MCPOAuth.endpoint(registration.tokenEndpoint), timeoutInterval: 30)
        if registration.authMethod == "client_secret_basic", let secret = registration.clientSecret {
            let basic = MCPOAuth.escape(registration.clientID) + ":" + MCPOAuth.escape(secret)
            request.setValue(
                "Basic " + Data(basic.utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        } else if registration.authMethod == "client_secret_post" {
            fields["client_secret"] = registration.clientSecret
        }
        request.httpMethod = "POST"
        request.httpBody = MCPOAuth.form(fields)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// 构造动态客户端注册请求体（公开客户端，无密钥）。
    static func registration(redirectURI: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "client_name": "GearMac", "application_type": "native",
            "redirect_uris": [redirectURI],
            "grant_types": ["authorization_code", "refresh_token"], "response_types": ["code"],
            "token_endpoint_auth_method": "none"
        ])
    }
}
