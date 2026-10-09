// 文件职责：把基础提供方包装成可循环调用工具的提供方，直到模型停止请求工具或触达轮数/字节上限。
// 分层：Service；仅转发流事件，负责轮数、单次结果与整轮历史三档上限控制。
import Foundation

/// 可调用工具的路由：反复重流式输出当前轮，直到模型不再请求工具或触达上限。
struct AIToolLoopProvider: AIProvider {
    private let base: any AIProvider
    private let tools: [AITool]
    private let invoke: @Sendable (AIToolCall) async -> AIToolResult

    /// 模型若持续调用工具就说明它已停止回答；这就是该轮宣告失败的轮数上限。
    private let maxRounds: Int?
    /// 单次工具结果的最大字节数。
    static let maxResultBytes = 32_768
    /// 工具结果会绕过 `boundedContext`，因此该轮自行为结果总量设定上限。
    static let maxTurnResultBytes = 131_072
    /// 每一轮都会重发整轮历史，因此没有轮数上限时，历史增长必须有个尽头。
    static let maxTurnHistoryBytes = 1_048_576

    init(
        base: any AIProvider, tools: [AITool], maxRounds: Int?,
        invoke: @escaping @Sendable (AIToolCall) async -> AIToolResult
    ) {
        self.base = base
        self.tools = tools
        self.maxRounds = maxRounds
        self.invoke = invoke
    }

    func stream(_ request: AIRequest) -> AIProviderStream {
        AIProviderStream { continuation in
            let task = Task.detached {
                do {
                    try await run(request, into: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        _ request: AIRequest, into continuation: AIProviderStream.Continuation
    ) async throws {
        var messages = request.messages
        var spent = 0
        var carried = 0
        var rounds = 0
        while maxRounds.map({ rounds < $0 }) ?? (carried < Self.maxTurnHistoryBytes) {
            rounds += 1
            let round = try await streamRound(
                request.continuing(with: messages, tools: tools), into: continuation)
            guard !round.calls.isEmpty else {
                continuation.yield(.finished)
                return
            }
            messages.append(
                AIMessage(role: .assistant, text: round.text, toolCalls: round.calls))
            carried += round.text.utf8.count + round.calls.reduce(0) { $0 + $1.arguments.utf8.count }
            for call in round.calls {
                try Task.checkCancellation()
                let tool = tools.first { $0.name == call.name }
                continuation.yield(
                    .toolCall(
                        id: call.id, origin: tool?.origin ?? "", title: tool?.title ?? call.name))
                let result = await bounded(invoke(call), spent: &spent)
                continuation.yield(.toolResult(id: call.id, isError: result.isError))
                carried += result.content.utf8.count
                messages.append(AIMessage(role: .tool, text: "", toolResult: result))
            }
        }
        throw AIProviderError.responseFailed("Stopped after \(rounds) rounds of tool calls.")
    }

    /// 一次性订阅基础路由的输出：文本直接进入对话，工具调用被收集起来。
    private func streamRound(
        _ request: AIRequest, into continuation: AIProviderStream.Continuation
    ) async throws -> (text: String, calls: [AIToolCall]) {
        var text = ""
        var calls: [AIToolCall] = []
        for try await event in base.stream(request) {
            try Task.checkCancellation()
            switch event {
            case .text(let delta):
                text += delta
                continuation.yield(event)
            case .toolCallRequested(let call):
                calls.append(call)
            // `.finished` 由本循环负责发送，因为模型已停止请求工具。
            case .finished:
                break
            default:
                continuation.yield(event)
            }
        }
        return (text, calls)
    }

    private func bounded(_ result: AIToolResult, spent: inout Int) -> AIToolResult {
        guard spent < Self.maxTurnResultBytes else {
            return .failure(result.callID, "This turn's tool output budget is used up.")
        }
        let allowance = min(Self.maxResultBytes, Self.maxTurnResultBytes - spent)
        let utf8 = result.content.utf8
        spent += min(utf8.count, allowance)
        guard utf8.count > allowance else { return result }
        // 截断可能落在半个字符上；`String(decoding:)` 会把残余部分变为替换字符。
        let content = String(decoding: Array(utf8.prefix(allowance)), as: UTF8.self)
        return AIToolResult(
            callID: result.callID, content: content + "\n…truncated.", isError: result.isError)
    }
}
