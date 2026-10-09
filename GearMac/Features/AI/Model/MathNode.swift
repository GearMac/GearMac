// 文件职责：定义数学公式的中间表示（TeX 原子与堆叠结构）及其 TeX 子集解析器，供 AI 回复排版公式。
// 分层：Model；不 import AppKit/SwiftUI，解析不支持或超限时返回 nil，由调用方回退显示源码。
import Foundation

/// 一个公式按 TeX 的理解方式表示：带间距类型（spacing kind）的原子，以及把原子堆叠起来的结构。
indirect enum MathNode: Hashable, Sendable {
    /// 单个绘制字符，已处于其数学字母表（math alphabet）中。
    case symbol(String, Kind)
    /// 直立文本：`\text`，以及 `\bmod` 的 "mod"。
    case text(String, Kind)
    /// 直立的运算符名（如 `\sin`）：`limits` 为 true 时脚本位于正上方/正下方。
    case operatorName(String, limits: Bool)
    /// 大运算符（如 `\sum`）：`limits` 为 true 时上下限垂直摆放。
    case largeOperator(String, limits: Bool)
    /// 水平拼接的一串节点。
    case row([MathNode])
    /// 上标/下标附着在同一个基（base）上。
    case scripts(base: MathNode, superscript: MathNode?, subscript: MathNode?)
    /// `\overset` 与 `\underset`：在基的正上方或正下方放置一个脚本。
    case stack(base: MathNode, over: MathNode?, under: MathNode?)
    case fraction(numerator: MathNode, denominator: MathNode, rule: Bool, style: Style?)
    case radical(MathNode, degree: MathNode?)
    /// `\left…\right`；空的一侧写作 `\left.`。
    case fenced(open: String, body: MathNode, close: String)
    /// `\big(` 及其同类命令：比正文高 1 到 4 档。
    case delimiter(String, size: Int, Kind)
    case accent(MathNode, mark: String, wide: Bool)
    case overline(MathNode)
    case underline(MathNode)
    case boxed(MathNode)
    /// 单位为 mu，即 TeX 中的一个 em 的十八分之一。
    case space(Double)
    case styled(Style, MathNode)
    /// 行列对齐的表格节点。
    case table(Table)

    /// TeX 的原子类型，决定相邻两个原子之间的间距。
    enum Kind: Hashable, Sendable {
        case ord, op, bin, rel, open, close, punct, inner
    }

    /// 公式的排版样式，决定字号与上下限的摆放方式。
    enum Style: Hashable, Sendable {
        case display, text, script, scriptScript
    }

    /// 数学字母表变体：斜体、直立、粗体、黑板体、花体等。
    enum Alphabet: Hashable, Sendable {
        case italic, upright, bold, boldItalic, doubleStruck, script, fraktur, sansSerif, monospace
    }

    /// 矩阵、cases 与 aligned 等式：单元格按行组织，列按固定模式对齐并设置间距。
    struct Table: Hashable, Sendable {
        enum Alignment: Hashable, Sendable {
            case leading, center, trailing
        }

        let rows: [[MathNode]]
        /// 按列循环重复，正如 aligned 的右-左成对模式。
        let alignments: [Alignment]
        /// 每列之后以 mu 为单位的间距，同样按列循环重复。
        let gaps: [Double]
        let style: Style
    }

    /// 超出支持的子集时返回 nil，从而展示回复原文而不是猜测结果。
    static func parse(_ tex: String) -> MathNode? {
        guard tex.count <= maximumLength else { return nil }
        var reader = TeXReader(characters: Array(tex))
        return try? reader.formula()
    }

    /// 回复属于不可信文本；超过这些上限时公式按源码显示，而不做排版。
    static let maximumLength = 4000
    /// 解析允许的最大嵌套深度，避免过深递归。
    fileprivate static let maximumDepth = 40
}

