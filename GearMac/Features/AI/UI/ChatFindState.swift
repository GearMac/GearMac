// 文件职责：维护聊天内“查找”的状态：查询串、当前匹配下标，以及按消息缓存的匹配结果。
// 分层：UI 状态（@MainActor @Observable）；不 import AppKit/SwiftUI，匹配计算委派给 ChatFindIndex。
import Foundation
import Observation

/// 在已打开聊天中的查找状态：工具栏输入框持有的查询，以及当前定位到第几个匹配。
@MainActor
@Observable
final class ChatFindState {
    var query = "" {
        didSet { if query != oldValue { current = 0 } }
    }
    private(set) var current = 0
    /// 按消息缓存，这样流式刷新时只搜索发生变化的那条回复。
    @ObservationIgnored private var cache: [UUID: Cached] = [:]

    private typealias Cached = (needle: String, message: ChatMessage, found: [ChatFindOccurrence])

    /// 去除首尾空白后的查询串；空串表示未在查找。
    var needle: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isSearching: Bool { !needle.isEmpty }

    /// 返回全部匹配，按阅读顺序逐词推进，而不是每条消息只停一次。
    func occurrences(in messages: [ChatMessage]) -> [ChatFindOccurrence] {
        let needle = needle
        guard !needle.isEmpty else {
            cache = [:]
            return []
        }
        var next: [UUID: Cached] = [:]
        let found = messages.flatMap { message -> [ChatFindOccurrence] in
            if let hit = cache[message.id], hit.needle == needle, hit.message == message {
                next[message.id] = hit
                return hit.found
            }
            let found = ChatFindIndex.occurrences(of: needle, in: [message])
            next[message.id] = (needle, message, found)
            return found
        }
        cache = next
        return found
    }

    /// 首尾循环，与 Mac 上其他地方“查找”的行为一致。
    func step(_ delta: Int, in messages: [ChatMessage]) {
        let count = occurrences(in: messages).count
        guard count > 0 else { return }
        current = ((current + delta) % count + count) % count
    }

    /// 按当前下标取出当前匹配；没有匹配时返回 nil。
    func currentOccurrence(in occurrences: [ChatFindOccurrence]) -> ChatFindOccurrence? {
        occurrences.isEmpty ? nil : occurrences[min(current, occurrences.count - 1)]
    }
}
