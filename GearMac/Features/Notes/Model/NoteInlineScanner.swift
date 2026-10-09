// 文件职责：扫描单行内容中的行内 Markdown 片段（代码、链接、裸 URL、强调与删除线）。
// 分层：Model；纯算法、不依赖 AppKit/SwiftUI。
import Foundation

/// 查找单行内容中的行内片段；解析器从不会传入超过一行的内容。
struct NoteInlineScanner {
    /// 该行内容的 UTF-16 码元。
    let units: [UInt16]

    private typealias Unit = NoteMarkdownParser.Unit

    /// 裸 URL 只有写明 scheme 时才被识别，绝不从裸域名推断。
    static let webPrefixes = ["https://", "http://"]

    /// GFM 中永远不属于裸 URL 的结尾标点。
    private static let autolinkTrailing: Set<UInt16> = Set(".,;:!?*_~".utf16)

    /// 按位置排序，外层片段排在内层之前。
    func inlines(in content: Range<Int>) -> [NoteMarkdown.Inline] {
        guard units[content].contains(where: Self.mayStartInline) else { return [] }
        return scan(content, inLabel: false).sorted {
            ($0.range.location, -$0.range.length) < ($1.range.location, -$1.range.length)
        }
    }

    /// 该码元是否可能是行内片段的起始。
    private static func mayStartInline(_ unit: UInt16) -> Bool {
        switch unit {
        case Unit.asterisk, Unit.underscore, Unit.tilde, Unit.backtick, Unit.openBracket,
            Unit.backslash, Unit.colon:
            true
        default:
            false
        }
    }

    /// 主扫描循环：先识别行内代码、行内链接与裸 URL，再叠加强调与删除线。
    private func scan(_ content: Range<Int>, inLabel: Bool) -> [NoteMarkdown.Inline] {
        var found: [NoteMarkdown.Inline] = []
        var blocked = [Bool](repeating: false, count: content.count)
        func block(_ range: Range<Int>) {
            for index in range.clamped(to: content) { blocked[index - content.lowerBound] = true }
        }
        var index = content.lowerBound
        while index < content.upperBound {
            let unit = units[index]
            if unit == Unit.backslash, index + 1 < content.upperBound,
                Unit.isASCIIPunctuation(units[index + 1])
            {
                block(index..<index + 2)
                index += 2
            } else if unit == Unit.backtick {
                let span = codeSpan(at: index, in: content)
                if let inline = span.inline { found.append(inline) }
                block(index..<span.end)
                index = span.end
            } else if unit == Unit.openBracket, !inLabel, let link = link(at: index, in: content) {
                let isImage = index > content.lowerBound && units[index - 1] == Unit.exclamation
                if isImage {
                    block((index - 1)..<link.end)
                } else {
                    let label = (index + 1)..<link.labelEnd
                    found.append(
                        NoteMarkdown.Inline(
                            kind: .link(destination: link.destination),
                            range: NSRange(index..<link.end), contentRange: NSRange(label),
                            markerRanges: [
                                NSRange(location: index, length: 1), NSRange(link.labelEnd..<link.end)
                            ]))
                    found += scan(label, inLabel: true)
                    block(index..<link.end)
                }
                index = link.end
            } else if !inLabel, let end = autolinkEnd(at: index, in: content) {
                found.append(
                    NoteMarkdown.Inline(
                        kind: .autolink, range: NSRange(index..<end), contentRange: NSRange(index..<end),
                        markerRanges: []))
                block(index..<end)
                index = end
            } else {
                index += 1
            }
        }
        return found + emphasis(in: content, blocked: blocked)
    }

    // MARK: - Code, links, bare URLs

    /// 未闭合的反引号串视为普通文本，但其结束位置仍是扫描继续的地方。
    private func codeSpan(at start: Int, in content: Range<Int>) -> (inline: NoteMarkdown.Inline?, end: Int) {
        let openEnd = runEnd(of: Unit.backtick, from: start, in: content)
        let length = openEnd - start
        var index = openEnd
        while index < content.upperBound {
            guard units[index] == Unit.backtick else {
                index += 1
                continue
            }
            let closeEnd = runEnd(of: Unit.backtick, from: index, in: content)
            if closeEnd - index == length {
                let inline = NoteMarkdown.Inline(
                    kind: .code, range: NSRange(start..<closeEnd), contentRange: NSRange(openEnd..<index),
                    markerRanges: [NSRange(start..<openEnd), NSRange(index..<closeEnd)])
                return (inline, closeEnd)
            }
            index = closeEnd
        }
        return (nil, openEnd)
    }

    /// 解析 `[label](destination)` 形式的行内链接；不合法时返回 nil。
    private func link(
        at open: Int, in content: Range<Int>
    ) -> (labelEnd: Int, end: Int, destination: String)? {
        var depth = 0
        var index = open
        var labelEnd: Int?
        while index < content.upperBound, labelEnd == nil {
            switch units[index] {
            case Unit.backslash: index += 1
            case Unit.openBracket: depth += 1
            case Unit.closeBracket:
                depth -= 1
                if depth == 0 { labelEnd = index }
            default: break
            }
            index += 1
        }
        guard let labelEnd, labelEnd + 1 < content.upperBound, units[labelEnd + 1] == Unit.openParen
        else { return nil }
        var parentheses = 0
        index = labelEnd + 2
        while index < content.upperBound {
            let unit = units[index]
            if Unit.isWhitespace(unit) { return nil }
            if unit == Unit.backslash {
                index += 2
                continue
            }
            if unit == Unit.openParen { parentheses += 1 }
            if unit == Unit.closeParen {
                guard parentheses == 0 else {
                    parentheses -= 1
                    index += 1
                    continue
                }
                let destination = String(decoding: units[(labelEnd + 2)..<index], as: UTF16.self)
                return (labelEnd, index + 1, destination)
            }
            index += 1
        }
        return nil
    }

