// 文件职责：把回复的 Markdown 源文本解析为块级模型（标题、段落、列表、代码、引用、表格、公式），并渲染行内 Markdown 与数学公式。
// 分层：Model；纯解析与 AttributedString 构建，不依赖 AppKit/SwiftUI，容忍流式未完成文本。
import Foundation

/// 回复中的一个块；行内片段保留源码形式，交由视图用 `AttributedString` 处理。
enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bulletList([Item])
    case numberedList(start: Int, items: [Item])
    case code(language: String?, text: String)
    case quote([MarkdownBlock])
    case table(Table)
    case math(MathFormula)
    /// 仍在流式传入的行间公式，暂缓显示直到结束定界符到达。
    case pendingMath
    case rule

    /// 列表条目：包含块内容与可选的任务勾选状态。
    struct Item: Equatable, Sendable {
        let blocks: [MarkdownBlock]
        /// 仅由任务列表复选框设置，使普通项目符号保留自己的标记。
        let checked: Bool?
    }

    /// 表格：表头、对齐方式与数据行。
    struct Table: Equatable, Sendable {
        /// 单元格对齐方式。
        enum Alignment: Equatable, Sendable {
            case leading
            case center
            case trailing
        }

        let header: [String]
        let alignments: [Alignment]
        let rows: [[String]]
    }

        /// 一段行内 Markdown，在此处一次性解析，使绘制结果与查找计数一致。
    static func inline(_ source: String) -> AttributedString {
        let pieces = MarkdownMath.pieces(of: source)
        guard pieces.contains(where: { $0 != .text(source) }) else { return markdown(source) }
        var masked = ""
        var standIns: [Character: StandIn] = [:]
        for piece in pieces {
            let standIn: StandIn
            switch piece {
            case .text(let text):
                masked += text
                continue
            case .math(let tex, let display, let source):
                standIn =
                    MathFormula(tex: tex, source: source, display: display).map(StandIn.formula)
                    ?? .literal(source)
            case .unclosed(let source): standIn = .literal(source)
            }
            guard let key = standInKey(standIns.count) else {
                masked += standIn.source
                continue
            }
            standIns[key] = standIn
            masked.append(key)
        }
        return restoring(standIns, in: markdown(masked))
    }

    /// 用仅行内的 Markdown 选项解析源文本，失败时按纯文本返回。
    private static func markdown(_ source: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible
        return (try? AttributedString(markdown: source, options: options))
            ?? AttributedString(source)
    }

    /// 数学公式以私有使用区字符的身份等待 Foundation 解析完成，不受任何 Markdown 规则影响。
    private enum StandIn {
        case formula(MathFormula)
        case literal(String)

        var source: String {
            switch self {
            case .formula(let formula): formula.source
            case .literal(let source): source
            }
        }
    }

    /// 把序号映射为私有使用区字符，作为占位符。
    private static func standInKey(_ number: Int) -> Character? {
        Unicode.Scalar(0xE000 + number).flatMap { $0.value <= 0xF8FF ? Character($0) : nil }
    }

    /// 把每个占位符还原为公式的单字符占位，无法排版时则还原为其源码。
    private static func restoring(
        _ standIns: [Character: StandIn], in parsed: AttributedString
    )
        -> AttributedString
    {
        var result = parsed
        let found = result.characters.indices.filter { standIns[result.characters[$0]] != nil }
        for position in found.reversed() {
            guard let standIn = standIns[result.characters[position]] else { continue }
            let range = position..<result.characters.index(after: position)
            let attributes = result[range].runs.first?.attributes ?? AttributeContainer()
            var replacement: AttributedString
            switch standIn {
            case .formula(let formula):
                replacement = AttributedString(String(MathFormula.placeholder), attributes: attributes)
                replacement[MathFormula.Attribute.self] = formula
            case .literal(let source):
                replacement = AttributedString(source, attributes: attributes)
            }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    /// 容忍流式传入的半成品文本；`midStream` 会暂缓仍在到达的公式。
    static func parse(_ markdown: String, midStream: Bool = false) -> [MarkdownBlock] {
        let text = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        var reader = MarkdownReader(lines: text.components(separatedBy: "\n"), endsMidStream: midStream)
        return reader.blocks()
    }
}

/// 逐行读取 Markdown 并产出块序列的读取器。
private struct MarkdownReader {
    let lines: [String]
    /// 这些行一直延伸到仍在流式输入的回复当前结束处。
    let endsMidStream: Bool
    var index = 0

    /// 位于流式回复最后一段文本之后的位置，此处未闭合的公式仍可能闭合。
    private var isAtStreamEnd: Bool { endsMidStream && onlyBlankLines(from: index) }

    /// 刚发出换行的流会停在空行上，这还不能证明什么。
    private func onlyBlankLines(from position: Int) -> Bool {
        lines[min(position, lines.count)...].allSatisfy(\.isBlankLine)
    }

    /// 位于流末尾时暂缓仍在到达的未闭合公式，否则原样返回。
    private func heldBack(_ text: String) -> String {
        isAtStreamEnd ? MarkdownMath.holdingBackUnclosed(text) : text
    }

    /// 顺序消费所有行并产出块列表。
    mutating func blocks() -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        while let line = peek() {
            if line.isBlankLine {
                index += 1
            } else if let fence = MarkdownLine.fence(line) {
                blocks.append(code(fence))
            } else if let math = math() {
                blocks.append(math)
            } else if MarkdownLine.isRule(line) {
                index += 1
                blocks.append(.rule)
            } else if case .heading(let level, let text)? = MarkdownLine.heading(line) {
                index += 1
                blocks.append(.heading(level: level, text: heldBack(text)))
            } else if MarkdownLine.isQuote(line) {
                blocks.append(quote())
            } else if let table = table() {
                blocks.append(table)
            } else if let marker = MarkdownLine.listMarker(line) {
                blocks.append(list(from: marker))
            } else if let paragraph = paragraph() {
                blocks.append(paragraph)
            }
        }
        return blocks
    }

    /// 查看当前或偏移位置的行，越界返回 nil。
    private func peek(_ offset: Int = 0) -> String? {
        let target = index + offset
        return lines.indices.contains(target) ? lines[target] : nil
    }

    /// 消费一个围栏代码块。
    private mutating func code(_ fence: MarkdownLine.Fence) -> MarkdownBlock {
        index += 1
        var body: [String] = []
        while let line = peek(), !MarkdownLine.closes(line, fence) {
            body.append(MarkdownLine.dedent(line, by: fence.indent))
            index += 1
        }
        if peek() != nil { index += 1 }
        while body.last?.isBlankLine == true { body.removeLast() }
        return .code(language: fence.language, text: body.joined(separator: "\n"))
    }

    /// 以 `$$` 或 `\[` 开头的一行；未闭合时按普通段落显示其源码。
    private mutating func math() -> MarkdownBlock? {
        guard let first = peek(), let fence = MarkdownLine.mathFence(first) else { return nil }
        var rest = fence.rest
        var body: [String] = []
        var offset = 0
        while true {
            if let close = rest.range(of: fence.closer) {
                guard rest[close.upperBound...].allSatisfy(\.isWhitespace) else { return nil }
                body.append(String(rest[..<close.lowerBound]))
                break
            }
            body.append(rest)
            offset += 1
            if endsMidStream, onlyBlankLines(from: index + offset) {
                index = lines.count
                return .pendingMath
            }
            // 空行之后还有文本可证明开头符是孤立的：行间公式不会跨越空行。
            guard let line = peek(offset), !line.isBlankLine else { return nil }
            rest = line
        }
        let source = lines[index...index + offset].joined(separator: "\n")
            .trimmingCharacters(in: .whitespaces)
        index += offset + 1
        let tex = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tex.isEmpty else { return .paragraph(source) }
        return MathFormula(tex: tex, source: source, display: true).map(MarkdownBlock.math)
            ?? .code(language: "latex", text: tex)
    }

    /// 消费一个引用块，把内部行交给新的读取器解析。
    private mutating func quote() -> MarkdownBlock {
        var inner: [String] = []
        while let line = peek() {
            if MarkdownLine.isQuote(line) {
                inner.append(MarkdownLine.strippingQuoteMarker(line))
            } else if line.isBlankLine || MarkdownLine.startsBlock(line, interrupting: false) {
                break
            } else {
                inner.append(line)
            }
            index += 1
        }
        var reader = MarkdownReader(lines: inner, endsMidStream: isAtStreamEnd)
        return .quote(reader.blocks())
    }

    /// 消费一个表格块；不满足表头/分隔行条件时返回 nil。
    private mutating func table() -> MarkdownBlock? {
        guard let header = peek(), header.contains("|"), let delimiter = peek(1),
            let alignments = MarkdownLine.tableAlignments(delimiter)
        else { return nil }
        let titles = MarkdownLine.tableCells(header)
        guard titles.count == alignments.count else { return nil }
        index += 2
        var rows: [[String]] = []
        while let line = peek(), !line.isBlankLine, line.contains("|") {
            var cells = MarkdownLine.tableCells(line)
            index += 1
            // 只有流正在写入的那个单元格可能在公式中途结束。
            if let last = cells.indices.last { cells[last] = heldBack(cells[last]) }
            rows.append(cells.resized(to: titles.count))
        }
        return .table(.init(header: titles, alignments: alignments, rows: rows))
    }

    /// 消费同级的列表项，产出无序或有序列表。
    private mutating func list(from first: MarkdownLine.Marker) -> MarkdownBlock {
        var items: [MarkdownBlock.Item] = []
        while let line = peek(), let marker = MarkdownLine.listMarker(line),
            marker.isOrdered == first.isOrdered, marker.indent <= first.indent + 1
        {
            index += 1
            items.append(item(startingWith: line, marker: marker))
        }
        guard first.isOrdered else { return .bulletList(items) }
        return .numberedList(start: first.number, items: items)
    }

    /// 消费一个列表条目，并识别其中的任务复选框。
    private mutating func item(
        startingWith line: String, marker: MarkdownLine.Marker
    )
        -> MarkdownBlock.Item
    {
        var body = [String(line.dropFirst(min(marker.contentIndent, line.count)))]
        while let line = peek() {
            if line.isBlankLine {
                guard let next = peek(1), !next.isBlankLine, next.indent >= marker.contentIndent
                else { break }
            } else if line.indent < marker.contentIndent,
                MarkdownLine.startsBlock(line, interrupting: false)
            {
                break
            }
            body.append(MarkdownLine.dedent(line, by: marker.contentIndent))
            index += 1
        }
        var reader = MarkdownReader(lines: body, endsMidStream: isAtStreamEnd)
        var blocks = reader.blocks()
        guard case .paragraph(let text) = blocks.first, let task = MarkdownLine.taskBox(text) else {
            return .init(blocks: blocks, checked: nil)
        }
        blocks[0] = .paragraph(task.rest)
        return .init(blocks: blocks, checked: task.checked)
    }

    /// 当目前内容只是一段仍在到达的公式时返回 nil。
    private mutating func paragraph() -> MarkdownBlock? {
        var body: [String] = []
        while let line = peek(), !line.isBlankLine {
            if !body.isEmpty, MarkdownLine.startsBlock(line, interrupting: true) || startsTable() {
                break
            }
            body.append(line.trimmingCharacters(in: .whitespaces))
            index += 1
        }
        let text = heldBack(body.joined(separator: "\n"))
        return text.allSatisfy(\.isWhitespace) ? nil : .paragraph(text)
    }

    /// 判断当前位置是否是表格的开头。
    private func startsTable() -> Bool {
        guard let header = peek(), header.contains("|"), let delimiter = peek(1) else { return false }
        return MarkdownLine.tableAlignments(delimiter) != nil
    }
}

