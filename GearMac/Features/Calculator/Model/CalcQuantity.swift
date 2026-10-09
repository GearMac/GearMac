// 文件职责：解析并求值带量纲的表达式，包括单位/货币换算、测量值运算、布尔结果卡片构造与表达式回显文本。
// 分层：Model；只依赖 Foundation 与同层单位/货币表，不 import AppKit/SwiftUI，不产生副作用。
import Foundation

/// 面向测量单位与货币的量纲化算术。
enum CalcQuantity {
    /// 入口：把分词结果求值为单位/货币/布尔/标量结果；无意义或不完整时返回 nil。
    static func evaluate(
        _ tokens: [CalcToken], query: String, rates: CurrencyRates?, region: String? = nil,
        preserveStandaloneUnit: Bool = false, language: AppLanguage = .english
    ) -> CalcResult? {
        if tokens.count == 1, case .intLiteral = tokens[0] { return nil }
        let split = splitConversion(tokens)
        if let target = split.targetName, target != "timespan", target != "duration",
            isSimpleConversionSource(split.expressionTokens),
            CalcUnits.byName[target] != nil || CalcCurrency.byName[target] != nil
        {
            return nil
        }

        var parser = CalcExpressionParser(
            tokens: split.expressionTokens, rates: rates, language: language)
        guard let value = parser.parse() else {
            guard let message = parser.issue else { return nil }
            return CalcResult(expression: query, payload: .error(message: message))
        }
        if parser.dimensionCount == 0, !value.isBoolean {
            guard split.targetName == nil,
                parser.operationCount > 0 || (!preserveStandaloneUnit && tokens.count > 1)
            else { return nil }
            return CalcResult(
                expression: CalcFormatter.expression(query), sourceBadge: expressionBadge(language),
                targetBadge: resultBadge(language), payload: .number(value.effective))
        }
        if value.isBoolean {
            guard split.targetName == nil else { return nil }
            let text = value.amount == 0 ? "false" : "true"
            return CalcResult(
                expression: expressionText(split.expressionTokens),
                sourceBadge: expressionBadge(language),
                targetBadge: L10n.string(CalculatorKey.badgeBoolean, language: language),
                payload: .value(display: text, copyText: text), canChain: false)
        }

        if parser.usedCurrency && !parser.usedCurrencyRate {
            guard let rates else {
                return CalcResult(
                    expression: query,
                    payload: .error(
                        message: L10n.string(
                            CalculatorKey.errorRatesUnavailable, language: language)))
            }
            if let code = parser.currencyCodes.first(where: { rates.rate(for: $0) == nil }) {
                return CalcResult(
                    expression: query,
                    payload: .error(
                        message: String(
                            format: L10n.string(CalculatorKey.errorNoRate, language: language),
                            code)))
            }
        }

        if let targetName = split.targetName {
            if targetName == "timespan" || targetName == "duration" {
                guard case .unit(let unit) = value.kind, unit.category == .time else { return nil }
                let seconds = value.amount * unit.factor
                guard seconds.isFinite else { return nil }
                let text = CalcFormatter.timespan(seconds, language: language)
                return CalcResult(
                    expression: expressionText(split.expressionTokens),
                    sourceBadge: parser.operationCount == 0
                        ? unit.name : expressionBadge(language),
                    targetBadge: L10n.string(CalculatorKey.badgeTimespan, language: language),
                    payload: .value(display: text, copyText: text))
            }
            guard let output = parser.converted(value, to: targetName) else {
                guard let message = parser.issue else { return nil }
                return CalcResult(expression: query, payload: .error(message: message))
            }
            return convertedResult(
                output, expression: expressionText(split.expressionTokens), language: language)
        }

        switch value.kind {
        case .scalar:
            guard parser.operationCount > 0 else { return nil }
            return CalcResult(
                expression: expressionText(split.expressionTokens),
                sourceBadge: expressionBadge(language), targetBadge: resultBadge(language),
                payload: .number(value.effective))
        case .unit(let unit):
            // 单独的 `50cm` 会在下面自动换算；带运算符时保留输入的单位。
            if !preserveStandaloneUnit, parser.operationCount == 0, parser.dimensionCount == 1,
                case .ident(let finalName)? = split.expressionTokens.last,
                CalcUnits.byName[finalName] != nil
            {
                return nil
            }
            guard parser.operationCount > 0 || parser.dimensionCount > 1 || preserveStandaloneUnit else {
                return nil
            }
            return measurementResult(
                value.amount, unit: unit, expression: expressionText(split.expressionTokens),
                language: language)
        case .currency(let definition):
            guard parser.operationCount == 0 else {
                return currencyResult(
                    value.amount, definition: definition,
                    expression: expressionText(split.expressionTokens), language: language)
            }
            let expression = "\(CalcFormatter.display(value.amount)) \(definition.code)"
            // 单独金额没有指定目标，因此输入后以 Mac 本地区货币作为目标。
            guard !preserveStandaloneUnit, let target = regionTarget(region, from: definition),
                let output = rates?.convert(value.amount, from: definition.code, to: target.code)
            else {
                return currencyResult(
                    value.amount, definition: definition, expression: expression,
                    language: language)
            }
            return currencyResult(
                output, definition: target, expression: expression, sourceBadge: definition.name,
                language: language)
        }
    }

