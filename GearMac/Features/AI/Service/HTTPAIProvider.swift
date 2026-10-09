// 文件职责：以 HTTP 流式请求（SSE）调用 OpenAI 兼容 / Anthropic 等 BYOK 接口，并把字节流解码为事件。
// 分层：Service；网络与 JSON 解码均在分离任务中进行，不占用主 actor，也不缓存响应。
import Foundation

/// BYOK HTTP 提供方：按端点形状组织请求、注入认证头，并把响应流解析为统一事件。
struct HTTPAIProvider: AIProvider {
    private let configuration: AIHTTPConfiguration
    private let apiKey: String

    /// 以端点配置与 API 密钥构造提供方。
    init(configuration: AIHTTPConfiguration, apiKey: String) {
        self.configuration = configuration
        self.apiKey = apiKey
    }

    /// 以字节流方式请求接口并逐行解码事件；状态码、取消与网络错误都映射为 `AIProviderError`。
    func stream(_ request: AIRequest) -> AIProviderStream {
        AIProviderStream { continuation in
            // 有意使用 detached：字节循环与 JSON 解码绝不接触主 actor。
            let task = Task.detached {
                let session = Self.makeSession()
                defer { session.invalidateAndCancel() }
                do {
                    let urlRequest = try makeURLRequest(request)
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let response = response as? HTTPURLResponse else {
                        throw AIProviderError.responseFailed(
                            "The provider returned an invalid HTTP response.")
                    }
                    guard response.statusCode == 200 else {
                        throw AIProviderError.responseFailed(Self.statusMessage(response))
                    }
                    var decoder = AIStreamDecoder(shape: configuration.shape)
                    var chunk = Data()
                    chunk.reserveCapacity(2_048)
                    // 按行而非按 2 KB：短回复必须在流关闭之前就显示出来。
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        chunk.append(byte)
                        if byte == 0x0A {
                            for event in try decoder.feed(chunk) { continuation.yield(event) }
                            chunk.removeAll(keepingCapacity: true)
                            if decoder.isTerminal { break }
                        }
                    }
                    if !chunk.isEmpty, !decoder.isTerminal {
                        for event in try decoder.feed(chunk) { continuation.yield(event) }
                    }
                    if !decoder.isTerminal {
                        for event in try decoder.finish() { continuation.yield(event) }
                    }
                    guard decoder.isTerminal else {
                        throw AIProviderError.responseFailed(
                            "The connection closed before the response completed.")
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as URLError {
                    continuation.finish(
                        throwing: AIProviderError.responseFailed(Self.networkMessage(error.code)))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 组装 POST 请求：JSON 体、SSE 响应类型与认证头。
    private func makeURLRequest(_ input: AIRequest) throws -> URLRequest {
        var request = URLRequest(url: configuration.endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        applyAuthentication(to: &request)
        request.httpBody = try JSONSerialization.data(
            withJSONObject: AIRequestBody.make(input, configuration: configuration))
        return request
    }

    /// 各路由的凭证与自身标识头；请求体对此一无所知。
    private func applyAuthentication(to request: inout URLRequest) {
        switch configuration.shape {
        case .openAICompatible:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            if configuration.provider == .gemini {
                request.setValue(Self.googleClientHeader, forHTTPHeaderField: "x-goog-api-client")
            } else if configuration.provider == .openRouter {
                request.setValue(Bundle.main.appDisplayName, forHTTPHeaderField: "X-OpenRouter-Title")
            }
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
    }

    /// Google 侧请求头使用的客户端标识（含应用版本）。
    private static var googleClientHeader: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return "gearmac-oai/\(version)"
    }

    /// 创建一次性、无缓存的 URLSession。
    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }

    /// 把 HTTP 状态码转成面向用户的错误文案（密钥、限流、服务不可用等）。
    private static func statusMessage(_ response: HTTPURLResponse) -> String {
        switch response.statusCode {
        case 401, 403:
            return "API key rejected — check it in Settings."
        case 429:
            guard let retryAfter = response.value(forHTTPHeaderField: "Retry-After"),
                let seconds = Int(retryAfter), seconds >= 0
            else { return "Rate limit reached — try again later." }
            return "Rate limit reached — retry after \(seconds) seconds."
        case 500...599:
            return "The provider is temporarily unavailable (HTTP \(response.statusCode))."
        default:
            return "The provider rejected the model or request (HTTP \(response.statusCode))."
        }
    }

    /// 把 `URLError` 的常见连接错误转为可读的文本。
    private static func networkMessage(_ code: URLError.Code) -> String {
        switch code {
        case .networkConnectionLost: return "The network connection was lost."
        case .notConnectedToInternet: return "No internet connection."
        case .timedOut: return "The provider took too long to respond."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "The provider could not be reached."
        default: return "The network request failed."
        }
    }
}