/// 纯行级分类：读取器在消费块之前需要识别的全部行形态。
private enum MarkdownLine {
    /// 围栏代码块的标记信息。
    struct Fence {
        let character: Character
        let length: Int
        let indent: Int
        let language: String?
    }

    /// 列表标记信息。
    struct Marker {
        let indent: Int
        /// 条目自身内容起始的列，也是其后续行去缩进的幅度。
        let contentIndent: Int
        let isOrdered: Bool
        let number: Int
    }

    /// 识别围栏代码块的开头。
    static func fence(_ line: String) -> Fence? {
        let indent = line.indent
        let body = line.dropFirst(indent)
        guard let character = body.first, character == "`" || character == "~" else { return nil }
        let length = body.prefix(while: { $0 == character }).count
        guard length >= 3 else { return nil }
        let info = body.dropFirst(length).trimmingCharacters(in: .whitespaces)
        guard character == "~" || !info.contains("`") else { return nil }
        let language = info.split(separator: " ").first.map(String.init)
        return Fence(character: character, length: length, indent: indent, language: language)
    }

    /// 判断某行是否闭合给定的代码围栏。
    static func closes(_ line: String, _ fence: Fence) -> Bool {
        let body = line.dropFirst(line.indent)
        let run = body.prefix(while: { $0 == fence.character }).count
        return run >= fence.length && body.dropFirst(run).allSatisfy(\.isWhitespace)
    }