/// 逐字符读取 TeX 源码的解析器，维护当前位置索引、嵌套深度与当前字母表状态。
private struct TeXReader {
    /// 解析失败：遇到不支持的 TeX 命令或结构。
    enum Failure: Error {
        case unsupported
    }

    /// 词法单元：命令、普通字符、花括号、上下标、对齐符与结束。
    enum Token: Equatable {
        case command(String)
        case character(Character)
        case open
        case close
        case superscript
        case `subscript`
        case alignment
        case end
    }

    /// 列表的终止条件：每种结构在自己的终止符处结束。
    enum Stop: Equatable {
        case end
        case brace
        case bracket
        case right
        case cell
    }

    let characters: [Character]
    var index = 0
    var depth = 0
    var alphabet = MathNode.Alphabet.italic

    /// 以字符数组初始化解析器。
    init(characters: [Character]) {
        self.characters = characters
    }

    /// 解析整个公式：单个原子直接返回，多列则按对齐表格处理。
    mutating func formula() throws -> MathNode {
        let rows = try cells()
        guard index >= characters.count else { throw Failure.unsupported }
        if rows.count == 1, rows[0].count == 1 { return .row(rows[0][0]) }
        let aligned = rows.contains { $0.count > 1 }
        return .table(
            .init(
                rows: rows.map { $0.map(MathNode.row) },
                alignments: aligned ? [.trailing, .leading] : [.center], gaps: aligned ? [0, 36] : [0],
                style: .display))
    }

    // MARK: Tokens

    /// 读取下一个词法单元，跳过数学模式下的空白与 `%` 注释。
    mutating func next() -> Token {
        skipSpace()
        guard index < characters.count else { return .end }
        let character = characters[index]
        index += 1
        switch character {
        case "{": return .open
        case "}": return .close
        case "^": return .superscript
        case "_": return .subscript
        case "&": return .alignment
        case "\\": return command()
        default: return .character(character)
        }
    }

    /// 预读下一个词法单元而不推进索引。
    func peek() -> Token {
        var copy = self
        return copy.next()
    }

    /// 解析反斜杠后的命令名：连续字母构成名字，否则取单字符。
    private mutating func command() -> Token {
        guard index < characters.count else { return .command("") }
        let letters = characters[index...].prefix(while: { $0.isASCII && $0.isLetter })
        guard letters.isEmpty else {
            index += letters.count
            return .command(String(letters))
        }
        index += 1
        return .command(String(characters[index - 1]))
    }

    /// 数学模式忽略空格，`%` 则注释到行尾。
    private mutating func skipSpace() {
        while index < characters.count {
            if characters[index].isWhitespace {
                index += 1
            } else if characters[index] == "%" {
                while index < characters.count, !characters[index].isNewline { index += 1 }
            } else {
                return
            }
        }
    }

    // MARK: Lists

    /// 解析直到给定终止符为止的节点列表，同时限制最大嵌套深度。
    mutating func list(until stop: Stop) throws -> [MathNode] {
        depth += 1
        defer { depth -= 1 }
        guard depth <= MathNode.maximumDepth else { throw Failure.unsupported }
        var nodes: [MathNode] = []
        while true {
            let start = index
            let token = next()
            switch token {
            case .end:
                guard stop == .end || stop == .cell else { throw Failure.unsupported }
                index = start
                return nodes
            case .close:
                guard stop == .brace else { throw Failure.unsupported }
                return nodes
            case .character("]") where stop == .bracket:
                return nodes
            case .alignment, .command("\\"), .command("cr"):
                guard stop == .cell else { throw Failure.unsupported }
                index = start
                return nodes
            case .command("end"):
                guard stop == .cell else { throw Failure.unsupported }
                index = start
                return nodes
            case .command("right"):
                guard stop == .right else { throw Failure.unsupported }
                return nodes
            case .superscript, .subscript:
                try attachScript(token == .superscript, to: &nodes)
            case .character("'"):
                try attachPrimes(to: &nodes)
            case .command("limits"), .command("nolimits"):
                try setLimits(token == .command("limits"), on: &nodes)
            default:
                if case .command(let name) = token, let style = Self.styles[name] {
                    return nodes + [.styled(style, .row(try list(until: stop)))]
                }
                nodes.append(try atom(token))
            }
        }
    }

