// 文件职责：定义 MCP 传输层协议、传输错误类型与服务器连接状态枚举。
// 分层：Service（协议/模型）；@MainActor 约束传输实现，不 import AppKit/SwiftUI。
import Foundation

/// 单个服务器的通信通道。两类传输都自行关联请求与响应，区别只在消息帧格式。
@MainActor
protocol MCPTransport: AnyObject {
    /// 建立连接（HTTP 为标记就绪，stdio 为启动子进程）。
    func connect() async throws
    /// 发送请求并等待与 id 对应的响应。
    func request(_ method: String, _ params: [String: Any]?) async throws -> JSONValue
    /// 发送无需回复的通知。
    func notify(_ method: String, _ params: [String: Any]?) throws
    /// 关闭连接并释放底层资源。
    func close()
}

extension MCPTransport {
    /// 不带参数的 request 便捷重载，等价于传入 nil。
    func request(_ method: String) async throws -> JSONValue {
        try await request(method, nil)
    }
}

/// 传输层可能出现的错误，统一映射为本地化文案。
enum MCPTransportError: LocalizedError, Equatable {
    case notRunning
    case launchFailed(String)
    case invalidEndpoint(String)
    case requestFailed(String)
    case malformedResponse
    case timedOut

    /// 面向用户的错误描述文本。
    var errorDescription: String? { message(.english) }

    /// 按指定语言解析错误描述文本。
    func message(_ language: AppLanguage) -> String {
        switch self {
        case .notRunning: return L10n.string(MCPKey.errorNotRunning, language: language)
        case .launchFailed(let detail): return detail
        case .invalidEndpoint(let detail): return detail
        case .requestFailed(let detail): return detail
        case .malformedResponse:
            return L10n.string(MCPKey.errorMalformedResponse, language: language)
        case .timedOut: return L10n.string(MCPKey.errorTimedOut, language: language)
        }
    }
}

/// 设置行展示的内容，同时决定该服务器的工具是否可以被提供。
enum MCPServerStatus: Equatable, Sendable {
    case stopped
    case signInRequired
    case connecting
    case ready(tools: Int)
    case failed(String)

    /// 仅就绪状态返回 true。
    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    /// 供 UI 展示的状态文案。
    func label(_ language: AppLanguage) -> String {
        switch self {
        case .stopped: return L10n.string(MCPKey.statusStopped, language: language)
        case .signInRequired:
            return L10n.string(MCPKey.statusSignInRequired, language: language)
        case .connecting: return L10n.string(MCPKey.statusConnecting, language: language)
        case .ready(let tools):
            let key = tools == 1 ? MCPKey.statusToolCountOne : MCPKey.statusToolCount
            return String(format: L10n.string(key, language: language), tools)
        case .failed(let message): return message
        }
    }
}
