// 文件职责：解析 provider 的 SSE 流：切分事件帧，并把 OpenAI 兼容与 Anthropic 两种形态的载荷解码为统一的流式事件。
// 分层：Model；纯解析状态机，不做网络 I/O，不得 import AppKit/SwiftUI。
import Foundation

/// SSE 帧切分器：按空行边界切出事件帧，并提取其中的 data 行。
struct SSEParser: Sendable {
    private var buffer = Data()

    /// 送入原始字节，返回本次能完整解析出的 data 载荷。
    mutating func feed(_ data: Data) -> [String] {
        buffer.append(data)
        var payloads: [String] = []
        while let boundary = nextBoundary() {
            let frame = buffer[..<boundary.lowerBound]
            buffer.removeSubrange(buffer.startIndex..<boundary.upperBound)
            if let payload = Self.payload(in: frame) { payloads.append(payload) }
        }
        return payloads
    }

    /// 流结束时取出剩余缓冲中的载荷。
    mutating func finish() -> [String] {
        guard !buffer.isEmpty else { return [] }
        defer { buffer.removeAll() }
        return Self.payload(in: buffer).map { [$0] } ?? []
    }

    /// 找到最早的帧边界（LF LF 或 CRLF CRLF）。
    private func nextBoundary() -> Range<Data.Index>? {
        let lf = buffer.range(of: Data([0x0A, 0x0A]))
        let crlf = buffer.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A]))
        switch (lf, crlf) {
        case (let lhs?, let rhs?): return lhs.lowerBound < rhs.lowerBound ? lhs : rhs
        case (let range?, nil), (nil, let range?): return range
        case (nil, nil): return nil
        }
    }

    /// 从一帧中按 SSE 规则拼接 data 行（忽略注释行与其它字段）；没有 data 行则返回 nil。
    private static func payload(in frame: some DataProtocol) -> String? {
        let text = String(decoding: frame, as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n")
        var dataLines: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(":") { continue }
            if line == "data" {
                dataLines.append("")
            } else if line.hasPrefix("data:") {
                var value = line.dropFirst(5)
                if value.first == " " { value = value.dropFirst() }
                dataLines.append(String(value))
            }
        }
        return dataLines.isEmpty ? nil : dataLines.joined(separator: "\n")
    }
}

/// 把两种 API 形态的流式载荷解码为 AIStreamEvent 序列。
struct AIStreamDecoder: Sendable {
    /// 一次调用的分片累积状态。
    /// 调用以 index 为键分片到达，id 与 name 只在第一片出现。
    private struct PartialToolCall {
        var id = ""
        var name = ""
        var arguments = ""
        var thoughtSignature: String?
    }

    private let shape: AIHTTPConfiguration.APIShape
    private var parser = SSEParser()
    private var thinkTags = AIThinkTagDecoder()
    private var usage = AIUsage()
    private var partialToolCalls: [Int: PartialToolCall] = [:]
    private(set) var isTerminal = false

    init(shape: AIHTTPConfiguration.APIShape) {
        self.shape = shape
    }

    /// 按 index 顺序组装，使本轮的调用以模型列出的顺序交给工具循环。
    private mutating func flushToolCalls() -> [AIStreamEvent] {
        guard !partialToolCalls.isEmpty else { return [] }
        let calls = partialToolCalls.sorted { $0.key < $1.key }.map(\.value)
        partialToolCalls.removeAll()
        return calls.compactMap { call in
            guard !call.name.isEmpty else { return nil }
            return .toolCallRequested(
                AIToolCall(
                    id: call.id, name: call.name, arguments: call.arguments,
                    thoughtSignature: call.thoughtSignature))
        }
    }

    /// 送入一段原始流字节，返回解析出的事件。
    mutating func feed(_ data: Data) throws -> [AIStreamEvent] {
        try decode(parser.feed(data))
    }

    /// 流结束：冲刷残留缓冲，并在 OpenAI 兼容形态下结算 think 标签解码器。
    mutating func finish() throws -> [AIStreamEvent] {
        var events = try decode(parser.finish())
        if shape == .openAICompatible, !isTerminal { events += thinkTags.finish() }
        return events
    }