    /// 样式切换命令到排版样式的映射。
    private static let styles: [String: MathNode.Style] = [
        "displaystyle": .display, "textstyle": .text, "scriptstyle": .script,
        "scriptscriptstyle": .scriptScript
    ]

    /// 解析若干行单元格，直到 `\end` 或公式结束。
    mutating func cells() throws -> [[[MathNode]]] {
        var rows: [[[MathNode]]] = [[]]
        while true {
            rows[rows.count - 1].append(try list(until: .cell))
            switch next() {
            case .alignment: continue
            case .command("\\"), .command("cr"):
                if case .character("[") = peek() { try skipOptional() }
                rows.append([])
            case .end: return trimmingEmptyLastRow(rows)
            case .command("end"):
                index -= "\\end".count
                return trimmingEmptyLastRow(rows)
            default: throw Failure.unsupported
            }
        }
    }

    /// `\end` 前的结尾 `\\` 否则会画出一个空的末行。
    private func trimmingEmptyLastRow(_ rows: [[[MathNode]]]) -> [[[MathNode]]] {
        guard rows.count > 1, let last = rows.last, last.allSatisfy(\.isEmpty) else { return rows }
        return Array(rows.dropLast())
    }

    // MARK: Scripts

    /// 把解析出的脚本挂到前一个节点上；基已有同类脚本时视为重复并报错。
    private mutating func attachScript(_ isSuperscript: Bool, to nodes: inout [MathNode]) throws {
        let script = try argument()
        let base = nodes.popLast() ?? .row([])
        guard case .scripts(let inner, let superscript, let `subscript`) = base else {
            nodes.append(
                isSuperscript
                    ? .scripts(base: base, superscript: script, subscript: nil)
                    : .scripts(base: base, superscript: nil, subscript: script))
            return
        }
        if isSuperscript {
            guard superscript == nil else { throw Failure.unsupported }
            nodes.append(.scripts(base: inner, superscript: script, subscript: `subscript`))
        } else {
            guard `subscript` == nil else { throw Failure.unsupported }
            nodes.append(.scripts(base: inner, superscript: superscript, subscript: script))
        }
    }

    /// `f''` 即 `f^{\prime\prime}`；紧跟其后的 `^` 会并入同一个上标。
    private mutating func attachPrimes(to nodes: inout [MathNode]) throws {
        var primes: [MathNode] = [.symbol("′", .ord)]
        while index < characters.count, characters[index] == "'" {
            index += 1
            primes.append(.symbol("′", .ord))
        }
        if peek() == .superscript {
            _ = next()
            primes.append(try argument())
        }
        let base = nodes.popLast() ?? .row([])
        var `subscript`: MathNode?
        var inner = base
        if case .scripts(let scripted, .none, let existing) = base {
            inner = scripted
            `subscript` = existing
        }
        nodes.append(.scripts(base: inner, superscript: .row(primes), subscript: `subscript`))
    }

    /// 依据 `\limits` / `\nolimits` 调整大运算符或运算符名的上下限摆放。
    private func setLimits(_ limits: Bool, on nodes: inout [MathNode]) throws {
        switch nodes.popLast() {
        case .largeOperator(let character, _): nodes.append(.largeOperator(character, limits: limits))
        case .operatorName(let text, _): nodes.append(.operatorName(text, limits: limits))
        default: throw Failure.unsupported
        }
    }

    // MARK: Atoms

    /// 单个脚本、分式部分或命令参数：一个花括号分组或单个原子。
    mutating func argument() throws -> MathNode {
        let token = next()
        switch token {
        case .open: return .row(try list(until: .brace))
        case .end, .close, .alignment, .superscript, .subscript: throw Failure.unsupported
        default: return try atom(token)
        }
    }