    /// 裸 URL 的结束位置（不含结尾标点）；不是裸 URL 时返回 nil。
    private func autolinkEnd(at start: Int, in content: Range<Int>) -> Int? {
        guard units[start] | 0x20 == 0x68 else { return nil }
        if start > content.lowerBound, Unit.isAlphanumeric(units[start - 1]) { return nil }
        guard
            let schemeEnd = Self.webPrefixes.lazy.compactMap({
                matchesIgnoringCase($0, at: start, in: content)
            }).first
        else { return nil }
        var end =
            units[schemeEnd..<content.upperBound].firstIndex(where: Unit.isWhitespace)
            ?? content.upperBound
        while end > schemeEnd {
            let last = units[end - 1]
            if Self.autolinkTrailing.contains(last) {
                end -= 1
            } else if last == Unit.closeParen, hasUnmatchedCloser(start..<end) {
                end -= 1
            } else {
                break
            }
        }
        return end > schemeEnd ? end : nil
    }

    /// 区间内右括号是否多于左括号。
    private func hasUnmatchedCloser(_ range: Range<Int>) -> Bool {
        let opens = units[range].count { $0 == Unit.openParen }
        let closes = units[range].count { $0 == Unit.closeParen }
        return closes > opens
    }

    /// 从 start 起忽略大小写匹配前缀，成功时返回其结束位置。
    private func matchesIgnoringCase(_ prefix: String, at start: Int, in content: Range<Int>) -> Int? {
        var index = start
        for expected in prefix.utf16 {
            guard index < content.upperBound, units[index] | 0x20 == expected | 0x20 else { return nil }
            index += 1
        }
        return index
    }

    /// 从 start 起连续相同码元的结束位置。
    private func runEnd(of unit: UInt16, from start: Int, in content: Range<Int>) -> Int {
        units[start..<content.upperBound].firstIndex { $0 != unit } ?? content.upperBound
    }

    // MARK: - Emphasis and strikethrough

    /// 一段连续的分隔符（强调标记）。
    private struct DelimiterRun {
        let marker: UInt16
        var start: Int
        var end: Int
        var length: Int { end - start }
    }

    /// 分隔符与同字符最近的开放段配对，与 CommonMark 一致。
    private func emphasis(in content: Range<Int>, blocked: [Bool]) -> [NoteMarkdown.Inline] {
        var found: [NoteMarkdown.Inline] = []
        var openers: [DelimiterRun] = []
        var index = content.lowerBound
        while index < content.upperBound {
            let marker = units[index]
            guard !blocked[index - content.lowerBound],
                marker == Unit.asterisk || marker == Unit.underscore || marker == Unit.tilde
            else {
                index += 1
                continue
            }
            var end = index + 1
            while end < content.upperBound, units[end] == marker, !blocked[end - content.lowerBound] {
                end += 1
            }
            defer { index = end }
            if marker == Unit.tilde, end - index != 2 { continue }

            let before = index > content.lowerBound ? units[index - 1] : nil
            let after = end < content.upperBound ? units[end] : nil
            var canOpen = after.map { !Unit.isWhitespace($0) } ?? false
            var canClose = before.map { !Unit.isWhitespace($0) } ?? false
            if marker == Unit.underscore {
                canOpen = canOpen && !(before.map(Unit.isAlphanumeric) ?? false)
                canClose = canClose && !(after.map(Unit.isAlphanumeric) ?? false)
            }

            var run = DelimiterRun(marker: marker, start: index, end: end)
            if run.length > 3, canOpen != canClose {
                if canOpen { run.start = run.end - 3 } else { run.end = run.start + 3 }
            }
            while canClose, run.length > 0,
                let openerIndex = openers.lastIndex(where: { $0.marker == marker })
            {
                var opener = openers[openerIndex]
                let use = marker == Unit.tilde ? 2 : min(opener.length, run.length, 3)
                let open = (opener.end - use)..<opener.end
                let close = run.start..<(run.start + use)
                found.append(
                    NoteMarkdown.Inline(
                        kind: Self.emphasisKind(marker: marker, length: use),
                        range: NSRange(open.lowerBound..<close.upperBound),
                        contentRange: NSRange(open.upperBound..<close.lowerBound),
                        markerRanges: [NSRange(open), NSRange(close)]))
                opener.end -= use
                run.start += use
                openers.removeSubrange((openerIndex + 1)..<openers.count)
                if opener.length > 0 {
                    openers[openerIndex] = opener
                } else {
                    openers.remove(at: openerIndex)
                }
            }
            if canOpen, run.length > 0 { openers.append(run) }
        }
        return found
    }

    /// 由分隔符与使用长度判定行内片段类型。
    private static func emphasisKind(marker: UInt16, length: Int) -> NoteMarkdown.Inline.Kind {
        guard marker != Unit.tilde else { return .strikethrough }
        switch length {
        case 1: return .emphasis
        case 2: return .strong
        default: return .strongEmphasis
        }
    }
}