    /// 逐条解码载荷；遇到 `[DONE]` 或已终止后不再处理后续载荷。
    private mutating func decode(_ payloads: [String]) throws -> [AIStreamEvent] {
        var events: [AIStreamEvent] = []
        for payload in payloads where !isTerminal {
            if payload == "[DONE]" {
                isTerminal = true
                if shape == .openAICompatible { events += thinkTags.finish() }
                events.append(contentsOf: flushToolCalls())
                events.append(.finished)
                continue
            }
            switch shape {
            case .openAICompatible:
                events.append(contentsOf: try decodeOpenAI(payload))
            case .anthropic:
                events.append(contentsOf: try decodeAnthropic(payload))
            }
        }
        return events
    }

    /// 解码一条 OpenAI 兼容形态的载荷；解析失败或携带 error 时终止并抛错。
    private mutating func decodeOpenAI(_ payload: String) throws -> [AIStreamEvent] {
        guard let data = payload.data(using: .utf8),
            let chunk = try? JSONDecoder().decode(OpenAIChunk.self, from: data)
        else {
            isTerminal = true
            throw AIProviderError.malformedResponse
        }

        // OpenRouter 把流中途的失败放在 200 响应体里上报，因此它是事件而不是 HTTP 状态。
        if let message = chunk.error?.message {
            isTerminal = true
            throw AIProviderError.responseFailed(message)
        }
        var events: [AIStreamEvent] = []
        if let choice = chunk.choices?.first {
            if let content = choice.delta?.content, !content.isEmpty {
                events += thinkTags.feed(content)
            } else if let reasoning = choice.delta?.reasoningText {
                events += [.thinking, .reasoning(reasoning)]
            }
            for fragment in choice.delta?.toolCalls ?? [] { absorb(fragment) }
            if choice.finishReason == "tool_calls" { events.append(contentsOf: flushToolCalls()) }
        }
        if let reported = chunk.usage {
            usage.inputTokens = reported.promptTokens ?? usage.inputTokens
            usage.outputTokens = reported.completionTokens ?? usage.outputTokens
            usage.reasoningTokens =
                reported.completionTokensDetails?.reasoningTokens ?? usage.reasoningTokens
            usage.costUSD = reported.cost ?? usage.costUSD
            events.append(.usage(usage))
        }
        return events
    }

    /// 分片的 index 是唯一稳定的标识；网关在只有一次调用时可能省略它。
    private mutating func absorb(_ fragment: OpenAIChunk.Choice.Delta.ToolCall) {
        var partial = partialToolCalls[fragment.index ?? 0] ?? PartialToolCall()
        if let id = fragment.id, !id.isEmpty { partial.id = id }
        if let name = fragment.function?.name, !name.isEmpty { partial.name = name }
        partial.arguments += fragment.function?.arguments ?? ""
        if let signature = fragment.extraContent?.google?.thoughtSignature {
            partial.thoughtSignature = signature
        }
        partialToolCalls[fragment.index ?? 0] = partial
    }

    /// 解码一条 Anthropic 形态的载荷，按事件类型转换为对应事件。
    private mutating func decodeAnthropic(_ payload: String) throws -> [AIStreamEvent] {
        guard let data = payload.data(using: .utf8),
            let event = try? JSONDecoder().decode(AnthropicEvent.self, from: data)
        else {
            isTerminal = true
            throw AIProviderError.malformedResponse
        }

        switch event.type {
        case "content_block_start":
            guard event.contentBlock?.type == "tool_use" else { return [] }
            partialToolCalls[event.index ?? 0] = PartialToolCall(
                id: event.contentBlock?.id ?? "", name: event.contentBlock?.name ?? "",
                arguments: "")
            return []
        case "content_block_delta":
            if event.delta?.type == "text_delta", let text = event.delta?.text, !text.isEmpty {
                return [.text(text)]
            }
            if event.delta?.type == "input_json_delta" {
                partialToolCalls[event.index ?? 0]?.arguments += event.delta?.partialJSON ?? ""
                return []
            }
            guard event.delta?.type == "thinking_delta" else { return [] }
            guard let thinking = event.delta?.thinking, !thinking.isEmpty else { return [.thinking] }
            return [.thinking, .reasoning(thinking)]
        case "message_start":
            let reported = event.message?.usage
            usage.inputTokens = reported?.inputTokens ?? usage.inputTokens
            let cached = [reported?.cacheReadInputTokens, reported?.cacheCreationInputTokens]
                .compactMap { $0 }
            if !cached.isEmpty { usage.cachedInputTokens = cached.reduce(0, +) }
            return [.usage(usage)]
        case "message_delta":
            usage.outputTokens = event.usage?.outputTokens ?? usage.outputTokens
            // 到这里调用已完整，而工具轮次可能永远不会收到 `message_stop`。
            guard event.delta?.stopReason == "tool_use" else { return [.usage(usage)] }
            return [.usage(usage)] + flushToolCalls()
        case "message_stop":
            isTerminal = true
            return flushToolCalls() + [.finished]
        case "error":
            isTerminal = true
            throw AIProviderError.responseFailed(Self.anthropicErrorMessage(event.error?.type))
        default:
            return []
        }
    }

