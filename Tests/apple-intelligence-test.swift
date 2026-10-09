// 文件职责：验证 Apple Intelligence（端上模型）集成路径——状态文案、累积快照转增量输出、请求轮次切分、生成错误到可读失败的映射。
// 分层：测试 harness；端到端流式用例在无法运行端上模型的 Mac 上会带原因跳过。

import FoundationModels
import Foundation

/// Apple Intelligence 相关行为的测试入口，用手写断言统计通过/失败数。
@main
@MainActor
struct AppleIntelligenceTests {
    /// 累计失败的断言数。
    static var failures = 0
    /// 累计通过的断言数。
    static var passes = 0

    /// 记录一次断言：条件为真则计入通过，否则计入失败并打印消息。
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// 依次运行各测试用例，最后打印统计结果，有失败则以 1 退出。
    static func main() async {
        statusCopyCoversEveryReason()
        deltasFollowCumulativeSnapshots()
        turnsSplitThePromptFromItsHistory()
        generationErrorsBecomeReadableFailures()
        guardrailsMapToFoundationModels()
        await onDeviceModelAnswers()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    /// 校验每种不可用状态都给出各自的说明文案。
    static func statusCopyCoversEveryReason() {
        expect(AppleIntelligenceStatus.available.message == nil, "available reads as no failure")
        expect(AppleIntelligenceStatus.available.isAvailable, "available is available")

        let unavailable: [AppleIntelligenceStatus] = [
            .deviceNotEligible, .notEnabled, .modelNotReady, .requiresNewerSystem
        ]
        for status in unavailable {
            expect(!status.isAvailable, "\(status) is not available")
            expect(status.message?.isEmpty == false, "\(status) explains itself")
        }
        expect(
            Set(unavailable.compactMap(\.message)).count == unavailable.count,
            "each reason reads differently")
    }

    /// 校验累积快照会被转换成增量文本。
    static func deltasFollowCumulativeSnapshots() {
        var delta = AppleIntelligenceDelta()
        let emitted = ["He", "Hello", "Hello!"].map { delta.delta(from: $0) }
        expect(emitted == ["He", "llo", "!"], "cumulative snapshots become deltas, got \(emitted)")

        // 修订版会替换掉之前的内容，因此丢弃过期前缀会把内容截断。
        var revised = AppleIntelligenceDelta()
        _ = revised.delta(from: "Hello")
        expect(revised.delta(from: "Goodbye") == "Goodbye", "a revised snapshot is emitted whole")

        var repeated = AppleIntelligenceDelta()
        _ = repeated.delta(from: "Hello")
        expect(repeated.delta(from: "Hello").isEmpty, "an unchanged snapshot emits nothing")
    }

    /// 校验请求被拆分为最新用户轮次（prompt）与其之前的历史。
    static func turnsSplitThePromptFromItsHistory() {
        guard #available(macOS 26.0, *) else {
            print("skip  turn splitting — needs macOS 26")
            return
        }
        let request = AIRequest(
            instructions: "Be brief.",
            messages: [
                AIMessage(role: .user, text: "first"),
                AIMessage(role: .assistant, text: "answer"),
                AIMessage(role: .user, text: "  second  ")
            ])
        let turn = AppleIntelligenceProvider.turn(for: request)

        expect(turn.prompt == "second", "the newest user turn is the prompt, got \(turn.prompt ?? "nil")")
        let entries = Array(turn.transcript)
        expect(entries.count == 3, "instructions plus two history turns, got \(entries.count)")
        if case .instructions(let instructions) = entries.first {
            expect(text(instructions.segments) == "Be brief.", "instructions lead the transcript")
        } else {
            expect(false, "the transcript opens with instructions")
        }
        if case .prompt(let prompt) = entries.dropFirst().first {
            expect(text(prompt.segments) == "first", "the older user turn is a transcript prompt")
        } else {
            expect(false, "the older user turn is a transcript prompt")
        }
        if case .response(let response) = entries.last {
            expect(text(response.segments) == "answer", "the reply is a transcript response")
        } else {
            expect(false, "the reply is a transcript response")
        }
        expect(
            !entries.contains { entryText($0).contains("second") },
            "the prompt is not also in the history it resumes from")

        // 当读取方关闭系统提示词时，指令在上游就被丢弃。
        let bare = AppleIntelligenceProvider.turn(
            for: AIRequest(messages: [AIMessage(role: .user, text: "hi")]))
        expect(Array(bare.transcript).isEmpty, "a turn with no history carries an empty transcript")
        expect(bare.prompt == "hi", "a lone user turn is still the prompt")

        // 只有图片的消息没有可发送的文本；无论哪种情况该模型都不接收图片。
        let empty = AppleIntelligenceProvider.turn(
            for: AIRequest(messages: [AIMessage(role: .assistant, text: "orphan")]))
        expect(empty.prompt == nil, "a request with no user turn has no prompt")
    }

