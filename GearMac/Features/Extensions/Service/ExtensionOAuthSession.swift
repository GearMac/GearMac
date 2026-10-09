// 文件职责：实现 OAuth 2.0 PKCE 授权会话：用默认浏览器打开授权页面，并通过 `raycast://` / `gearmac://` 回调完成换取 token。
// 分层：Service；@MainActor 隔离，全局只允许一个活跃会话（activeSession），await 结束后必须在 finish 中恢复 continuation。
import AppKit
import Foundation

/// 发起授权所需的参数。
struct ExtensionOAuthAuthorizeOptions: Sendable {
    let url: URL
    let state: String?
}

/// 授权完成后回调得到的结果（授权码、可选 access token 与 state）。
struct ExtensionOAuthAuthorizeResult: Sendable {
    let authorizationCode: String
    let accessToken: String?
    let state: String?
}

/// 一个 OAuth 2.0 PKCE 会话：浏览器完成授权后由 `oauth` 回调结束会话。
@MainActor
final class ExtensionOAuthSession {
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var expectedState: String?
    private var timeoutTimer: Timer?

    private static weak var activeSession: ExtensionOAuthSession?

    /// 会话是否仍在等待浏览器回调。
    var isAuthorizing: Bool {
        continuation != nil
    }

    /// 授权过程中可能出现的错误。
    enum OAuthError: LocalizedError {
        case canceled
        case failed(String)
        case stateMismatch

        var errorDescription: String? {
            switch self {
            case .canceled: return "Authentication was canceled."
            case .failed(let message): return message
            case .stateMismatch: return "OAuth state mismatch. Please try authenticating again."
            }
        }
    }

    /// 描述一个深度链接的实际归宿，使调用方可以区分「不是我们的链接」与「回来得太晚」。
    enum Callback {
        case delivered
        case expired
        case ignored
    }

    /// 处理来自 app delegate 的深度链接，例如 `raycast://oauth?code=…`。
    static func handleCallbackURL(_ url: URL) -> Callback {
        guard let scheme = url.scheme?.lowercased(),
            scheme == "raycast" || scheme == "gearmac" || scheme == "com.raycast"
        else { return .ignored }

        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        guard
            host == "oauth" || host == "redirect"
                || path == "/oauth" || path == "/redirect"
                || path.hasPrefix("/oauth/") || path.hasPrefix("/redirect/")
        else {
            return .ignored
        }

        // 浏览器可能在会话已经消失（退出、超时或被销毁）后才回来。
        guard let active = activeSession else { return .expired }
        active.receiveCallback(url: url)
        return .delivered
    }

    /// 发起授权并直接返回结构化结果（授权码、access token、state）。
    func authorize(options: ExtensionOAuthAuthorizeOptions) async throws -> ExtensionOAuthAuthorizeResult {
        let params = try await authorize(url: options.url, expectedState: options.state)
        let code = params["code"] ?? ""
        let token = params["access_token"]
        let state = params["state"]
        return ExtensionOAuthAuthorizeResult(authorizationCode: code, accessToken: token, state: state)
    }

    /// 发起授权：用 NSWorkspace 打开授权 URL，并挂起至回调（或 300 秒超时）后返回回调参数表。
    func authorize(
        url: URL,
        expectedState: String? = nil
    ) async throws -> [String: String] {
        if continuation != nil {
            cancel()
        }

        self.expectedState = expectedState
        Self.activeSession = self

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            self.timeoutTimer?.invalidate()
            self.timeoutTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.finish(error: OAuthError.failed("Authentication timed out."))
                }
            }

            let opened = NSWorkspace.shared.open(url)
            if !opened {
                self.finish(error: OAuthError.failed("Failed to open authorization URL in default browser."))
            }
        }
    }

    /// 收到回调：优先上报 error，其次校验 state（如期望非空），最后以参数表结束会话。
    private func receiveCallback(url: URL) {
        let params = Self.parseCallback(url: url)
        if let error = params["error"] {
            let desc = params["error_description"] ?? error
            finish(error: OAuthError.failed(desc))
            return
        }

        if let expected = expectedState, !expected.isEmpty {
            guard let received = params["state"], !received.isEmpty, received == expected else {
                finish(error: OAuthError.stateMismatch)
                return
            }
        }

        finish(result: params)
    }

    /// 统一收尾：停掉超时定时器、清空活跃会话引用，并用结果或错误恢复 continuation。
    private func finish(result: [String: String]? = nil, error: Error? = nil) {
        timeoutTimer?.invalidate()
        timeoutTimer = nil

        if Self.activeSession === self {
            Self.activeSession = nil
        }

        if let continuation = self.continuation {
            self.continuation = nil
            if let error {
                continuation.resume(throwing: error)
            } else if let result {
                continuation.resume(returning: result)
            } else {
                continuation.resume(throwing: OAuthError.canceled)
            }
        }
    }

    /// 取消当前授权，使等待方以 canceled 错误结束。
    func cancel() {
        finish(error: OAuthError.canceled)
    }

    // MARK: - URL Parsing

    /// 解析回调 URL：合并 query 与 fragment（`#code=…` 形式的隐式回调）中的键值对。
    static func parseCallback(url: URL) -> [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return [:]
        }
        var result: [String: String] = [:]
        if let queryItems = components.queryItems {
            for item in queryItems {
                result[item.name] = item.value ?? ""
            }
        }
        // 隐式与 hash 回调以 `raycast://oauth#code=…` 的形式到达。
        if let fragment = components.fragment, !fragment.isEmpty {
            let pairs = fragment.split(separator: "&")
            for pair in pairs {
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    let key = String(parts[0])
                    let val = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                    result[key] = val
                }
            }
        }
        return result
    }
}
