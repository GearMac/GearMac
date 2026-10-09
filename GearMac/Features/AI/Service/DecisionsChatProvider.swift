// 文件职责：把聊天中的一轮消息转为 Decisions 判定请求，并把结构化答案作为回复文本流回。
// 分层：Service；遵循 AIProvider 协议，网络与解码在分离任务中进行，不占用主 actor。
import Foundation

/// 选中 Decisions 模型时的聊天传输：输入取最新一条用户消息，答案序列化为可读文本。
/// 判定是"一次请求、一份结构化答案"，因此这里只发一段文本加一条用量，不流式分片。
struct DecisionsChatProvider: AIProvider {
    let client: DecisionsClient
    let questions: DecisionsQuestionSet

    func stream(_ request: AIRequest) -> AIProviderStream {
        AIProviderStream { continuation in
            let task = Task.detached {
                do {
                    let input = request.messages.last { $0.role == .user }?.text ?? ""
                    let response = try await client.decide(input, questions: questions)
                    continuation.yield(
                        .text(
                            DecisionsResultText.serialize(
                                response.answers, usage: response.usage, language: .english)))
                    if let usage = response.usage {
                        continuation.yield(
                            .usage(
                                AIUsage(
                                    inputTokens: usage.inputTokens,
                                    outputTokens: usage.outputTokens)))
                    }
                    continuation.yield(.finished)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(
                        throwing: AIProviderError.responseFailed(Self.message(error)))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 判定错误以英文基线上报：聊天里所有提供方的错误形状一致，面板另有双语路径。
    private static func message(_ error: Error) -> String {
        if let questionError = error as? DecisionsQuestionError {
            return questionError.message(.english)
        }
        if let clientError = error as? DecisionsClient.ClientError {
            return clientError.message(.english)
        }
        return error.localizedDescription
    }
}