    /// 判断是否为分隔线（`---`/`***`/`___`）。
    static func isRule(_ line: String) -> Bool {
        let body = line.filter { !$0.isWhitespace }
        guard let character = body.first, "-*_".contains(character) else { return false }
        return body.count >= 3 && body.allSatisfy { $0 == character }
    }

    /// 识别 ATX 标题，返回标题块或 nil。
    static func heading(_ line: String) -> MarkdownBlock? {
        let body = line.dropFirst(line.indent)
        let level = body.prefix(while: { $0 == "#" }).count
        let rest = body.dropFirst(level)
        guard (1...6).contains(level), rest.isEmpty || rest.first == " " else { return nil }
        return .heading(level: level, text: strippingClosingHashes(rest))
    }

    /// 判断是否为引用行。
    static func isQuote(_ line: String) -> Bool { line.dropFirst(line.indent).first == ">" }

    /// 行间公式在该行开头的定界符，以及该行定界符之后的内容。
    static func mathFence(_ line: String) -> (closer: String, rest: String)? {
        let body = line.trimmingCharacters(in: .whitespaces)
        if body.hasPrefix("$$") { return ("$$", String(body.dropFirst(2))) }
        if body.hasPrefix("\\[") { return ("\\]", String(body.dropFirst(2))) }
        return nil
    }

