// 文件职责：在 Foundation 解析 Markdown 之前找出行内片段中的数学公式（`$…$`、`\(…\)`、`$$…$$`、`\[…\]`）。
// 分层：Model；纯文本扫描，不依赖 UI，保留代码跨度与转义。
import Foundation

/// 在一段行内 Markdown 中找出数学公式，抢在 Foundation 解析吞掉反斜杠之前。
enum MarkdownMath {
    /// 一个片段：普通文本、公式或未闭合的公式开头。
    enum Piece: Equatable {
        case text(String)
        case math(tex: String, display: Bool, source: String)
        /// 只有开头符、尚无结束符（流式触发公式中途）的内容，按原样显示。
        case unclosed(String)
    }

    /// `\(…\)` 与 `$…$` 为行内，`\[…\]` 与 `$$…$$` 为行间；代码跨度与 `\$` 保持为文本。
    static func pieces(of text: String) -> [Piece] {
        let characters = Array(text)
        var pieces: [Piece] = []
        var plain = ""
        var index = 0
        func flush() {
            if !plain.isEmpty { pieces.append(.text(plain)) }
            plain = ""
        }
        while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            if character == "`" {
                let end = codeSpanEnd(from: index, in: characters)
                plain += String(characters[index..<end])
                index = end
                continue
            }
            let opener: (length: Int, closer: [Character], display: Bool)? =
                switch (character, next) {
                case ("\\", "("): (2, ["\\", ")"], false)
                case ("\\", "["): (2, ["\\", "]"], true)
                case ("$", "$"): (2, ["$", "$"], true)
                case ("$", _): (1, ["$"], false)
                default: nil
                }
            guard let opener else {
                // 转义对整体算文本，因此 `\$` 不会开启公式，`\\(` 也不是 `\(`。
                let length = character == "\\" && next != nil ? 2 : 1
                plain += String(characters[index..<index + length])
                index += length
                continue
            }
            let bodyStart = index + opener.length
            guard let close = closer(opener.closer, from: bodyStart, in: characters) else {
                if opener.closer == ["$"] {
                    plain.append(character)
                    index += 1
                    continue
                }
                flush()
                pieces.append(.unclosed(String(characters[index...])))
                return pieces
            }
            let tex = String(characters[bodyStart..<close])
            let end = close + opener.closer.count
            if opener.closer == ["$"], !isInlineDollar(tex, followedBy: end, in: characters) {
                plain.append(character)
                index += 1
                continue
            }
            guard !tex.allSatisfy(\.isWhitespace) else {
                plain += String(characters[index..<end])
                index = end
                continue
            }
            flush()
            pieces.append(
                .math(tex: tex, display: opener.display, source: String(characters[index..<end])))
            index = end
        }
        flush()
        return pieces
    }

    /// 丢弃文本末尾仍在到达的公式；单个 `$` 可能是价格，因此保留。
    static func holdingBackUnclosed(_ text: String) -> String {
        guard case .unclosed(let tail)? = pieces(of: text).last, text.hasSuffix(tail) else { return text }
        return String(text.dropLast(tail.count))
    }

    /// Pandoc 的规则，用于保留 "$5 and $10" 这类正文：`$x$` 紧贴内容，且其后不能是数字。
    private static func isInlineDollar(
        _ tex: String, followedBy end: Int, in characters: [Character]
    )
        -> Bool
    {
        guard let first = tex.first, let last = tex.last, !first.isWhitespace, !last.isWhitespace
        else { return false }
        return end >= characters.count || !characters[end].isNumber
    }

    /// 第一个未转义的结束符，且不跨越代码跨度：单个 `$` 与紧随其后的 `$` 配对。
    private static func closer(
        _ closer: [Character], from start: Int, in characters: [Character]
    )
        -> Int?
    {
        var index = start
        while index + closer.count <= characters.count, characters[index] != "`" {
            if Array(characters[index..<index + closer.count]) == closer { return index }
            index += characters[index] == "\\" ? 2 : 1
        }
        return nil
    }

    /// 返回代码跨度结束反引号串之后的位置；若没有等长闭合串，则返回开头反引号串之后的位置。
    private static func codeSpanEnd(from start: Int, in characters: [Character]) -> Int {
        let run = characters[start...].prefix(while: { $0 == "`" }).count
        var index = start + run
        while index < characters.count {
            let length = characters[index...].prefix(while: { $0 == "`" }).count
            if length == run { return index + length }
            index += max(length, 1)
        }
        return start + run
    }
}