    /// 把 Anthropic 的错误类型映射为可直接展示的错误文案。
    private static func anthropicErrorMessage(_ type: String?) -> String {
        switch type {
        case "authentication_error": return "API key rejected — check it in Settings."
        case "rate_limit_error": return "Rate limit reached — try again later."
        default: return "The provider stopped the response with an error."
        }
    }
}

/// OpenAI 兼容形态的流式响应分片。
private struct OpenAIChunk: Decodable {
    /// 一条候选回复。
    struct Choice: Decodable {
        /// 增量内容。
        struct Delta: Decodable {
            /// 结构化的推理明细。
            struct ReasoningDetail: Decodable { let text: String? }

            /// 工具调用的分片。
            struct ToolCall: Decodable {
                /// 工具调用的名称与参数分片。
                struct Function: Decodable {
                    let name: String?
                    let arguments: String?
                }

                /// provider 额外的扩展内容。
                struct ExtraContent: Decodable {
                    /// Gemini 相关的扩展字段。
                    struct Google: Decodable {
                        let thoughtSignature: String?

                        enum CodingKeys: String, CodingKey {
                            case thoughtSignature = "thought_signature"
                        }
                    }

                    let google: Google?
                }

                let index: Int?
                let id: String?
                let function: Function?
                let extraContent: ExtraContent?

                enum CodingKeys: String, CodingKey {
                    case index, id, function
                    case extraContent = "extra_content"
                }
            }

            let content: String?
            let reasoning: String?
            let reasoningContent: String?
            let reasoningDetails: [ReasoningDetail]?
            let toolCalls: [ToolCall]?

            /// OpenRouter 用 `reasoning`，DeepSeek 及其衍生则用 `reasoning_content`。
            var reasoningText: String? {
                let text =
                    [reasoning, reasoningContent].compactMap { $0 }.first { !$0.isEmpty }
                    ?? reasoningDetails?.compactMap(\.text).joined()
                return text?.isEmpty == false ? text : nil
            }

            enum CodingKeys: String, CodingKey {
                case content, reasoning
                case reasoningContent = "reasoning_content"
                case reasoningDetails = "reasoning_details"
                case toolCalls = "tool_calls"
            }
        }

        let delta: Delta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    /// 用量统计。
    struct Usage: Decodable {
        /// 输出 token 的细分统计。
        struct CompletionDetails: Decodable {
            let reasoningTokens: Int?

            enum CodingKeys: String, CodingKey {
                case reasoningTokens = "reasoning_tokens"
            }
        }

        let promptTokens: Int?
        let completionTokens: Int?
        let completionTokensDetails: CompletionDetails?
        /// OpenRouter 自己的费用数值；厂商 API 不会发送该字段。
        let cost: Double?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case completionTokensDetails = "completion_tokens_details"
            case cost
        }
    }

    /// 流中途上报的错误体。
    struct ErrorBody: Decodable { let message: String? }

    let choices: [Choice]?
    let usage: Usage?
    let error: ErrorBody?
}

/// Anthropic Messages 的流式事件。
private struct AnthropicEvent: Decodable {
    /// 事件增量。
    struct Delta: Decodable {
        let type: String?
        let text: String?
        let thinking: String?
        let partialJSON: String?
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case type, text, thinking
            case partialJSON = "partial_json"
            case stopReason = "stop_reason"
        }
    }

    /// 内容块起始信息。
    struct ContentBlock: Decodable {
        let type: String?
        let id: String?
        let name: String?
    }

    /// Anthropic 的用量统计。
    struct Usage: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheReadInputTokens: Int?
        let cacheCreationInputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
        }
    }

    /// `message_start` 事件中的消息体。
    struct Message: Decodable { let usage: Usage? }
    /// 错误事件体。
    struct ErrorBody: Decodable { let type: String? }

    let type: String
    let index: Int?
    let delta: Delta?
    let contentBlock: ContentBlock?
    let usage: Usage?
    let message: Message?
    let error: ErrorBody?

    enum CodingKeys: String, CodingKey {
        case type, index, delta, usage, message, error
        case contentBlock = "content_block"
    }
}
