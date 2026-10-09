// 文件职责：识别算术解析器覆盖不到的百分比/比例类短语（折扣、占比、小费、比值、聚合、就近取整）并给出结果卡片。
// 分层：Model；纯短语解析，不 import AppKit/SwiftUI，不产生副作用。
import Foundation

/// 算术解析器覆盖不到的百分比说法，例如 `20% off 500`、`50 as % of 200`。
enum CalcPercent {
    /// 依次尝试各类百分比/比例短语解析；全部不匹配时返回 nil。
    static func evaluate(
        _ tokens: [CalcToken], query: String, language: AppLanguage = .english
    ) -> CalcResult? {
        parseOff(tokens, query: query, language: language)
            ?? parseAsPercentOf(tokens, query: query, language: language)
            ?? parseTip(tokens, query: query, language: language)
            ?? parseWhatPercentOf(tokens, query: query, language: language)
            ?? parseIsPercentOfWhat(tokens, query: query, language: language)
            ?? parseRatio(tokens, query: query, language: language)
            ?? parseAggregate(tokens, query: query, language: language)
            ?? parseRoundToNearest(tokens, query: query, language: language)
    }

    /// `<pct>% off <value>` → 金额按百分比扣减后的值（`20% off 500` → 400）。
    private static func parseOff(
        _ tokens: [CalcToken], query: String, language: AppLanguage
    ) -> CalcResult? {
        guard let off = tokens.firstIndex(of: .ident("off")), off >= 2,
            tokens[off - 1] == .op(.percent),
            let pct = CalcExpressionParser.scalar(Array(tokens[0..<(off - 1)])),
            let base = CalcExpressionParser.scalar(Array(tokens[(off + 1)...]))
        else { return nil }
        let result = base * (1 - pct / 100)
        guard result.isFinite else { return nil }
        return card(
            query, .number(result),
            target: L10n.string(CalculatorKey.targetDiscounted, language: language),
            language: language)
    }

    /// `<x> as % of <y>` → x / y × 100，以百分比呈现（`50 as % of 200` → 25%）。
    private static func parseAsPercentOf(
        _ tokens: [CalcToken], query: String, language: AppLanguage
    ) -> CalcResult? {
        guard let asIdx = tokens.firstIndex(of: .ident("as")), asIdx + 2 < tokens.count,
            tokens[asIdx + 1] == .op(.percent), tokens[asIdx + 2] == .ident("of"),
            let x = CalcExpressionParser.scalar(Array(tokens[0..<asIdx])),
            let y = CalcExpressionParser.scalar(Array(tokens[(asIdx + 3)...])), y != 0
        else { return nil }
        let ratio = x / y * 100
        guard ratio.isFinite else { return nil }
        return card(
            query, .number(ratio, suffix: "%"),
            target: L10n.string(CalculatorKey.targetPercentage, language: language),
            language: language)
    }

    /// 构造一张结果卡片：统一表达式回显与 Expression 来源徽章，`target` 为右侧目标徽章。
    private static func card(
        _ query: String, _ payload: CalcResult.Payload, target: String? = nil,
        canChain: Bool = true, language: AppLanguage
    ) -> CalcResult {
        CalcResult(
            expression: query.split(whereSeparator: \.isWhitespace).joined(separator: " "),
            sourceBadge: L10n.string(CalculatorKey.badgeExpression, language: language),
            targetBadge: target ?? L10n.string(CalculatorKey.badgeResult, language: language),
            payload: payload,
            canChain: canChain)
    }

    /// 只返回小费金额而非总额：短语问的就是这个数。
    private static func parseTip(
        _ tokens: [CalcToken], query: String, language: AppLanguage
    ) -> CalcResult? {
        guard let tip = tokens.firstIndex(of: .ident("tip")), tip >= 2,
            tip + 2 < tokens.count, tokens[tip - 1] == .op(.percent),
            tokens[tip + 1] == .ident("on") || tokens[tip + 1] == .ident("of"),
            let pct = CalcExpressionParser.scalar(Array(tokens[0..<(tip - 1)])),
            let bill = CalcExpressionParser.scalar(Array(tokens[(tip + 2)...]))
        else { return nil }
        let amount = bill * pct / 100
        guard amount.isFinite else { return nil }
        return card(
            query, .number(amount),
            target: L10n.string(CalculatorKey.targetTip, language: language), language: language)
    }

    /// `<x> is what % of <y>` → x / y × 100，以百分比呈现。
    private static func parseWhatPercentOf(
        _ tokens: [CalcToken], query: String, language: AppLanguage
    ) -> CalcResult? {
        guard let isIdx = tokens.firstIndex(of: .ident("is")), isIdx + 4 <= tokens.count,
            isIdx + 3 < tokens.count,
            tokens[isIdx + 1] == .ident("what"), tokens[isIdx + 2] == .op(.percent),
            tokens[isIdx + 3] == .ident("of"),
            let x = CalcExpressionParser.scalar(Array(tokens[0..<isIdx])),
            let y = CalcExpressionParser.scalar(Array(tokens[(isIdx + 4)...])), y != 0
        else { return nil }
        let ratio = x / y * 100
        guard ratio.isFinite else { return nil }
        return card(
            query, .number(ratio, suffix: "%"),
            target: L10n.string(CalculatorKey.targetPercentage, language: language),
            language: language)
    }