    /// 解析单个原子：花括号分组、普通字符或命令。
    private mutating func atom(_ token: Token) throws -> MathNode {
        switch token {
        case .open: return .row(try list(until: .brace))
        case .character(let character): return try typed(character)
        case .command(let name): return try command(name)
        default: throw Failure.unsupported
        }
    }

    /// 把直接键入的字符转成符号节点，按当前字母表套用样式并判定原子类型。
    private func typed(_ character: Character) throws -> MathNode {
        if character == "~" { return .space(6) }
        if "#$^_&".contains(character) { throw Failure.unsupported }
        if character.isASCII, character.isLetter || character.isNumber {
            let styled = MathSymbolCatalog.styled(character, in: alphabet)
            return .symbol(styled, .ord)
        }
        return .symbol(MathSymbolCatalog.drawn(character), MathSymbolCatalog.kind(of: character))
    }

    /// 解析命名命令：先查符号、大运算符、函数、空格、重音、字母表与大界符，最后回退到结构命令。
    private mutating func command(_ name: String) throws -> MathNode {
        if let symbol = MathSymbolCatalog.symbol(named: name) {
            let character = symbol.character
            let isGreek = character.unicodeScalars.first.map { (0x3B1...0x3F5).contains($0.value) }
            let drawn =
                isGreek == true && character.count == 1
                ? MathSymbolCatalog.styled(Character(character), in: alphabet) : character
            return .symbol(drawn, symbol.kind)
        }
        if let operation = MathSymbolCatalog.largeOperators[name] {
            return .largeOperator(operation.character, limits: operation.limits)
        }
        if let function = MathSymbolCatalog.functions[name] {
            return .operatorName(function.text, limits: function.limits)
        }
        if let space = Self.spaces[name] { return .space(space) }
        if let accent = MathSymbolCatalog.accents[name] {
            return .accent(try argument(), mark: accent.mark, wide: accent.wide)
        }
        if let alphabet = Self.alphabets[name] { return try styled(alphabet) }
        if let size = Self.bigSizes[name] {
            return .delimiter(try delimiter(), size: size.size, size.kind)
        }
        return try structure(name)
    }

    /// 解析分式、根式、fenced、文本、上下堆叠等结构性命令。
    private mutating func structure(_ name: String) throws -> MathNode {
        switch name {
        case "frac", "dfrac", "tfrac", "cfrac":
            let style: MathNode.Style? =
                name == "dfrac" || name == "cfrac" ? .display : name == "tfrac" ? .text : nil
            return .fraction(numerator: try argument(), denominator: try argument(), rule: true, style: style)
        case "binom", "dbinom", "tbinom":
            let style: MathNode.Style? = name == "dbinom" ? .display : name == "tbinom" ? .text : nil
            let fraction = MathNode.fraction(
                numerator: try argument(), denominator: try argument(), rule: false, style: style)
            return .fenced(open: "(", body: fraction, close: ")")
        case "sqrt":
            var degree: MathNode?
            if case .character("[") = peek() {
                _ = next()
                degree = .row(try list(until: .bracket))
            }
            return .radical(try argument(), degree: degree)
        case "left":
            let open = try delimiter()
            let body = try list(until: .right)
            return .fenced(open: open, body: .row(body), close: try delimiter())
        case "text", "textrm", "textnormal", "mbox", "textit", "textbf", "textsf", "texttt", "mathnormal":
            return .text(try rawText(), .ord)
        case "operatorname":
            let star = skipStar()
            return .operatorName(try rawText(), limits: star)
        case "overline": return .overline(try argument())
        case "underline": return .underline(try argument())
        case "boxed", "fbox": return .boxed(try argument())
        case "overset", "stackrel":
            let over = try argument()
            return .stack(base: try argument(), over: over, under: nil)
        case "underset":
            let under = try argument()
            return .stack(base: try argument(), over: nil, under: under)
        case "not": return try negated()
        case "bmod": return .text("mod", .bin)
        case "pmod":
            let body = try argument()
            return .row([
                .space(18), .symbol("(", .open), .operatorName("mod", limits: false), .space(6), body,
                .symbol(")", .close)
            ])
        case "mod":
            return .row([.space(18), .operatorName("mod", limits: false), .space(6)])
        case "begin": return try environment()
        case "color":
            _ = try rawText()
            return .space(0)
        case "textcolor", "colorbox":
            _ = try rawText()
            return try argument()
        case "nonumber", "notag": return .space(0)
        case "label", "tag":
            _ = skipStar()
            _ = try rawText()
            return .space(0)
        default: throw Failure.unsupported
        }
    }

