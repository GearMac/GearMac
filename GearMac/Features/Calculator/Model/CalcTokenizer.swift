// 文件职责：把用户输入的原始字符串切分为 `CalcToken` 序列，处理进制字面量、缩写数、单位/货币复合词与多字符运算符。
// 分层：Model；纯字符串扫描，不 import AppKit/SwiftUI，不产生副作用。
import Foundation

/// 把原始输入字符串切分为 `CalcToken` 序列。
enum CalcTokenizer {
    /// 遇到无法作为计算器输入的字符时返回 nil——含义是「不是一道计算」，而非出错。
    static func tokenize(_ input: String) -> [CalcToken]? {
        let chars = Array(input.unicodeScalars)
        var tokens: [CalcToken] = []
        tokens.reserveCapacity(chars.count / 2 + 1)
        var i = 0
        var depth = 0
        var functionDepth: Int?

        func isDigit(_ ch: Unicode.Scalar) -> Bool { (48...57).contains(ch.value) }

        while i < chars.count {
            let ch = chars[i]
            if ch.isWhitespace {
                i += 1
                continue
            }

            // 进制字面量要求前缀后至少 1 位数字，否则 "0" 按普通数字处理。
            if ch == "0", i + 2 < chars.count, let base = literalBase(chars[i + 1]) {
                let start = i + 2
                var end = start
                while end < chars.count, chars[end].isASCII && Character(chars[end]).isHexDigit { end += 1 }
                if end > start,
                    let value = UInt64(
                        String(String.UnicodeScalarView(chars[start..<end])), radix: base.rawValue)
                {
                    tokens.append(.intLiteral(value, base: base))
                    i = end
                    continue
                }
            }

            if isDigit(ch) || (ch == "." && i + 1 < chars.count && isDigit(chars[i + 1])) {
                var text = ""
                var seenDot = false
                while i < chars.count {
                    let c = chars[i]
                    if isDigit(c) {
                        text.unicodeScalars.append(c)
                    } else if c == "," && functionDepth == nil && i + 1 < chars.count && isDigit(chars[i + 1])
                    {
                        // 数字之间的分组符——跳过
                    } else if c == "." && !seenDot {
                        seenDot = true
                        text.unicodeScalars.append(c)
                    } else {
                        break
                    }
                    i += 1
                }
                // 仅当指数紧贴尾数时才识别；写成 `2 e` 仍表示 2 × e。
                var isShorthand = false
                if i < chars.count, chars[i] == "e" || chars[i] == "E" {
                    var digits = i + 1
                    if digits < chars.count, chars[digits] == "+" || chars[digits] == "-" {
                        digits += 1
                    }
                    var end = digits
                    while end < chars.count, isDigit(chars[end]) { end += 1 }
                    if end > digits {
                        text += String(String.UnicodeScalarView(chars[i..<end]))
                        i = end
                        isShorthand = true
                    }
                }
                // 溢出的字面量（"1e400"）不算计算器输入，因此不出卡片。
                guard let value = Double(text), value.isFinite else { return nil }
                // 紧贴的 `k` 表示 ×1,000；有空格则仍是开尔文，而 `10kg` 仍按单位处理。
                if i < chars.count, chars[i] == "k" || chars[i] == "K", isCompactSuffix(chars, i) {
                    let scaled = value * 1_000
                    guard scaled.isFinite else { return nil }
                    tokens.append(.compactNumber(scaled))
                    i += 1
                } else if let magnitude = magnitudeWord(chars, after: i) {
                    let scaled = value * magnitude.scale
                    guard scaled.isFinite else { return nil }
                    tokens.append(.compactNumber(scaled))
                    i = magnitude.end
                } else if isShorthand {
                    tokens.append(.compactNumber(value))
                } else {
                    tokens.append(.number(value))
                }
                continue
            }

            if ch == "x" || ch == "X", isMultiplicationX(chars, at: i, previous: tokens.last) {
                tokens.append(.op(.multiply))
                i += 1
                continue
            }

            if ch.isLetter || ch == "°" {
                let start = i
                while i < chars.count, chars[i].isLetter { i += 1 }
                var text = String(String.UnicodeScalarView(chars[start..<i]))
                if i < chars.count, isDigit(chars[i]) {
                    let prefix = text.lowercased()
                    if CalcUnits.byName[prefix] == nil, CalcCurrency.byName[prefix] != nil {
                        tokens.append(.ident(prefix))
                        continue
                    }
                }
                while i < chars.count {
                    let c = chars[i]
                    if c.isLetter || c.isCombiningMark || c == "°" || isDigit(c) {
                        text.unicodeScalars.append(c)
                    } else if c == "²" {
                        text.append("2")
                    } else if c == "³" {
                        text.append("3")
                    } else {
                        break
                    }
                    i += 1
                }
                if let unit = compoundUnit(chars, after: i, prefix: text) {
                    tokens.append(.ident(unit.name))
                    i = unit.end
                } else {
                    tokens.append(.ident(CalcUnits.byName[text] != nil ? text : text.lowercased()))
                }
                continue
            }

            // 货币符号是标点，先归一化为 ISO 代码：`€20 to gbp` 分词为 `20 eur to gbp`。
            if let code = CurrencyData.signs[Character(ch)] {
                tokens.append(.ident(code))
                i += 1
                continue
            }

            // "**" 是 Python/JS/shell 中幂运算的写法，与 "^" 是同一运算符。
            if ch == "*", i + 1 < chars.count, chars[i + 1] == "*" {
                tokens.append(.op(.power))
                i += 2
                continue
            }

            if i + 1 < chars.count {
                let combined: CalcOperator? =
                    switch (ch, chars[i + 1]) {
                    case ("<", "<"): .shiftLeft
                    case (">", ">"): .shiftRight
                    case ("=", "="): .equal
                    case ("!", "="): .notEqual
                    case ("<", "="): .lessEqual
                    case (">", "="): .greaterEqual
                    default: nil
                    }
                if let op = combined {
                    tokens.append(.op(op))
                    i += 2
                    continue
                }
            }
            if ch == "(" {
                if functionDepth == nil, case .ident(let name)? = tokens.last, CalcMath.isFunction(name) {
                    functionDepth = depth
                }
                depth += 1
            } else if ch == ")" {
                depth -= 1
                if functionDepth == depth { functionDepth = nil }
            }
            switch ch {
            case "+", "(", ")", "!", "%", "^", "&", "|", "~", "<", ">", "≤", "≥", "≠", "⊻":
                guard let op = CalcOperator(rawValue: Character(ch)) else { return nil }
                tokens.append(.op(op))
            case ",":
                tokens.append(.comma)
            case "*", "×":
                tokens.append(.op(.multiply))
            case "/", "÷":
                tokens.append(.op(.divide))
            case "−":
                tokens.append(.op(.subtract))
            case "-":
                if i + 1 < chars.count, chars[i + 1] == ">" {
                    tokens.append(.arrow)
                    i += 1
                } else {
                    tokens.append(.op(.subtract))
                }
            case "→":
                tokens.append(.arrow)
            case "=":
                // 容忍末尾的 "="（"2+2="）；出现在其他位置则不算计算器输入。
                guard i == chars.count - 1 else { return nil }
            default:
                return nil
            }
            i += 1
        }
        return tokens
    }