    /// 单独输入一个金额的唯一意义就是换算，因此让它与本地区货币配对。
    private static func regionTarget(_ region: String?, from: CurrencyDef) -> CurrencyDef? {
        guard let regional = region.flatMap({ CalcCurrency.byName[$0.lowercased()] })
        else { return nil }
        guard regional.code == from.code else { return regional }
        return CalcCurrency.byName[from.code == "USD" ? "eur" : "usd"]
    }

    /// 把转换后的 `CalcValue` 转为对应卡片（测量值或货币）；标量不合规时返回 nil。
    private static func convertedResult(
        _ value: CalcValue, expression: String, language: AppLanguage
    ) -> CalcResult? {
        switch value.kind {
        case .scalar:
            return nil
        case .unit(let unit):
            return measurementResult(
                value.amount, unit: unit, expression: expression, language: language)
        case .currency(let definition):
            return currencyResult(
                value.amount, definition: definition, expression: expression, language: language)
        }
    }

    /// 卡片左列的「表达式」徽章。
    private static func expressionBadge(_ language: AppLanguage) -> String {
        L10n.string(CalculatorKey.badgeExpression, language: language)
    }

    /// 卡片右列的「结果」徽章。
    private static func resultBadge(_ language: AppLanguage) -> String {
        L10n.string(CalculatorKey.badgeResult, language: language)
    }

    /// 构造测量值卡片：表达式 + 单位目标的徽章 + 测量载荷。
    private static func measurementResult(
        _ amount: Double, unit: UnitDef, expression: String, language: AppLanguage
    ) -> CalcResult {
        CalcResult(
            expression: expression,
            sourceBadge: expressionBadge(language), targetBadge: unit.name,
            payload: .measurement(amount, unit: unit))
    }

    /// 构造货币卡片：显示值带分组符、复制文本不带，均附币种代码。
    private static func currencyResult(
        _ amount: Double, definition: CurrencyDef, expression: String,
        sourceBadge: String? = nil, language: AppLanguage = .english
    ) -> CalcResult {
        let formatted = CalcFormatter.currency(amount)
        return CalcResult(
            expression: expression,
            sourceBadge: sourceBadge ?? expressionBadge(language), targetBadge: definition.name,
            payload: .value(
                display: "\(CalcFormatter.grouped(formatted)) \(definition.code)",
                copyText: "\(formatted) \(definition.code)"))
    }

    /// 按 factor/offset 在两种单位间换算：先去源偏移，再乘/除缩放系数。
    static func convertUnit(_ amount: Double, from: UnitDef, to: UnitDef) -> Double {
        (amount * from.factor + from.offset - to.offset) / to.factor
    }

    /// 把「表达式 + 转换目标」拆开；无目标时返回原 token 列表与 nil。
    private static func splitConversion(
        _ tokens: [CalcToken]
    ) -> (expressionTokens: [CalcToken], targetName: String?) {
        guard let target = conversionTarget(tokens, from: 0, to: tokens.count) else { return (tokens, nil) }
        return (Array(tokens[..<target.start]), target.name)
    }