    /// 自行闭合公式后还有后续内容的行是正文，而非行间公式块。
    static func opensMath(_ line: String) -> Bool {
        guard let fence = mathFence(line) else { return false }
        guard let close = fence.rest.range(of: fence.closer) else { return true }
        return fence.rest[close.upperBound...].allSatisfy(\.isWhitespace)
    }

    /// 去掉引用行开头的 `>` 及其后一个空格。
    static func strippingQuoteMarker(_ line: String) -> String {
        var body = line.dropFirst(line.indent).dropFirst()
        if body.first == " " { body = body.dropFirst() }
        return String(body)
    }

    /// 识别无序或有序列表标记。
    static func listMarker(_ line: String) -> Marker? {
        let indent = line.indent
        let body = line.dropFirst(indent)
        guard let character = body.first else { return nil }
        var isOrdered = false
        var number = 1
        var width = 1
        if !"-*+".contains(character) {
            let digits = body.prefix(while: \.isNumber)
            guard digits.count <= 9, let value = Int(digits),
                let delimiter = body.dropFirst(digits.count).first, delimiter == "." || delimiter == ")"
            else { return nil }
            isOrdered = true
            number = value
            width = digits.count + 1
        }
        let rest = body.dropFirst(width)
        let gap = rest.prefix(while: { $0 == " " }).count
        guard rest.isEmpty || gap > 0 else { return nil }
        return Marker(
            indent: indent, contentIndent: indent + width + max(gap, 1), isOrdered: isOrdered,
            number: number)
    }