    /// 空格命令到 mu 间距值的映射。
    private static let spaces: [String: Double] = [
        ",": 3, "thinspace": 3, ":": 4, ">": 4, "medspace": 4, ";": 5, "thickspace": 5, "!": -3,
        "negthinspace": -3, " ": 6, "quad": 18, "qquad": 36, "enspace": 9
    ]

    /// 字母表命令到对应变体的映射。
    private static let alphabets: [String: MathNode.Alphabet] = [
        "mathrm": .upright, "mathup": .upright, "mathit": .italic, "mathbf": .bold,
        "boldsymbol": .boldItalic, "bm": .boldItalic, "mathbb": .doubleStruck, "mathcal": .script,
        "mathscr": .script, "mathfrak": .fraktur, "mathsf": .sansSerif, "mathtt": .monospace
    ]

    /// 大界符命令到放大档位与原子类型的映射。
    private static let bigSizes: [String: (size: Int, kind: MathNode.Kind)] = [
        "big": (1, .ord), "Big": (2, .ord), "bigg": (3, .ord), "Bigg": (4, .ord),
        "bigl": (1, .open), "Bigl": (2, .open), "biggl": (3, .open), "Biggl": (4, .open),
        "bigr": (1, .close), "Bigr": (2, .close), "biggr": (3, .close), "Biggr": (4, .close),
        "bigm": (1, .rel), "Bigm": (2, .rel), "biggm": (3, .rel), "Biggm": (4, .rel)
    ]

    /// 临时切换字母表解析其参数，解析完成后恢复原字母表。
    private mutating func styled(_ next: MathNode.Alphabet) throws -> MathNode {
        let previous = alphabet
        alphabet = next
        defer { alphabet = previous }
        return try argument()
    }

    /// `\left`、`\right` 与 `\big` 所定尺寸的对象：一个括号字符或具名定界符。
    private mutating func delimiter() throws -> String {
        switch next() {
        case .character("."): return ""
        case .character("<"): return "⟨"
        case .character(">"): return "⟩"
        case .character(let character) where "()[]|/".contains(character): return String(character)
        case .command(let name):
            guard let character = MathSymbolCatalog.delimiters[name] else { throw Failure.unsupported }
            return character
        default: throw Failure.unsupported
        }
    }

    /// 解析 `\not` 之后的符号，优先使用 Unicode 预组合的否定形式。
    private mutating func negated() throws -> MathNode {
        guard case .symbol(let character, let kind) = try argument() else { throw Failure.unsupported }
        return .symbol(MathSymbolCatalog.negations[character] ?? character + "\u{0338}", kind)
    }

    /// 若当前位置是星号则消费它并返回 true，对应带 `*` 的命令变体。
    private mutating func skipStar() -> Bool {
        guard index < characters.count, characters[index] == "*" else { return false }
        index += 1
        return true
    }

    /// 跳过方括号形式的可选参数。
    private mutating func skipOptional() throws {
        _ = next()
        while index < characters.count, characters[index] != "]" { index += 1 }
        guard index < characters.count else { throw Failure.unsupported }
        index += 1
    }