    /// `<x> is <pct>% of what` → 反推总数 `x / (pct / 100)`。
    private static func parseIsPercentOfWhat(
        _ tokens: [CalcToken], query: String, language: AppLanguage
    ) -> CalcResult? {
        guard tokens.count >= 6, tokens.last == .ident("what"),
            tokens[tokens.count - 2] == .ident("of"), tokens[tokens.count - 3] == .op(.percent),
            let isIdx = tokens.firstIndex(of: .ident("is")),
            let x = CalcExpressionParser.scalar(Array(tokens[0..<isIdx])),
            let pct = CalcExpressionParser.scalar(Array(tokens[(isIdx + 1)..<(tokens.count - 3)])),
            pct != 0
        else { return nil }
        let whole = x / (pct / 100)
        guard whole.isFinite else { return nil }
        return card(
            query, .number(whole),
            target: L10n.string(CalculatorKey.targetTotal, language: language),
            language: language)
    }

    /// 仅接受整数，使约分后的比值保持精确。
    private static func parseRatio(
        _ tokens: [CalcToken], query: String, language: AppLanguage
    ) -> CalcResult? {
        guard tokens.count >= 5, tokens[0] == .ident("ratio"), tokens[1] == .ident("of"),
            let toIdx = tokens.firstIndex(of: .ident("to")),
            let a = CalcExpressionParser.scalar(Array(tokens[2..<toIdx])),
            let b = CalcExpressionParser.scalar(Array(tokens[(toIdx + 1)...])),
            a.rounded() == a, b.rounded() == b, abs(a) <= 1e15, abs(b) <= 1e15, a != 0 || b != 0
        else { return nil }
        let divisor = greatestCommonDivisor(abs(a), abs(b))
        guard divisor > 0 else { return nil }
        let text = "\(CalcFormatter.display(a / divisor)) : \(CalcFormatter.display(b / divisor))"
        return card(
            query, .value(display: text, copyText: text),
            target: L10n.string(CalculatorKey.targetRatio, language: language), canChain: false,
            language: language)
    }

    /// 用辗转相除法（欧几里得算法）求两个非负数的最大公约数。
    private static func greatestCommonDivisor(_ a: Double, _ b: Double) -> Double {
        var (x, y) = (a, b)
        while y > 0 { (x, y) = (y, x.truncatingRemainder(dividingBy: y)) }
        return x
    }

    /// `<聚合名> of <列表>` → 对逗号/and 分隔的列表求平均、求和、最小值或最大值。
    private static func parseAggregate(
        _ tokens: [CalcToken], query: String, language: AppLanguage
    ) -> CalcResult? {
        guard tokens.count >= 3, case .ident(let name) = tokens[0],
            let aggregate = aggregates[name], tokens[1] == .ident("of")
        else { return nil }
        let values = splitList(Array(tokens[2...]))
        guard values.count >= 2, let result = aggregate.reduce(values), result.isFinite
        else { return nil }
        return card(
            query, .number(result),
            target: L10n.string(aggregate.badge, language: language), language: language)
    }

    /// 对齐到步长而非小数位数，因此 `nearest 5` 表示 5 的倍数。
    private static func parseRoundToNearest(
        _ tokens: [CalcToken], query: String, language: AppLanguage
    ) -> CalcResult? {
        guard tokens.count >= 5, tokens[0] == .ident("round"),
            let toIdx = tokens.firstIndex(of: .ident("to")), toIdx + 2 < tokens.count,
            tokens[toIdx + 1] == .ident("nearest"),
            let value = CalcExpressionParser.scalar(Array(tokens[1..<toIdx])),
            let step = CalcExpressionParser.scalar(Array(tokens[(toIdx + 2)...])), step != 0
        else { return nil }
        let result = (value / step).rounded() * step
        guard result.isFinite else { return nil }
        return card(
            query, .number(result),
            target: L10n.string(CalculatorKey.targetRounded, language: language),
            language: language)
    }

    /// 徽章标明实际执行的聚合，使 `min` 与 `max` 在卡片上可区分。
    private struct Aggregate {
        /// 目标徽章的本地化键。
        let badge: CalculatorKey
        let reduce: @Sendable ([Double]) -> Double?
    }

    /// 聚合函数表：短语名（含别名）映射到显示名称与归约实现。
    private static let aggregates: [String: Aggregate] = [
        "average": Aggregate(badge: .aggregateAverage) { $0.reduce(0, +) / Double($0.count) },
        "avg": Aggregate(badge: .aggregateAverage) { $0.reduce(0, +) / Double($0.count) },
        "mean": Aggregate(badge: .aggregateAverage) { $0.reduce(0, +) / Double($0.count) },
        "sum": Aggregate(badge: .aggregateSum) { $0.reduce(0, +) },
        "total": Aggregate(badge: .aggregateSum) { $0.reduce(0, +) },
        "min": Aggregate(badge: .aggregateMinimum) { $0.min() },
        "max": Aggregate(badge: .aggregateMaximum) { $0.max() }
    ]

    /// 每段整体求值，因此 `sum of 2*3, 4` 仍是两个操作数。
    private static func splitList(_ tokens: [CalcToken]) -> [Double] {
        var values: [Double] = []
        var current: [CalcToken] = []
        for token in tokens {
            if token == .comma || token == .ident("and") {
                guard let value = CalcExpressionParser.scalar(current) else { return [] }
                values.append(value)
                current = []
            } else {
                current.append(token)
            }
        }
        guard let last = CalcExpressionParser.scalar(current) else { return [] }
        values.append(last)
        return values
    }
}