    /// `interrupting` 对应 CommonMark 规则：只有 `1.` 可以中断段落。
    static func startsBlock(_ line: String, interrupting: Bool) -> Bool {
        if fence(line) != nil || isRule(line) || heading(line) != nil || isQuote(line) || opensMath(line) {
            return true
        }
        guard let marker = listMarker(line) else { return false }
        return !interrupting || (!marker.isOrdered || marker.number == 1)
    }

    /// 识别任务列表复选框 `[ ]`/`[x]`，返回勾选状态与剩余文本。
    static func taskBox(_ text: String) -> (checked: Bool, rest: String)? {
        guard text.count >= 3, text.hasPrefix("["), text.dropFirst(2).first == "]" else { return nil }
        let box = text.dropFirst().first
        guard box == " " || box == "x" || box == "X" else { return nil }
        let rest = text.dropFirst(3)
        guard rest.isEmpty || rest.first == " " else { return nil }
        return (box != " ", String(rest.dropFirst(rest.isEmpty ? 0 : 1)))
    }

    /// 按未转义竖线切分表格行，去掉首尾竖线与单元格空白。
    static func tableCells(_ line: String) -> [String] {
        var body = Substring(line.trimmingCharacters(in: .whitespaces))
        if body.first == "|" { body = body.dropFirst() }
        if body.hasSuffix("|"), !body.hasSuffix("\\|") { body = body.dropLast() }
        var cells: [String] = []
        var current = ""
        var isEscaped = false
        for character in body {
            if isEscaped || character == "\\" {
                isEscaped = !isEscaped && character == "\\"
                current.append(character)
            } else if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    /// 必须含竖线：否则正文下方单独的 `---` 是分隔线而非表格。
    static func tableAlignments(_ line: String) -> [MarkdownBlock.Table.Alignment]? {
        guard line.contains("|") else { return nil }
        var alignments: [MarkdownBlock.Table.Alignment] = []
        for cell in tableCells(line) {
            let dashes = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            let isLeading = cell.hasPrefix(":")
            let isTrailing = cell.hasSuffix(":")
            alignments.append(isLeading && isTrailing ? .center : isTrailing ? .trailing : .leading)
        }
        return alignments.isEmpty ? nil : alignments
    }

    /// 去掉行首最多 count 个空白字符。
    static func dedent(_ line: String, by count: Int) -> String {
        var body = Substring(line)
        var remaining = count
        while remaining > 0, let character = body.first, character == " " || character == "\t" {
            body = body.dropFirst()
            remaining -= 1
        }
        return String(body)
    }

    /// 结尾的 `###` 只有与文本间有空格时才视为结束标记，因此 `# C#` 保留它的井号。
    private static func strippingClosingHashes(_ text: Substring) -> String {
        let body = text.trimmingCharacters(in: .whitespaces)
        let hashes = body.reversed().prefix(while: { $0 == "#" }).count
        guard hashes > 0, hashes < body.count,
            body[body.index(body.endIndex, offsetBy: -hashes - 1)] == " "
        else { return body }
        return body.dropLast(hashes).trimmingCharacters(in: .whitespaces)
    }
}

/// 面向 Markdown 行解析的字符串辅助属性。
extension StringProtocol {
    /// 是否整行只有空白。
    fileprivate var isBlankLine: Bool { allSatisfy(\.isWhitespace) }

    /// 以字符数计量的前导空白，可直接用于回索引该行。
    fileprivate var indent: Int { prefix(while: { $0 == " " || $0 == "\t" }).count }
}

/// Markdown 表格行的列数调整辅助。
extension [String] {
    /// 把数组调整到指定长度，不足处补空字符串。
    fileprivate func resized(to count: Int) -> [String] {
        self.count >= count
            ? Array(prefix(count)) : self + Array(repeating: "", count: count - self.count)
    }
}
