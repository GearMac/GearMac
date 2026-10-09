// 文件职责：定义所有 AI 提供方统一遵循的流式接口，以及流事件序列的类型别名。
// 分层：Service；协议不含 UI 与副作用实现，只约束“以流返回事件”这一形状。
import Foundation

/// AI 提供方统一返回的事件流类型：以 `AIStreamEvent` 为元素、以 `Error` 终止。
typealias AIProviderStream = AsyncThrowingStream<AIStreamEvent, Error>

/// 提供方协议：流自行完成 IO 与解码，只把事件交给主 actor，因此不绑定主 actor。
protocol AIProvider: Sendable {
    func stream(_ request: AIRequest) -> AIProviderStream
}
