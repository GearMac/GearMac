// 文件职责：对话消息模型：消息状态、附件，以及搜索/工具/思考记录，并负责把回复切分为文本与过程片段。
// 分层：Model；纯数据与派生计算，不得 import AppKit/SwiftUI。
import Foundation

/// 转写中的一条消息。
struct ChatMessage: Identifiable, Equatable, Sendable {
    /// 消息角色：用户或助手。
    enum Role: String, Equatable, Sendable {
        case user
        case assistant
    }

    /// 消息的生成状态。
    enum State: String, Equatable, Sendable {
        case streaming
        case complete
        case failed
    }

    let id: UUID
    let role: Role
    var text: String
    var state: State
    let sentAt: Date
    let images: [AIImage]
    /// 随消息发送的 PDF；文本文件不属于此类，其内容以文本形式送达模型。
    let documents: [AIDocument]
    /// 回复依次发起的联网搜索；每条都标记在文本中发生的位置。
    var searches: [ChatSearch]
    /// 回复调用的工具，同样按位置标记；调用本身不会进入上下文。
    var toolUses: [ChatToolUse]
    /// 模型共享的思考内容，每一段为一块，并标记其发生位置。
    var reasoning: [ChatReasoning]
    /// 路由为本次回复上报的用量；上下文卡片读取最新的一条。
    var usage: AIUsage?
    /// 通过 `@server` 指定本次提问所指向的服务器；存储的文本已去掉该标记。
    let toolScope: String?

    /// 构造消息；默认状态为已完成，其余可选字段为空。
    init(
        id: UUID = UUID(), role: Role, text: String, state: State = .complete,
        sentAt: Date = Date(), images: [AIImage] = [], documents: [AIDocument] = [],
        searches: [ChatSearch] = [],
        toolUses: [ChatToolUse] = [], reasoning: [ChatReasoning] = [], usage: AIUsage? = nil,
        toolScope: String? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.state = state
        self.sentAt = sentAt
        self.images = images
        self.documents = documents
        self.searches = searches
        self.toolUses = toolUses
        self.reasoning = reasoning
        self.usage = usage
        self.toolScope = toolScope
    }

    /// 流式回复进行中，文本只会追加到 `count` 个片段中的最后一个。
    func isArriving(segmentAt offset: Int, of count: Int) -> Bool {
        state == .streaming && offset == count - 1
    }

    /// 下一次搜索或调用的序号；若其间没有文本，则 textOffset 相同。
    var nextSequence: Int { searches.count + toolUses.count }

    /// 把所有思考块拼接起来，供查找与整段复制使用。
    var reasoningText: String {
        reasoning.map(\.text).joined(separator: "\n\n")
    }

    /// 把回复按其中发生的过程切开：思考、搜索或工具、正文……各按发生位置排列。
    var segments: [ChatSegment] {
        // 同一偏移处思考排在前面：模型先思考，再搜索或调用工具。
        let interruptions =
            (reasoning.map {
                (offset: $0.textOffset, sequence: -1, segment: ChatSegment.reasoning($0))
            }
            + searches.map {
                (offset: $0.textOffset, sequence: $0.sequence, segment: ChatSegment.search($0))
            }
            + toolUses.map {
                (offset: $0.textOffset, sequence: $0.sequence, segment: ChatSegment.tools([$0]))
            })
            .sorted { ($0.offset, $0.sequence) < ($1.offset, $1.sequence) }
        var segments: [ChatSegment] = []
        var rest = Substring(text)
        var consumed = 0
        for interruption in interruptions {
            let take = max(0, min(interruption.offset - consumed, rest.count))
            if take > 0 { segments.append(.text(String(rest.prefix(take)))) }
            if case .tools(let uses) = interruption.segment,
                case .tools(let previous) = segments.last
            {
                segments[segments.count - 1] = .tools(previous + uses)
            } else {
                segments.append(interruption.segment)
            }
            rest = rest.dropFirst(take)
            consumed += take
        }
        if !rest.isEmpty { segments.append(.text(String(rest))) }
        return segments
    }
}

/// 回复中的一次联网搜索。
struct ChatSearch: Equatable, Hashable, Sendable {
    var query: String?
    var isComplete: Bool
    /// 搜索开始时已到达的回复文本字符数。
    let textOffset: Int
    let sequence: Int
}

/// 回复中的一次工具调用：运行期间是实时状态，结束后成为执行记录。
struct ChatToolUse: Equatable, Hashable, Sendable {
    /// 调用的状态。
    enum State: String, Equatable, Hashable, Sendable {
        case running
        case completed
        case failed
    }

    let callID: String
    let origin: String
    let title: String
    var state: State
    /// 调用开始时已到达的回复文本字符数。
    let textOffset: Int
    let sequence: Int

    /// 调用在记录行中的文案，含运行中/已调用的动词。
    var label: String {
        let verb = state == .running ? "Calling" : "Called"
        return origin.isEmpty ? "\(verb) \(title)" : "\(verb) \(origin) · \(title)"
    }
}

/// 工具调用记录集合的派生状态与汇总文案。
extension Array where Element == ChatToolUse {
    /// 当前仍在运行的调用（若有）。
    var runningCall: ChatToolUse? { last { $0.state == .running } }
    /// 是否仍有调用在运行。
    var isLive: Bool { runningCall != nil }
    /// 失败的调用数量。
    var failedCount: Int { count { $0.state == .failed } }

    /// 全部调用结束后的汇总文案，带失败数量。
    var completedLabel: String {
        let label = "Called \(count) tools"
        let failures = failedCount
        return failures == 0 ? label : "\(label) · \(failures) failed"
    }
}

/// 一段思考：一条回复可以先思考、再作答，然后继续思考。
struct ChatReasoning: Equatable, Hashable, Sendable {
    var text: String
    /// 本段思考开始时已到达的回复文本字符数。
    let textOffset: Int
    /// 持续到正文恢复或回复结束为止；仍在思考时为 nil。
    var duration: TimeInterval?
}

/// 回复切分后的片段类型。
enum ChatSegment: Equatable, Hashable {
    case text(String)
    case search(ChatSearch)
    case tools([ChatToolUse])
    case reasoning(ChatReasoning)
}