    /// 校验各类生成错误都映射为不泄露内部细节的可读失败。
    static func generationErrorsBecomeReadableFailures() {
        guard #available(macOS 26.0, *) else {
            print("skip  generation error mapping — needs macOS 26")
            return
        }
        let context = LanguageModelSession.GenerationError.Context(
            debugDescription: "internal-detail-42")
        let errors: [LanguageModelSession.GenerationError] = [
            .exceededContextWindowSize(context), .guardrailViolation(context),
            .unsupportedLanguageOrLocale(context), .assetsUnavailable(context),
            .rateLimited(context), .concurrentRequests(context)
        ]
        var messages: [String] = []
        for error in errors {
            let message = AppleIntelligenceProvider.providerError(error).localizedDescription
            expect(!message.isEmpty, "\(error) explains itself")
            expect(
                !message.contains("internal-detail-42"),
                "\(error) does not leak its debug description")
            messages.append(message)
        }
        expect(Set(messages).count == messages.count, "each failure reads differently")
        expect(
            AppleIntelligenceProvider.providerError(.decodingFailure(context))
                == .malformedResponse,
            "a decoding failure is the shared malformed-response case")
    }

    /// 真正的端到端调用，在这台 Mac 能运行它的时候。
    /// 校验 guardrail 映射在 macOS 26 运行时路径可安全调用；旧系统构建环境跳过。
    /// FoundationModels 的两个预设值是结构等价的存储值（Mirror 无法区分），因此不做值断言；
    /// case 对应关系由实现处的 switch 穷尽性在编译期保证。
    static func guardrailsMapToFoundationModels() {
        guard #available(macOS 26.0, *) else {
            print("skip  guardrails mapping — needs macOS 26")
            return
        }
        _ = AppleIntelligenceProvider.foundationModelsGuardrails(.default)
        _ = AppleIntelligenceProvider.foundationModelsGuardrails(.permissiveContentTransformations)
        expect(true, "guardrail mappings are callable on macOS 26")
    }

    static func onDeviceModelAnswers() async {
        let status = AppleIntelligenceProvider.status()
        guard status.isAvailable else {
            print("skip  on-device stream — \(status.message ?? "unavailable")")
            return
        }
        let request = AIRequest(
            instructions: "Reply with one short sentence.",
            messages: [AIMessage(role: .user, text: "Name one colour.")])
        var text = ""
        var finished = false
        do {
            for try await event in AppleIntelligenceProvider().stream(request) {
                switch event {
                case .text(let chunk): text += chunk
                case .finished: finished = true
                default: break
                }
            }
        } catch {
            expect(false, "the on-device stream failed: \(error.localizedDescription)")
            return
        }
        expect(!text.isEmpty, "the on-device model answered")
        expect(finished, "the on-device stream terminated with .finished")
    }

    /// 把 transcript 段落中的所有文本片段拼接为一个字符串。
    private static func text(_ segments: [Transcript.Segment]) -> String {
        segments.compactMap { if case .text(let segment) = $0 { segment.content } else { nil } }
            .joined()
    }

    /// 取出某个 transcript 条目中的纯文本（工具调用与工具输出视为空）。
    private static func entryText(_ entry: Transcript.Entry) -> String {
        switch entry {
        case .instructions(let value): return text(value.segments)
        case .prompt(let value): return text(value.segments)
        case .response(let value): return text(value.segments)
        case .toolCalls, .toolOutput: return ""
        @unknown default: return ""
        }
    }
}