    /// 把进制前缀字符映射为进制；非前缀返回 nil。
    private static func literalBase(_ prefix: Unicode.Scalar) -> CalcNumberBase? {
        switch prefix {
        case "x", "X": .hexadecimal
        case "b", "B": .binary
        case "o", "O": .octal
        default: nil
        }
    }

    /// 判断 `x`/`X` 是否应作为乘号：前一个 token 必须能结束操作数，且后方接着可继续的输入。
    private static func isMultiplicationX(
        _ chars: [Unicode.Scalar], at index: Int, previous: CalcToken?
    ) -> Bool {
        guard index > 0, !chars[index - 1].isLetter, let previous, endsOperand(previous) else {
            return false
        }
        if index + 2 < chars.count,
            ["o", "O"].contains(chars[index + 1]),
            ["r", "R"].contains(chars[index + 2]),
            index + 3 == chars.count || !chars[index + 3].isLetter
        {
            return false
        }
        let attached = !chars[index - 1].isWhitespace
        var next = index + 1
        while next < chars.count, chars[next].isWhitespace { next += 1 }
        guard next < chars.count else { return !attached }
        switch chars[next] {
        case ")", "!", "%", "^", "/", ",", "=", "*", "×", "÷", "−", "→":
            return false
        default:
            return true
        }
    }

