// 文件职责：对话内查找：按与转写视图一致的遍历顺序列出全部命中位置，并计算文本匹配区间。
// 分层：Model；纯计算，不得 import AppKit/SwiftUI。
import Foundation

/// 一次查找命中：所属消息、所在的绘制文本片段，以及它在该片段中的第几次匹配。
struct ChatFindOccurrence: Equatable, Hashable, Sendable {
    let messageID: UUID
    /// 绘制文本的位置路径而非其内容：两个内容相同的表格单元格也是两处不同位置。
    let leaf: [Int]
    let index: Int
}

/// 按阅读顺序列出整个转写中的全部命中，遍历方式与转写视图的绘制方式完全一致。
enum ChatFindIndex {
    /// 匹配选项：忽略大小写与变音符号。
    static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// 在消息列表中查找全部命中，按消息与片段的顺序展开。
    static func occurrences(of query: String, in messages: [ChatMessage]) -> [ChatFindOccurrence] {
        guard !query.isEmpty else { return [] }
        return messages.flatMap { message in
            leaves(of: message).flatMap { leaf in
                ranges(of: query, in: leaf.visible).indices.map {
                    ChatFindOccurrence(messageID: message.id, leaf: leaf.path, index: $0)
                }
            }
        }
    }

    /// 在文本中找出 query 的全部不重叠匹配区间。
    static func ranges(of query: String, in text: String) -> [Range<String.Index>] {
        guard !query.isEmpty else { return [] }
        var found: [Range<String.Index>] = []
        var from = text.startIndex
        while let range = text.range(of: query, options: options, range: from..<text.endIndex) {
            found.append(range)
            from = range.upperBound
        }
        return found
    }

    /// 绘制文本片段：路径与其中可见的文本。
    typealias Leaf = (path: [Int], visible: String)

    /// 一条消息按顺序绘制出的每段文本，路径与转写视图构建的一致。
    static func leaves(of message: ChatMessage) -> [Leaf] {
        guard message.role == .assistant else { return [([0], message.text)] }
        let segments = message.segments
        return segments.enumerated().flatMap { offset, segment -> [Leaf] in
            switch segment {
            case .text(let text):
                let blocks = MarkdownBlock.parse(
                    ChatChoices.split(text).text,
                    midStream: message.isArriving(segmentAt: offset, of: segments.count))
                return leaves(of: blocks, at: [offset])
            case .reasoning(let block): return [([offset], block.text)]
            case .search, .tools: return []
            }
        }
    }

    /// 递归展开 Markdown 块，得到各片段的路径与可见文本。
    private static func leaves(of blocks: [MarkdownBlock], at prefix: [Int]) -> [Leaf] {
        blocks.enumerated().flatMap { offset, block -> [Leaf] in
            let path = prefix + [offset]
            switch block {
            case .heading(_, let text), .paragraph(let text): return [(path, inline(text))]
            case .bulletList(let items), .numberedList(_, let items):
                return items.enumerated().flatMap { leaves(of: $1.blocks, at: path + [$0]) }
            case .code(_, let text): return [(path, text)]
            case .quote(let blocks): return leaves(of: blocks, at: path)
            case .table(let table):
                return ([table.header] + table.rows).enumerated().flatMap { row, cells in
                    cells.enumerated().map { (path + [row, $0], inline($1)) }
                }
            case .math, .pendingMath, .rule: return []
            }
        }
    }

    /// 把行内 Markdown 源文本渲染为可见纯文本。
    private static func inline(_ source: String) -> String {
        String(MarkdownBlock.inline(source).characters)
    }
}
