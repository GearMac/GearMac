// 文件职责：定义数字格式样式与分隔符规则，并在本地化写法（如逗号作小数点）与引擎内部使用的规范英文写法之间做双向转换。
// 分层：Model；只依赖 Foundation（见 docs/features/calculator.md），不 import AppKit/SwiftUI。
import Foundation

/// 计算器采用哪种数字格式：跟随 Mac 的区域设置，还是始终按英文读写。
enum CalcNumberStyle: String, CaseIterable, Identifiable, Sendable {
    case system
    case english

    var id: String { rawValue }

    /// 英文标题；保留给尚未迁移的调用点，界面请改用 `localizedTitle(_:)`。
    var title: String {
        switch self {
        case .system: "System"
        case .english: "English"
        }
    }

    /// 按界面语言给出的样式名。
    func localizedTitle(_ language: AppLanguage) -> String {
        L10n.string(
            self == .system ? CalculatorKey.numberStyleSystem : CalculatorKey.numberStyleEnglish,
            language: language)
    }
}

/// 用户实际输入时使用的分隔符；引擎内部只读英文写法（见 docs/features/calculator.md）。
struct CalcNumberFormat: Equatable, Sendable {
    let decimalSeparator: Unicode.Scalar
    /// 当数字不写分组符时为 nil。
    let groupingSeparator: Unicode.Scalar?

    /// 英文格式：点作小数点、逗号作分组符，也是引擎内部的规范写法。
    static let english = CalcNumberFormat(decimal: ".", grouping: ",")

    /// macOS 可能提供的分组分隔符中，绝不会被误认为计算器语法的那几种。
    private static let groupingScalars: Set<Unicode.Scalar> = [
        ".", ",", "'", "\u{2019}", "\u{00A0}", "\u{202F}", "\u{2009}"
    ]

    private init(decimal: Unicode.Scalar, grouping: Unicode.Scalar?) {
        decimalSeparator = decimal
        groupingSeparator = grouping
    }

    /// 对小数字符是规范语法无法表达的情况（如阿拉伯语 `٫`）返回 nil。
    init?(decimalSeparator: String, groupingSeparator: String?) {
        guard let decimal = Self.single(decimalSeparator), decimal == "." || decimal == "," else {
            return nil
        }
        let grouping = groupingSeparator.flatMap(Self.single).flatMap {
            $0 != decimal && Self.groupingScalars.contains($0) ? $0 : nil
        }
        self.init(decimal: decimal, grouping: grouping)
    }

    private static func single(_ text: String) -> Unicode.Scalar? {
        let scalars = text.unicodeScalars
        return scalars.count == 1 ? scalars.first : nil
    }

    /// 小数点用逗号时无法再用逗号分隔参数，因此改用 `;`，与电子表格一致。
    var argumentSeparator: Character { decimalSeparator == "," ? ";" : "," }

    private var usesDecimalComma: Bool { decimalSeparator == "," }

    // MARK: - Input