    /// 判断某 token 能否作为操作数结尾（用于判定前缀 `x` 是否为乘号）。
    private static func endsOperand(_ token: CalcToken) -> Bool {
        switch token {
        case .number, .compactNumber, .intLiteral:
            true
        case .op(let op):
            op == .close || op == .factorial || op == .percent
        case .ident(let name):
            !["to", "in", "of", "mod", "power", "and"].contains(name)
        case .arrow, .comma:
            false
        }
    }

    /// 只有表中能解析的拼写才合并，使 `6/2(1+2)` 仍按除法处理。
    private static func compoundUnit(
        _ chars: [Unicode.Scalar], after index: Int, prefix: String
    ) -> (name: String, end: Int)? {
        guard index < chars.count, chars[index] == "/" || chars[index].isWhitespace else { return nil }
        let separator = chars[index] == "/" ? "/" : " "
        var rightStart = index + 1
        while rightStart < chars.count, chars[rightStart].isWhitespace { rightStart += 1 }
        var end = rightStart
        while end < chars.count, chars[end].isLetter || chars[end].isNumber { end += 1 }
        guard end > rightStart else { return nil }
        let spelling = (prefix + separator + String(String.UnicodeScalarView(chars[rightStart..<end])))
            .replacingOccurrences(of: "²", with: "2")
            .replacingOccurrences(of: "³", with: "3")
        let name = CalcUnits.byName[spelling] != nil ? spelling : spelling.lowercased()
        guard CalcUnits.byName[name] != nil else { return nil }
        return (name, end)
    }

    /// 仅支持短级差：引擎读的是规范英语，其中 billion 为 10⁹。
    private static let magnitudes: [String: Double] = ["thousand": 1e3, "million": 1e6, "billion": 1e9]

    /// 字面量后跟完整数量级词（如 `13 million`）时的缩放系数，以及该词结束位置。
    private static func magnitudeWord(
        _ chars: [Unicode.Scalar], after index: Int
    ) -> (scale: Double, end: Int)? {
        var start = index
        while start < chars.count, chars[start].isWhitespace { start += 1 }
        var end = start
        while end < chars.count, chars[end].isLetter { end += 1 }
        guard end > start else { return nil }
        if end < chars.count, chars[end].isNumber || chars[end].isCombiningMark { return nil }
        guard let scale = magnitudes[String(String.UnicodeScalarView(chars[start..<end])).lowercased()]
        else { return nil }
        return (scale, end)
    }

    /// 判断 `index` 处的 `k` 是千位后缀，而非开尔文或单位词的开头。
    private static func isCompactSuffix(_ chars: [Unicode.Scalar], _ index: Int) -> Bool {
        let next = index + 1
        guard next < chars.count else { return true }
        if isTemperatureConversion(chars, from: next) { return false }
        guard chars[next].isLetter else { return true }

        var end = next
        while end < chars.count, chars[end].isLetter { end += 1 }
        return CalcCurrency.byName[String(String.UnicodeScalarView(chars[next..<end])).lowercased()] != nil
    }

    /// 判断剩余部分是否读作向温度单位的转换，若是则把 `k` 保留为开尔文。
    private static func isTemperatureConversion(_ chars: [Unicode.Scalar], from index: Int) -> Bool {
        let remainder = String(String.UnicodeScalarView(chars[index...]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        for connector in ["to", "in", "->", "→"] where remainder.hasPrefix(connector) {
            let target = remainder.dropFirst(connector.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if CalcUnits.byName[target]?.category == .temperature { return true }
        }
        return false
    }
}

/// 为分词器补充的 Unicode 标量分类工具。
private extension Unicode.Scalar {
    /// 是否为字母：ASCII 用编码区间判断，其余交给 `CharacterSet.letters`。
    var isLetter: Bool {
        if isASCII { return (65...90).contains(value) || (97...122).contains(value) }
        return CharacterSet.letters.contains(self)
    }

    /// 是否为空白字符。
    var isWhitespace: Bool { properties.isWhitespace }
    /// 是否具有数值属性（用于 `²`/`³` 等）。
    var isNumber: Bool { properties.numericType != nil }
    /// 是否为组合标记（非间距标记或间距标记）。
    var isCombiningMark: Bool {
        properties.generalCategory == .nonspacingMark || properties.generalCategory == .spacingMark
    }
}
