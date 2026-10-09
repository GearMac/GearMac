// 文件职责：向各 AI 提供方发起模型清单请求，并把 HTTP 状态与响应解码映射为发现错误。
// 分层：Service；只做网络 IO 与错误映射，不缓存任何响应，不依赖 UI。
import Foundation

/// 模型发现服务：查询提供方当前可用的模型清单，无状态且可安全跨并发使用。
final class AIModelDiscoveryService: Sendable {
    /// 每个进程共用一个 session（而非每个编辑器面板一个）；禁用缓存，确保磁盘上不残留任何响应。
    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }()

    /// 按提供方与 baseURL 查询可用模型；按 HTTP 状态码区分密钥被拒、不支持、服务不可用与响应格式错误。
    func models(
        provider: AIProviderKind, baseURL: URL, apiKey: String
    ) async throws -> [AIModelDiscovery.Model] {
        let query = try AIModelDiscovery.query(
            provider: provider, baseURL: baseURL, apiKey: apiKey,
            appTitle: Bundle.main.appDisplayName)
        let (data, response) = try await Self.session.data(for: query.request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else {
            throw AIModelDiscovery.DiscoveryError.unavailable
        }
        switch response.statusCode {
        case 200:
            do {
                return try AIModelDiscovery.decode(data, shape: query.responseShape)
            } catch {
                throw AIModelDiscovery.DiscoveryError.malformedResponse
            }
        case 401, 403:
            throw AIModelDiscovery.DiscoveryError.rejectedKey
        case 404, 405, 501:
            throw AIModelDiscovery.DiscoveryError.unsupported
        default:
            throw AIModelDiscovery.DiscoveryError.unavailable
        }
    }
}