    /// 返回规范语法的查询；若其中某个数字有多种读法，则返回 nil。
    func canonical(_ query: String) -> String? {
        guard self != .english else { return query }
        let scalars = Array(query.unicodeScalars)
        var output = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if usesDecimalComma, scalar == ";" {
                // 加空格，避免规范写法里的逗号被当作两个数字之间的分组符。
                output.append(contentsOf: ", ".unicodeScalars)
                index += 1
                continue
            }
            guard startsNumber(scalars, at: index, decimal: decimalSeparator) else {
                output.append(scalar)
                index += 1
                continue
            }
            let end = numberEnd(
                scalars, from: index, decimal: decimalSeparator, grouping: groupingSeparator)
            let run = scalars[index..<end]
            if Self.isClockFragment(scalars, run: index..<end) {
                output.append(contentsOf: run)
            } else {
                guard let number = canonicalNumber(run) else { return nil }
                output.append(contentsOf: number)
            }
            index = end
        }
        return String(output)
    }

    /// 把一段输入数字转成规范写法：去掉分组符、将本地小数点统一为点；不是单一数字时返回 nil。
    private func canonicalNumber(_ run: ArraySlice<Unicode.Scalar>) -> [Unicode.Scalar]? {
        let parts = run.split(separator: decimalSeparator, omittingEmptySubsequences: false)
        // 当点是小数点时，`19.2.27` 仍按英文读法作为日期处理。
        if parts.count > 2 {
            return !usesDecimalComma && !run.contains(where: isGrouping) ? Array(run) : nil
        }
        if parts.count == 2, parts[1].contains(where: isGrouping) { return nil }
        let groups = parts[0].split(
            omittingEmptySubsequences: false, whereSeparator: isGrouping)
        if groups.count > 1, !Self.isValidGrouping(groups) {
            // 点分隔日期的点在本地是分组点，而合法分组不会出现不足三位的短分组。
            let isDottedDate = groupingSeparator == "." && parts.count == 1 && groups.count > 2
            return isDottedDate ? Array(run) : nil
        }
        var number = groups.flatMap { $0 }
        if parts.count == 2 {
            number.append(".")
            number.append(contentsOf: parts[1])
        }
        return number
    }

    private func isGrouping(_ scalar: Unicode.Scalar) -> Bool { scalar == groupingSeparator }

    // MARK: - Output

    /// 把答案中的数字转成本地格式；其他文本（含逗号）保持原样。
    func localized(_ text: String) -> String {
        rewrite(text, separatingArguments: false)
    }

    /// 把回显表达式中的规范参数逗号也转成本格式的参数分隔符。
    func localizedExpression(_ text: String) -> String {
        rewrite(text, separatingArguments: true)
    }

    /// 把整个计算结果转成本格式：数字与表达式本地化，错误载荷保持不变。
    func localized(_ result: CalcResult) -> CalcResult {
        guard self != .english else { return result }
        let payload: CalcResult.Payload
        switch result.payload {
        case .value(let display, let copyText):
            payload = .value(display: localized(display), copyText: localized(copyText))
        case .error:
            payload = result.payload
        }
        return CalcResult(
            expression: localizedExpression(result.expression), sourceBadge: result.sourceBadge,
            targetBadge: result.targetBadge, payload: payload, canChain: result.canChain)
    }

    /// 按本格式重写文本中的数字；`separatingArguments` 决定是否同时转换参数分隔符。
    private func rewrite(_ text: String, separatingArguments: Bool) -> String {
        guard self != .english else { return text }
        let scalars = Array(text.unicodeScalars)
        var output = String.UnicodeScalarView()
        var depth = 0
        // 调用括号内的每个逗号都用于分隔参数，与 `CalcTokenizer` 的读法一致。
        var functionDepth: Int?
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            guard startsNumber(scalars, at: index, decimal: ".") else {
                if scalar == "(" {
                    if functionDepth == nil, Self.namesFunction(scalars, before: index) {
                        functionDepth = depth
                    }
                    depth += 1
                } else if scalar == ")" {
                    depth -= 1
                    if functionDepth == depth { functionDepth = nil }
                }
                if separatingArguments, usesDecimalComma, scalar == "," {
                    output.append(contentsOf: argumentSeparator.unicodeScalars)
                } else {
                    output.append(scalar)
                }
                index += 1
                continue
            }
            let end = numberEnd(
                scalars, from: index, decimal: ".", grouping: functionDepth == nil ? "," : nil)
            let run = scalars[index..<end]
            if !Self.isClockFragment(scalars, run: index..<end), let number = localizedNumber(run) {
                output.append(contentsOf: number)
            } else {
                output.append(contentsOf: run)
            }
            index = end
        }
        return String(output)
    }

    /// 当该片段不是一个完整的规范数字时返回 nil，使点分隔日期保持原样。
    private func localizedNumber(_ run: ArraySlice<Unicode.Scalar>) -> [Unicode.Scalar]? {
        let parts = run.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts.count == 1 || !parts[1].contains(",") else { return nil }
        let groups = parts[0].split(separator: ",", omittingEmptySubsequences: false)
        guard groups.count == 1 || Self.isValidGrouping(groups) else { return nil }
        var number: [Unicode.Scalar] = []
        for (index, group) in groups.enumerated() {
            if index > 0, let groupingSeparator { number.append(groupingSeparator) }
            number.append(contentsOf: group)
        }
        if parts.count == 2 {
            number.append(decimalSeparator)
            number.append(contentsOf: parts[1])
        }
        return number
    }

    // MARK: - Scanning

    /// 判定某位置是否为数字开头：一个数字，或前面没有数字的小数字符（如 `,5`）。
    private func startsNumber(
        _ scalars: [Unicode.Scalar], at index: Int, decimal: Unicode.Scalar
    ) -> Bool {
        let scalar = scalars[index]
        if Self.isDigit(scalar) { return true }
        guard scalar == decimal, index + 1 < scalars.count, Self.isDigit(scalars[index + 1]) else {
            return false
        }
        return index == 0 || !Self.isDigit(scalars[index - 1])
    }

    /// 扫描数字及其间的分隔符；末尾的小数字符会保留，使 `2,` 仍能给出结果。
    private func numberEnd(
        _ scalars: [Unicode.Scalar], from start: Int, decimal: Unicode.Scalar,
        grouping: Unicode.Scalar?
    ) -> Int {
        var end = start
        while end < scalars.count {
            let scalar = scalars[end]
            if Self.isDigit(scalar) {
                end += 1
                continue
            }
            guard scalar == decimal || scalar == grouping else { break }
            let next = end + 1
            if next < scalars.count, Self.isDigit(scalars[next]) {
                end = next
            } else {
                if scalar == decimal, next == scalars.count, end > start { end = next }
                break
            }
        }
        return end
    }

    /// `00:18:00.123` 属于时钟时刻，其小数秒始终用点书写。
    private static func isClockFragment(_ scalars: [Unicode.Scalar], run: Range<Int>) -> Bool {
        (run.lowerBound > 0 && scalars[run.lowerBound - 1] == ":")
            || (run.upperBound < scalars.count && scalars[run.upperBound] == ":")
    }

    /// 判断 `index` 前的词（允许空格）是否是函数名；`2max(` 即 `2 × max(`。
    private static func namesFunction(_ scalars: [Unicode.Scalar], before index: Int) -> Bool {
        var end = index
        while end > 0, scalars[end - 1].properties.isWhitespace { end -= 1 }
        var start = end
        while start > 0, scalars[start - 1].properties.isAlphabetic || isDigit(scalars[start - 1]) {
            start -= 1
        }
        while start < end, isDigit(scalars[start]) { start += 1 }
        guard start < end else { return false }
        return CalcMath.isFunction(String(String.UnicodeScalarView(scalars[start..<end])).lowercased())
    }

    /// 校验分组是否合法：首组 1–3 位，其余每组恰好 3 位。
    private static func isValidGrouping(_ groups: [ArraySlice<Unicode.Scalar>]) -> Bool {
        guard let first = groups.first, (1...3).contains(first.count) else { return false }
        return groups.dropFirst().allSatisfy { $0.count == 3 }
    }

    private static func isDigit(_ scalar: Unicode.Scalar) -> Bool { (48...57).contains(scalar.value) }
}
