// 文件职责：为 MCP 的 OAuth 流程提供定制 URLSession，控制重定向时是否跟随及是否保留 Authorization 头。
// 分层：Service；不 import AppKit/SwiftUI，仅负责网络层配置与发送。
import Foundation

/// 实现 URLSessionTaskDelegate 的 OAuth 专用 URLSession 配置与发送入口。
final class MCPOAuthHTTP: NSObject, URLSessionTaskDelegate, Sendable {
    private let followsSameOrigin: Bool

    init(followsSameOrigin: Bool) { self.followsSameOrigin = followsSameOrigin }

    /// 重定向回调：仅当允许跟随同源跳转且新旧地址同源时保留原请求头，否则拒绝重定向。
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard followsSameOrigin, let from = response.url, let to = request.url,
            MCPOAuth.sameOrigin(from, to)
        else { return completionHandler(nil) }
        // URLSession 在重定向时会抹掉 Authorization；在同一源内恢复包头是安全的。
        var next = request
        for (name, value) in task.originalRequest?.allHTTPHeaderFields ?? [:]
        where next.value(forHTTPHeaderField: name) == nil {
            next.setValue(value, forHTTPHeaderField: name)
        }
        completionHandler(next)
    }

    /// OAuth 端点會拒绝一切重定向；MCP 端点则允许在自己的源内跳转。
    static func session(followsSameOrigin: Bool = false) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(
            configuration: configuration, delegate: MCPOAuthHTTP(followsSameOrigin: followsSameOrigin),
            delegateQueue: nil)
    }

    /// 发送请求并同步读取完整响应体，超过 limit 字节或网络异常时抛出 MCPOAuth.Failure.network。
    static func send(_ request: URLRequest, limit: Int = 1_048_576) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw MCPOAuth.Failure.invalidMetadata }
        _ = try MCPOAuth.endpoint(url.absoluteString)
        let session = session()
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw MCPOAuth.Failure.network }
            var data = Data()
            for try await byte in bytes {
                guard data.count < limit else { throw MCPOAuth.Failure.network }
                data.append(byte)
            }
            return (data, response)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            throw MCPOAuth.Failure.network
        }
    }

    /// 发起一次 JSON HTTP 请求（无 body 则 GET，有 body 则 POST）并校验状态码为 2xx。
    static func json(
        _ url: URL, body: Data? = nil, contentType: String = "application/json"
    ) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await send(request)
        guard (200...299).contains(response.statusCode) else { throw MCPOAuth.Failure.network }
        return data
    }
}