    /// 在 token 中定位末尾的连接词（to/in/→）及其后的目标单位，返回连接词下标与目标名；未找到时返回 nil。
    static func conversionTarget(
        _ tokens: [CalcToken], from start: Int, to end: Int
    ) -> (start: Int, name: String)? {
        var depth = 0
        for index in start..<end {
            if tokens[index] == .op(.open) { depth += 1 }
            if tokens[index] == .op(.close) { depth -= 1 }
            guard depth == 0, index + 1 < end, CalcUnits.isConnector(tokens[index]) else { continue }
            if index + 2 == end, case .ident(let name) = tokens[index + 1] { return (index, name) }
            let target = Array(tokens[(index + 1)..<end])
            guard CalcUnitExpression.parse(target) != nil else { continue }
            return (
                index,
                target.map { token in
                    switch token {
                    case .ident(let name): return name
                    case .op(let op): return String(op.rawValue)
                    case .number(let value): return CalcFormatter.copyText(value)
                    default: return ""
                    }
                }.joined(separator: " ")
            )
        }
        return nil
    }

    /// 判断是否为「单个单位」或「数值+单位」这类最简转换源。
    private static func isSimpleConversionSource(_ tokens: [CalcToken]) -> Bool {
        switch tokens.count {
        case 1:
            if case .ident = tokens[0] { return true }
        case 2:
            switch (tokens[0], tokens[1]) {
            case (.number, .ident), (.compactNumber, .ident),
                (.ident, .number), (.ident, .compactNumber):
                return true
            default:
                break
            }
        default:
            break
        }
        return false
    }

    /// 卡片左列的规范化回显：单位符号、美观字形，以及 `金额 币种代码` 形式的货币。
    private static func expressionText(_ tokens: [CalcToken]) -> String {
        var parts: [String] = []
        parts.reserveCapacity(tokens.count)
        var attachNext = true

        func add(_ piece: String, attached: Bool = false) {
            if attachNext || attached, !parts.isEmpty {
                parts[parts.count - 1] += piece
            } else {
                parts.append(piece)
            }
            attachNext = false
        }

        var index = 0
        while index < tokens.count {
            // 货币写法是符号在前（`$10`），因此回显时把金额放在币种代码之前。
            if case .ident(let name) = tokens[index], CalcUnits.byName[name] == nil,
                let definition = CalcCurrency.byName[name], index + 1 < tokens.count,
                let amount = numberValue(tokens[index + 1])
            {
                add(CalcFormatter.copyText(amount))
                add(definition.code)
                index += 2
                continue
            }

            switch tokens[index] {
            case .number(let value), .compactNumber(let value):
                add(CalcFormatter.copyText(value))
            case .intLiteral(let value, _):
                add(String(value))
            case .ident(let name):
                add(CalcUnits.byName[name]?.symbol ?? CalcCurrency.byName[name]?.code ?? name)
                attachNext =
                    index + 1 < tokens.count && tokens[index + 1] == .op(.open)
                    && CalcMath.isFunction(name)
            case .op(.open):
                add("(")
                attachNext = true
            case .op(.close):
                add(")", attached: true)
            case .op(.percent):
                add("%", attached: true)
            case .op(.factorial):
                add("!", attached: true)
            case .op(.multiply):
                add("×")
            case .op(.divide):
                add("÷")
            case .op(let op):
                add(op.text)
                if op == .subtract || op == .add { attachNext = isSign(at: index, tokens) }
            case .arrow:
                add("→")
            case .comma:
                add(",", attached: true)
            }
            index += 1
        }
        return parts.joined(separator: " ")
    }

    /// 判定 `+`/`-` 是在给后面的操作数取负，而非连接两个操作数。
    private static func isSign(at index: Int, _ tokens: [CalcToken]) -> Bool {
        guard index > 0 else { return true }
        switch tokens[index - 1] {
        case .op(let previous):
            return previous != .close && previous != .percent && previous != .factorial
        // 单词运算符（`of`、`mod`、`sqrt`）会引入一个操作数，因此符号属于它。
        case .ident(let name):
            return CalcUnits.byName[name] == nil && CalcCurrency.byName[name] == nil
                && CalcMath.constants[name] == nil
        default:
            return false
        }
    }

    /// 从数字型 token 取值；其他 token 返回 nil。
    static func numberValue(_ token: CalcToken) -> Double? {
        switch token {
        case .number(let value), .compactNumber(let value):
            return value
        default:
            return nil
        }
    }
}
