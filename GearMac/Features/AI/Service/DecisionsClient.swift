// 文件职责：以一次性、无缓存的 HTTPS 会话调用 Decisions 网关，判定文本并解码结构化答案。
// 分层：Service；Sendable 值类型，网络与解码不占用主 actor；密钥只在请求头出现，绝不进入日志或错误。
import Foundation

/// Decisions API 客户端：端点与模型来自所选 API 连接，密钥由调用方在最后一刻传入。
struct DecisionsClient: Sendable {

    /// 面向用户的失败原因；`message(_:)` 是按界面语言解析的文案。
    enum ClientError: LocalizedError, Equatable {
        /// 401/403 且与密钥或租户有关。
        case unauthorized
        /// 403 且网关明确说模型不可用。
        case modelUnavailable
        /// 其余 4xx：参数形状不合法（如 union_tag_invalid、name 重复）。
        case invalidRequest(String)
        case rateLimited
        case serverUnavailable
        case network(String)
        /// 响应合法但一条答案都没有。
        case emptyResponse
        case decoding
        /// 远端端点未配置密钥；仅回环地址允许无密钥。
        case missingKey
        /// 没有任何启用的 API 连接提供 Decisions 模型。
        case noRoute
        case keychainRead
        case badEndpoint(String)

        var errorDescription: String? { message(.english) }

        func message(_ language: AppLanguage) -> String {
            switch self {
            case .unauthorized:
                return L10n.string(AIKey.decisionsErrorUnauthorized, language: language)
            case .modelUnavailable:
                return L10n.string(AIKey.decisionsErrorModelUnavailable, language: language)
            case .invalidRequest(let detail):
                return String(
                    format: L10n.string(AIKey.decisionsErrorInvalidRequest, language: language),
                    detail)
            case .rateLimited:
                return L10n.string(AIKey.decisionsErrorRateLimited, language: language)
            case .serverUnavailable:
                return L10n.string(AIKey.decisionsErrorServer, language: language)
            case .network:
                return L10n.string(AIKey.decisionsErrorNetwork, language: language)
            case .emptyResponse:
                return L10n.string(AIKey.decisionsErrorEmptyResponse, language: language)
            case .decoding:
                return L10n.string(AIKey.decisionsErrorDecoding, language: language)
            case .missingKey:
                return L10n.string(AIKey.decisionsErrorMissingKey, language: language)
            case .noRoute:
                return L10n.string(AIKey.decisionsErrorNoRoute, language: language)
            case .keychainRead:
                return L10n.string(AIKey.decisionsErrorKeychain, language: language)
            case .badEndpoint(let reason):
                return String(
                    format: L10n.string(AIKey.decisionsErrorBadEndpoint, language: language),
                    reason)
            }
        }
    }

    /// 网关 base URL（形如 `https://…/v1`），`/decisions` 与 `/models` 由此拼接。
    let endpoint: URL
    let model: String
    /// 可为空；空密钥只对回环端点合法，且此时不发 Authorization 头。
    let apiKey: String

    /// 判定一段文本：问题集在发出前再校验一次，答案按网关返回顺序交回。
    func decide(
        _ input: String, questions: DecisionsQuestionSet
    ) async throws -> DecisionsResponse {
        try questions.validated()
        var request = URLRequest(url: endpoint.appending(path: "decisions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthentication(to: &request)
        request.httpBody = try JSONSerialization.data(
            withJSONObject: DecisionsRequestBody.make(
                model: model, input: input, questions: questions.questions))

        let (data, response) = try await Self.run(request)
        let http = try Self.httpResponse(response)
        try Self.checkStatus(http, data: data)
        let decoded: DecisionsResponse
        do {
            decoded = try JSONDecoder().decode(DecisionsResponse.self, from: data)
        } catch {
            throw ClientError.decoding
        }
        guard !decoded.answers.isEmpty else { throw ClientError.emptyResponse }
        return decoded
    }

    /// 只在持有密钥时注入 Bearer 头；回环测试端点可以不带。
    private func applyAuthentication(to request: inout URLRequest) {
        guard !apiKey.isEmpty else { return }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    /// 创建一次性、无缓存的 URLSession，并在请求结束后立即销毁。
    private static func run(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        do {
            return try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw error
        } catch let error as URLError {
            throw ClientError.network(error.localizedDescription)
        } catch {
            // 取消以外的意外错误按网络失败上报；不携带请求体细节。
            throw ClientError.network("request failed")
        }
    }

    private static func httpResponse(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.decoding
        }
        return http
    }

    /// 按文档 §9 映射状态码；403 需要看正文区分密钥问题与模型不可用。
    private static func checkStatus(_ http: HTTPURLResponse, data: Data) throws {
        guard !(200..<300).contains(http.statusCode) else { return }
        let detail = Self.detail(from: data)
        switch http.statusCode {
        case 401:
            throw ClientError.unauthorized
        case 403:
            if detail.contains("model") { throw ClientError.modelUnavailable }
            throw ClientError.unauthorized
        case 429:
            throw ClientError.rateLimited
        case 400...499:
            throw ClientError.invalidRequest(detail)
        default:
            throw ClientError.serverUnavailable
        }
    }

    /// 从错误响应里取一段简短、可读的原因；只保留网关生成的文本，不回显请求内容。
    private static func detail(from data: Data) -> String {
        guard
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return "HTTP error" }
        let candidates = [object["error"], object["detail"], object["message"]]
        for candidate in candidates {
            if let text = candidate as? String { return Self.clamped(text) }
            if let nested = candidate as? [String: Any], let text = nested["message"] as? String {
                return Self.clamped(text)
            }
        }
        return "HTTP error"
    }

    /// 错误原因截断到一行，避免网关的长堆栈撑爆面板。
    private static func clamped(_ text: String) -> String {
        let prefix = String(text.prefix(160))
        return prefix.contains("\n") ? String(prefix.prefix(while: { $0 != "\n" })) : prefix
    }
}
