// 文件职责：把以内联 <think>…</think> 标记思考的流式文本解码为思考与正文两类事件。
// 分层：Model；纯状态机，无 I/O，不得 import AppKit/SwiftUI。
import Foundation

/// 逐片解析流式文本的状态机：开头的 `<think>` 之前为正文，其中内容为思考，`</think>` 之后恢复正文；
/// 未出现该标签时整体视为正文。
struct AIThinkTagDecoder: Sendable {
    /// 解析阶段：尚未判定、正在输出思考、已进入正文。
    private enum Phase { case undecided, reasoning, answer }

    private var phase = Phase.undecided
    private var buffer = ""
    private var reasoningWhitespace = ""
    private var hasReasoning = false
    private var trimmingAnswer = false
    private let opening = "<think>"
    private let closing = "</think>"

    /// 送入一段流式片段，返回由此产生的事件；标签可能跨片段，因此未判定阶段会先缓存。
    mutating func feed(_ fragment: String) -> [AIStreamEvent] {
        if phase == .answer { return answer(fragment) }
        buffer += fragment
        if phase == .undecided {
            let candidate = buffer.drop(while: \.isWhitespace)
            if candidate.hasPrefix(opening) {
                buffer = String(candidate.dropFirst(opening.count))
                phase = .reasoning
            } else if opening.hasPrefix(candidate) {
                return []
            } else {
                phase = .answer
                let text = buffer
                buffer = ""
                return answer(text)
            }
        }
        if let close = buffer.range(of: closing) {
            let thought = String(buffer[..<close.lowerBound])
            let text = String(buffer[close.upperBound...])
            buffer = ""
            let events = reasoning(thought)
            reasoningWhitespace = ""
            phase = .answer
            trimmingAnswer = true
            return events + answer(text)
        }
        var tail = min(buffer.count, closing.count - 1)
        while tail > 0, !closing.hasPrefix(buffer.suffix(tail)) { tail -= 1 }
        let thought = String(buffer.dropLast(tail))
        buffer = String(buffer.suffix(tail))
        return reasoning(thought)
    }

    /// 流结束时冲刷剩余缓冲，返回尚未产出的事件。
    mutating func finish() -> [AIStreamEvent] {
        let pending = buffer
        buffer = ""
        let events: [AIStreamEvent]
        switch phase {
        case .undecided: events = pending.isEmpty ? [] : [.text(pending)]
        case .reasoning: events = reasoning(pending)
        case .answer: events = []
        }
        reasoningWhitespace = ""
        phase = .answer
        return events
    }

    /// 把思考文本转为事件，并抑制开头全为空白的内容。
    private mutating func reasoning(_ text: String) -> [AIStreamEvent] {
        guard !text.isEmpty else { return [] }
        if !hasReasoning {
            reasoningWhitespace += text
            guard !reasoningWhitespace.allSatisfy(\.isWhitespace) else { return [] }
            hasReasoning = true
            let thought = reasoningWhitespace
            reasoningWhitespace = ""
            return [.thinking, .reasoning(thought)]
        }
        return [.thinking, .reasoning(text)]
    }

    /// 把正文文本转为事件；刚结束思考时会丢弃开头的空白。
    private mutating func answer(_ text: String) -> [AIStreamEvent] {
        let text = trimmingAnswer ? String(text.drop(while: \.isWhitespace)) : text
        guard !text.isEmpty else { return [] }
        trimmingAnswer = false
        return [.text(text)]
    }
}
