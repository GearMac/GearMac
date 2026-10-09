// 文件职责：解析单位表达式（单位相乘/相除/乘方），并据此构造复合单位与货币单位。
// 分层：Model；纯解析与单位组合，不 import AppKit/SwiftUI，不产生副作用。
import Foundation

/// 单位表达式的解析与组合。
enum CalcUnitExpression {
    /// 按名字取单位；不在单位表中时尝试货币名，并包装为带货币量纲的单位。
    static func named(_ name: String) -> UnitDef? {
        if let unit = CalcUnits.byName[name] { return unit }
        guard let currency = CalcCurrency.byName[name] else { return nil }
        return UnitDef(
            currency.code, currency.name, .compound, 1,
            dimension: CalcDimension(currency: 1), currency: currency)
    }

    /// 解析整段 token 为单位定义；存在未消费的 token 时返回 nil。
    static func parse(_ tokens: [CalcToken]) -> UnitDef? {
        var parser = UnitParser(tokens: tokens)
        guard let unit = parser.expression(), parser.index == tokens.count else { return nil }
        return unit
    }

    /// 从 `index` 起解析单个单位因子，返回单位与结束位置。
    static func factor(_ tokens: [CalcToken], at index: Int) -> (unit: UnitDef, end: Int)? {
        var parser = UnitParser(tokens: tokens, index: index)
        guard let unit = parser.factor() else { return nil }
        return (unit, parser.index)
    }

    /// 按乘法或除法组合两个单位，生成复合单位；量纲或缩放系数不合法时返回 nil。
    static func combine(_ left: UnitDef, _ right: UnitDef, dividing: Bool) -> UnitDef? {
        guard let lhs = left.dimension, let rhs = right.dimension,
            left.currency == nil || right.currency == nil || left.currency == right.currency
        else { return nil }
        let dimension = lhs.adding(rhs, scale: dividing ? -1 : 1)
        guard abs(dimension.currency) <= 1 else { return nil }
        let factor = dividing ? left.factor / right.factor : left.factor * right.factor
        guard factor.isFinite, factor > 0 else { return nil }
        let rightSymbol =
            dividing && (right.symbol.contains("/") || right.symbol.contains("·"))
            ? "(\(right.symbol))" : right.symbol
        return UnitDef(
            left.symbol + (dividing ? "/" : "·") + rightSymbol,
            "Compound Units", .compound, factor, dimension: dimension,
            currency: dimension.currency == 0 ? nil : left.currency ?? right.currency)
    }

    /// 对单位取幂，生成复合单位；量纲或缩放系数不合法时返回 nil。
    static func power(_ unit: UnitDef, _ exponent: Double) -> UnitDef? {
        guard let dimension = unit.dimension else { return nil }
        let raised = dimension.raised(to: exponent)
        guard abs(raised.currency) <= 1, raised.currency.rounded() == raised.currency else { return nil }
        let factor = pow(unit.factor, exponent)
        guard factor.isFinite, factor > 0 else { return nil }
        let symbol = unit.symbol.contains("/") || unit.symbol.contains("·") ? "(\(unit.symbol))" : unit.symbol
        let suffix = exponent == 2 ? "²" : exponent == 3 ? "³" : "^" + CalcFormatter.copyText(exponent)
        return UnitDef(
            symbol + suffix, "Compound Units", .compound, factor, dimension: raised,
            currency: raised.currency == 0 ? nil : unit.currency)
    }

    /// 单位表达式的小型递归下降解析器。
    private struct UnitParser {
        let tokens: [CalcToken]
        var index = 0
        /// 当前待解析的 token；已到末尾时为 nil。
        var current: CalcToken? { index < tokens.count ? tokens[index] : nil }

        /// 解析「因子 (×/÷ 因子)*」形式的单位表达式。
        mutating func expression() -> UnitDef? {
            guard var left = factor() else { return nil }
            while current == .op(.multiply) || current == .op(.divide) {
                let dividing = current == .op(.divide)
                index += 1
                guard let right = factor(), let result = combine(left, right, dividing: dividing) else {
                    return nil
                }
                left = result
            }
            return left
        }

        /// 解析单个因子：单位名或括号分组，后可带 `^` 幂。
        mutating func factor() -> UnitDef? {
            let unit: UnitDef
            if case .ident(let name) = current, let found = named(name) {
                unit = found
                index += 1
            } else if current == .op(.open) {
                index += 1
                guard let found = expression(), current == .op(.close) else { return nil }
                unit = found
                index += 1
            } else {
                return nil
            }
            guard current == .op(.power) else { return unit }
            index += 1
            let negative = current == .op(.subtract)
            if negative { index += 1 }
            guard case .number(let number) = current, number <= 16 else { return nil }
            index += 1
            return power(unit, negative ? -number : number)
        }
    }
}
