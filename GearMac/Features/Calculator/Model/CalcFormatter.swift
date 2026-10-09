// 文件职责：计算结果与表达式的纯文本格式化：表达式回显、数字分组、货币、英尺英寸与时间段展示。
// 分层：Model；手写实现、与 locale 无关，保证每种语言下渲染结果一致。
import Foundation

/// 手写、与 locale 无关的数字格式化，使所有 locale 下列渲染一致。
enum CalcFormatter {
    /// 将查询规范化为单空格间隔，并把 `*`/`/` 换成 `×`/`÷` 作为表达式回显。
    static func expression(_ query: String) -> String {
        query.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .replacingOccurrences(of: "*", with: "×")
            .replacingOccurrences(of: "/", with: "÷")
    }

    /// 面向用户：≤10 位有效数字，去掉尾随零，带千位分隔符。
    static func display(_ value: Double) -> String {
        grouped(copyText(value))
    }

    /// 2^53 以内所有整数在 Double 中都精确可表示。
    private static let maxExactInteger = 9_007_199_254_740_992.0

    /// 同样舍入但不分组——这是写入剪贴板的内容。
    static func copyText(_ value: Double) -> String {
        let v = value == 0 ? 0 : value  // 归一化 -0
        // 超过 2^53 后精度确实丢失，此时指数形式才是诚实的结果。
        if v.rounded() == v && abs(v) <= maxExactInteger {
            return String(Int64(v))
        }
        return String(format: "%.10g", v)
    }

    /// 金额：保留 2 位小数，小于 1 分时自动加宽。从不使用 `%g`。见 docs/features/calculator.md
    static func currency(_ value: Double) -> String {
        let magnitude = abs(value)
        // 低于约 1e-9 时数字已无意义，且直接用 "0.00" 可避免 `%.2f` 产生 "-0.00"。
        guard magnitude >= 1e-9 else { return "0.00" }
        guard magnitude < 0.01 else { return String(format: "%.2f", value) }
        var text = String(format: "%.\(3 - Int(floor(log10(magnitude))))f", value)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }

    /// 整英尺加剩余英寸，仅用于公制长度自动换算为英制的场景。
    static func compoundFeetInches(_ feet: Double, language: AppLanguage = .english) -> String {
        let sign = feet < 0 ? "-" : ""
        let magnitude = abs(feet)
        let wholeFeet = magnitude.rounded(.towardZero)
        let inches = (magnitude - wholeFeet) * 12
        let feetPart =
            wholeFeet == 0
            ? ""
            : "\(sign)\(display(wholeFeet)) "
                + L10n.string(
                    wholeFeet == 1 ? CalculatorKey.footSingular : CalculatorKey.footPlural,
                    language: language)
        let inchText = display(inches)
        let inchPart =
            "\(inchText) "
            + L10n.string(
                inchText == "1" ? CalculatorKey.inchSingular : CalculatorKey.inchPlural,
                language: language)
        if feetPart.isEmpty { return "\(sign)\(inchPart)" }
        return "\(feetPart) \(inchPart)"
    }

    /// 把秒数拆成最大可能的单位：`8,700` → `2 hr 25 min`。
    static func timespan(_ seconds: Double, language: AppLanguage = .english) -> String {
        guard seconds.isFinite else { return display(seconds) }
        let sign = seconds < 0 ? "-" : ""
        var remainder = abs(seconds).rounded()
        var parts: [String] = []
        for step in timespanSteps where remainder >= step.seconds {
            let count = (remainder / step.seconds).rounded(.towardZero)
            remainder -= count * step.seconds
            parts.append(
                "\(grouped(String(format: "%.0f", count))) "
                    + L10n.string(step.key, language: language))
        }
        // 不足 1 秒的输入没有整数部分可展示，保留其自身精度。
        if parts.isEmpty {
            return "\(display(seconds)) " + L10n.string(CalculatorKey.timespanSecond, language: language)
        }
        return sign + parts.joined(separator: " ")
    }

    /// 周是最大单位：月份并非固定秒数。
    private static let timespanSteps: [(seconds: Double, key: CalculatorKey)] = [
        (604800, .timespanWeek), (86400, .timespanDay), (3600, .timespanHour),
        (60, .timespanMinute), (1, .timespanSecond)
    ]

    /// 每三个整数位插入一个 `,`；指数形式的字符串原样返回。
    static func grouped(_ text: String) -> String {
        let bytes = text.utf8
        guard !bytes.contains(101), !bytes.contains(69) else { return text }
        let signCount = bytes.first == 45 ? 1 : 0
        let integer = bytes.prefix { $0 != 46 }
        guard integer.count - signCount > 3 else { return text }
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count + integer.count / 3)
        for (index, byte) in bytes.enumerated() {
            if index > signCount, index < integer.count, (integer.count - index) % 3 == 0 {
                output.append(44)
            }
            output.append(byte)
        }
        return String(bytes: output, encoding: .utf8)!
    }
}