    /// 把一个花括号分组按散文方式读取：保留空格，只处理句子所需的转义。
    private mutating func rawText() throws -> String {
        guard next() == .open else { throw Failure.unsupported }
        var text = ""
        var nesting = 0
        while index < characters.count {
            let character = characters[index]
            index += 1
            switch character {
            case "{": nesting += 1
            case "}":
                if nesting == 0 { return text }
                nesting -= 1
            case "\\":
                guard index < characters.count else { throw Failure.unsupported }
                let escaped = characters[index]
                index += 1
                guard "{}$&%#_ ,;".contains(escaped) else { throw Failure.unsupported }
                text.append(",;".contains(escaped) ? " " : escaped)
            case "$": throw Failure.unsupported
            default: text.append(character.isNewline ? " " : character)
            }
        }
        throw Failure.unsupported
    }

    // MARK: Environments

    /// 解析 `\begin{…}…\end{…}` 环境，按环境名决定表格布局与外层括号。
    private mutating func environment() throws -> MathNode {
        let name = try rawText()
        let layout = try Self.tableLayout(name, columns: try columnSpec(for: name))
        let rows = try cells()
        guard next() == .command("end"), try rawText() == name else { throw Failure.unsupported }
        var styledRows = rows.map { $0.map(MathNode.row) }
        if layout.alignments == [.trailing, .leading] {
            // aligned 的右半部分以 `{}` 开头，因此 `&=` 会像 TeX 那样为关系符留出间距。
            styledRows = rows.map { row in
                row.enumerated().map { column, cell in
                    .row(column % 2 == 1 ? [.row([])] + cell : cell)
                }
            }
        }
        let table = MathNode.table(
            .init(rows: styledRows, alignments: layout.alignments, gaps: layout.gaps, style: layout.style))
        guard let fences = Self.fences[name] else { return table }
        return .fenced(open: fences.open, body: table, close: fences.close)
    }

    /// 需要自动包裹括号的环境到开闭定界符的映射。
    private static let fences: [String: (open: String, close: String)] = [
        "pmatrix": ("(", ")"), "bmatrix": ("[", "]"), "Bmatrix": ("{", "}"), "vmatrix": ("|", "|"),
        "Vmatrix": ("‖", "‖"), "cases": ("{", ""), "dcases": ("{", ""), "rcases": ("", "}")
    ]

    /// 按环境名返回列对齐方式、列间距与排版样式。
    private static func tableLayout(
        _ name: String, columns: [MathNode.Table.Alignment]?
    ) throws
        -> (alignments: [MathNode.Table.Alignment], gaps: [Double], style: MathNode.Style)
    {
        switch name {
        case "matrix", "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix":
            return ([.center], [18], .text)
        case "smallmatrix": return ([.center], [9], .script)
        case "cases", "rcases": return ([.leading], [18], .text)
        case "dcases": return ([.leading], [18], .display)
        case "aligned", "align", "align*", "split", "alignat", "alignat*", "flalign", "flalign*":
            return ([.trailing, .leading], [0, 36], .display)
        case "gathered", "gather", "gather*", "equation", "equation*", "multline", "multline*":
            return ([.center], [0], .display)
        case "array":
            guard let columns else { throw Failure.unsupported }
            return (columns, [18], .text)
        default: throw Failure.unsupported
        }
    }

    /// `array` 的 `{lcr}` 列格式；竖线规则被丢弃而不报错。
    private mutating func columnSpec(for name: String) throws -> [MathNode.Table.Alignment]? {
        guard name == "array" else {
            if name.hasPrefix("alignat") { _ = try rawText() }
            return nil
        }
        let columns = try rawText().compactMap { character -> MathNode.Table.Alignment? in
            switch character {
            case "l": .leading
            case "c": .center
            case "r": .trailing
            default: nil
            }
        }
        guard !columns.isEmpty else { throw Failure.unsupported }
        return columns
    }
}
