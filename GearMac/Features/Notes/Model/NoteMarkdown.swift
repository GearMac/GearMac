// 文件职责：以带范围的行表示笔记的 Markdown，并提供行/行内片段的查询接口。
// 分层：Model；纯值类型、`Sendable`，不依赖 AppKit/SwiftUI。
import Foundation

/// 以带范围的行表示的笔记 Markdown；一行对应一个 TextKit 段落，也是一个重设样式的单元。
struct NoteMarkdown: Sendable, Equatable {
    /// 笔记的一行及其块级结构。
    struct Line: Sendable, Equatable {
        /// 行的块级类型。
        enum Kind: Sendable, Equatable {
            case blank
            case paragraph
            case heading(level: Int)
            case bullet
            case ordered(number: Int)
            case task(checked: Bool)
            case quote(depth: Int)
            case rule
            case fenceOpen(language: String?)
            case fenceClose
            case code
            /// GFM 表格中的一行，保持字面：没有行内片段，也不解析块级语法。
            case table

            /// 该行是否为列表行。
            var isList: Bool {
                switch self {
                case .bullet, .ordered, .task: true
                default: false
                }
            }

            /// 该行是否属于围栏代码块。
            var isFenced: Bool {
                switch self {
                case .fenceOpen, .fenceClose, .code: true
                default: false
                }
            }
        }

        let kind: Kind
        /// 整行（含行终止符），使各范围无缝铺满源文本。
        let range: NSRange
        /// 去掉行首块级语法标记、且不含行终止符的行内容。
        let contentRange: NSRange
        /// 行首缩进加块级标记及其后的空格；没有标记时为 nil。
        let markerRange: NSRange?
        /// 任务的三个字符 `[ ]` 或 `[x]`；否则为 nil。
        let checkboxRange: NSRange?
        /// 由缩进栈得出的列表嵌套深度；顶层与非列表行为 0。
        let level: Int
    }

    /// 行内片段：类型及其在源文本中的范围。
    struct Inline: Sendable, Equatable {
        /// 行内片段的类型。
        enum Kind: Sendable, Equatable {
            case strong, emphasis, strongEmphasis, strikethrough, code
            case link(destination: String)
            case autolink
        }

        let kind: Kind
        let range: NSRange
        let contentRange: NSRange
        /// 需要隐藏的每段语法：开闭分隔符，以及链接的 `](url)`。
        let markerRanges: [NSRange]
    }

    /// 各行解析自的源文本；仅凭行形状无法确定一篇笔记。
    let units: [UInt16]
    let lines: [Line]
    /// 围栏块的行索引范围，从开始行到结束行（未闭合时为最后一行）。
    let fenceBlocks: [ClosedRange<Int>]

    static let empty = NoteMarkdown(units: [], lines: [], fenceBlocks: [])

    /// 按需扫描：每个使用方只需要一行，全部预先存储开销更大。
    func inlines(of line: Line) -> [Inline] {
        switch line.kind {
        case .paragraph, .heading, .quote, .bullet, .ordered, .task:
            NoteInlineScanner(units: units)
                .inlines(in: line.contentRange.location..<NSMaxRange(line.contentRange))
        default:
            []
        }
    }

    /// 二分查找；解析器末尾的空行正是光标位于最末尾时的落点。
    func lineIndex(at location: Int) -> Int? {
        guard let last = lines.last, 0...NSMaxRange(last.range) ~= location else { return nil }
        var low = 0
        var high = lines.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if lines[middle].range.location <= location {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }

    /// 空范围只涉及自身所在行；终止于某行行首的范围不会触及该行。
    func lineIndexes(intersecting range: NSRange) -> Range<Int> {
        guard let first = lineIndex(at: range.location) else { return 0..<0 }
        guard range.length > 0, let last = lineIndex(at: NSMaxRange(range) - 1) else {
            return first..<(first + 1)
        }
        return first..<(max(first, last) + 1)
    }
}
