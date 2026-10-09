// 文件职责：实现基于 Apple Foundation Models 的本地提供方，把请求拆为 prompt 与 transcript 并以流式返回。
// 分层：Service；把本地模型的状态与生成错误统一映射为 `AIProviderError`。
import FoundationModels
import Foundation

/// 唯一无需任何配置的提供方，因此首次运行可以未经选择就直接使用它。
struct AppleIntelligenceProvider: AIProvider {
    /// 由调用方指定而非常量：默认过滤器会拒绕用户自己写过的文本。
    let guardrails: AppleIntelligenceGuardrails

    /// 以指定 guardrails 构造；默认使用系统默认过滤强度。
    init(guardrails: AppleIntelligenceGuardrails = .default) {
        self.guardrails = guardrails
    }

    /// 应用内 guardrail 枚举到 FoundationModels 的转换；仅在 macOS 26 运行时路径上调用，
    /// 入口已由 status() 单点过滤，不需要第二道运行时防线。
    @available(macOS 26.0, *)
    static func foundationModelsGuardrails(
        _ guardrails: AppleIntelligenceGuardrails
    ) -> SystemLanguageModel.Guardrails {
        switch guardrails {
        case .default: .default
        case .permissiveContentTransformations: .permissiveContentTransformations
        }
    }

    /// 读取本地模型的可用性，并映射为应用内的状态枚举。
    /// 本函数是端侧路由唯一的系统判断点：模型选择器、默认模型回落、工厂与设置页
    /// 全部经由它的返回值驱动，不各自维护可用性分支。
    static func status() -> AppleIntelligenceStatus {
        guard #available(macOS 26.0, *) else { return .requiresNewerSystem }
        switch SystemLanguageModel.default.availability {
        case .available: return .available
        case .unavailable(.deviceNotEligible): return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): return .notEnabled
        case .unavailable(.modelNotReady): return .modelNotReady
        @unknown default: return .modelNotReady
        }
    }

    /// 以流的形式完成一轮本地生成：先校验状态，再建立会话并逐帧推送增量文本。
    /// 入口守卫是编译器强制要求（实现体引用 26-only 类型），与 status() 同属端侧路由的
    /// 系统判断；正常路径下旧系统用户已被选择器过滤，不会到达这里。
    func stream(_ request: AIRequest) -> AIProviderStream {
        AIProviderStream { continuation in
            guard #available(macOS 26.0, *) else {
                continuation.finish(
                    throwing: AIProviderError.unavailable("On-device chat needs macOS 26."))
                return
            }
            Self.deliver(request, guardrails: guardrails, into: continuation)
        }
    }

    /// `stream` 的 macOS 26 实现体。
    @available(macOS 26.0, *)
    private static func deliver(
        _ request: AIRequest, guardrails: AppleIntelligenceGuardrails,
        into continuation: AIProviderStream.Continuation
    ) {
        // 会话与流在此处创建：`ResponseStream` 是 `sending` 的，不可跨隔离域传递。
        let task = Task.detached {
            do {
                if let message = status().message {
                    throw AIProviderError.unavailable(message)
                }
                let turn = Self.turn(for: request)
                guard let prompt = turn.prompt else {
                    throw AIProviderError.responseFailed("There was nothing to send.")
                }
                let session = LanguageModelSession(
                    model: SystemLanguageModel(
                        guardrails: foundationModelsGuardrails(guardrails)),
                    transcript: turn.transcript)
                let options = GenerationOptions(
                    maximumResponseTokens: min(
                        request.maxOutputTokens, AppleIntelligence.maxOutputTokens))
                var delta = AppleIntelligenceDelta()
                for try await snapshot in session.streamResponse(to: prompt, options: options) {
                    try Task.checkCancellation()
                    let text = delta.delta(from: snapshot.content)
                    if !text.isEmpty { continuation.yield(.text(text)) }
                }
                continuation.yield(.finished)
                continuation.finish()
            } catch is CancellationError {
                continuation.finish()
            } catch let error as LanguageModelSession.GenerationError {
                continuation.finish(throwing: providerError(error))
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }

    /// 按会话接受的形式拆分：最新的用户轮作为 prompt，其余作为 transcript。
    @available(macOS 26.0, *)
    static func turn(for request: AIRequest) -> (prompt: String?, transcript: Transcript) {
        var entries: [Transcript.Entry] = []
        if let instructions = request.instructions, !instructions.isEmpty {
            entries.append(
                .instructions(
                    Transcript.Instructions(
                        segments: [.text(Transcript.TextSegment(content: instructions))],
                        toolDefinitions: [])))
        }
        let promptIndex = request.messages.lastIndex { $0.role == .user }
        for message in request.messages[..<(promptIndex ?? request.messages.endIndex)]
        where !message.text.isEmpty {
            let segment = Transcript.Segment.text(Transcript.TextSegment(content: message.text))
            switch message.role {
            case .user:
                entries.append(.prompt(Transcript.Prompt(segments: [segment])))
            case .assistant:
                entries.append(.response(Transcript.Response(assetIDs: [], segments: [segment])))
            // 本地路由不提供工具，因此工具轮只可能是外来的历史记录。
            case .system, .tool:
                continue
            }
        }
        let prompt = promptIndex.map {
            request.messages[$0].text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (prompt?.isEmpty == true ? nil : prompt, Transcript(entries: entries))
    }

    /// 使用平实的句子：这些错误携带的唯一细节是为日志而写的 `debugDescription`。
    @available(macOS 26.0, *)
    static func providerError(_ error: LanguageModelSession.GenerationError) -> AIProviderError {
        switch error {
        case .exceededContextWindowSize:
            return .responseFailed(
                "This conversation is longer than the on-device model can hold. Start a new chat.")
        case .guardrailViolation, .refusal:
            return .responseFailed("Apple Intelligence declined to answer that.")
        case .unsupportedLanguageOrLocale:
            return .responseFailed("Apple Intelligence does not support this language yet.")
        case .assetsUnavailable:
            return .unavailable("Apple Intelligence is still downloading its model.")
        case .rateLimited:
            return .responseFailed("Apple Intelligence is busy. Try again shortly.")
        case .concurrentRequests:
            return .responseFailed("Apple Intelligence is already answering. Try again shortly.")
        case .decodingFailure, .unsupportedGuide:
            return .malformedResponse
        @unknown default:
            return .responseFailed("Apple Intelligence could not complete the response.")
        }
    }
}
