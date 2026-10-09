// 文件职责：为聊天消息渲染中的「查找」命中词提供高亮，并给出当前命中项的滚动锚点与环境值。
// 分层：UI；只计算展示态样式，不持有查找状态本身。
import SwiftUI

/// 查找功能在单条消息中要找的内容；向下传递，使该消息绘制的每段文本都能标记命中词。
struct ChatTextHighlight: Equatable {
    let query: String
    /// 当前定位到的命中项（若在本消息内）；只有它会使用实心高亮。
    let current: ChatFindOccurrence?

    /// 承载当前命中项的那段文本所带的 id，供会话记录滚动定位到它。
    static let currentAnchor = "chat-find-current"

    func isCurrent(_ leaf: [Int]) -> Bool { current?.leaf == leaf }

    /// 返回按给定叶子路径标记命中项后的 `AttributedString`。
    func attributed(_ string: String, leaf: [Int]) -> AttributedString {
        var text = AttributedString(string)
        apply(to: &text, leaf: leaf)
        return text
    }

    /// 就地标记每一处命中，从而保留 Markdown 自身的 run（如代码、强调）。
    func apply(to text: inout AttributedString, leaf: [Int]) {
        let plain = String(text.characters)
        for (index, range) in ChatFindIndex.ranges(of: query, in: plain).enumerated() {
            let start = plain.distance(from: plain.startIndex, to: range.lowerBound)
            let length = plain.distance(from: range.lowerBound, to: range.upperBound)
            let lower = text.characters.index(text.startIndex, offsetBy: start)
            let upper = text.characters.index(lower, offsetBy: length)
            let solid = current?.leaf == leaf && current?.index == index
            text[lower..<upper].backgroundColor = solid ? Theme.Colors.findCurrent : Theme.Colors.findMatch
            if solid { text[lower..<upper].foregroundColor = Theme.Colors.findCurrentInk }
        }
    }
}

extension View {
    /// 只有绘制当前命中项的那个视图带上锚点，供会话记录滚动到它。
    @ViewBuilder
    func findAnchor(_ highlight: ChatTextHighlight?, leaf: [Int]) -> some View {
        if highlight?.isCurrent(leaf) == true {
            id(ChatTextHighlight.currentAnchor)
        } else {
            self
        }
    }
}

extension EnvironmentValues {
    /// 向下传递的当前查找高亮状态；为 nil 表示该视图不在标记范围内。
    @Entry var chatTextHighlight: ChatTextHighlight?
    /// 外层视图在其消息中的位置路径，构造方式与 `ChatFindIndex.leaves` 一致。
    @Entry var chatFindPath: [Int] = []
    /// 回复的来源编号，按 URL 键索引；除已完成且带来源的回复外处处为空。
    @Entry var chatCitations: [String: Int] = [:]
}
