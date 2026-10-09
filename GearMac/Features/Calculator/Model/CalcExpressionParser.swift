// 文件职责：Calculator 的表达式求值器，按运算符优先级对 CalcToken 流求值，产出标量、带单位或带货币的 CalcValue。
// 分层：Model；汇率等外部事实由构造参数注入，错误通过 issue 文字回传而非抛异常。
import Foundation

/// 基于 token 流的运算符优先级解析器，实例累积解析过程中的各类标记与错误。
struct CalcExpressionParser {
    /// 仅当整个表达式是纯标量（无量纲、非布尔）时返回其值，否则返回 nil。
    static func scalar(_ tokens: [CalcToken]) -> Double? {
        var parser = CalcExpressionParser(tokens: tokens, rates: nil)
        guard let value = parser.parse(), case .scalar = value.kind, !value.isBoolean else { return nil }
        return value.effective
    }

    let tokens: [CalcToken]
    let rates: CurrencyRates?
    var position = 0
    var operationCount = 0
    var dimensionCount = 0
    var usedCurrency = false
    var usedCurrencyRate = false
    var currencyCodes: [String] = []
    var issue: String?
    /// 生成 issue 文字所用的界面语言；默认英文，保证引擎的英文输出不变。
    var language: AppLanguage = .english

    private static let unaryBindingPower = 25
    private static let compositeBindingPower = 40

    /// 当前待消费的 token，已消费完则为 nil。
    private var current: CalcToken? {
        position < tokens.count ? tokens[position] : nil
    }

    /// 对整个 token 流求值：要求恰好消费完所有 token、结果有限，并对复合单位做一次化简。
    mutating func parse() -> CalcValue? {
        guard var value = parseExpression(minBindingPower: 0), position == tokens.count,
            value.effective.isFinite
        else { return nil }
        if case .unit(let unit) = value.kind, unit.category == .compound,
            let dimension = unit.dimension, dimension == .scalar || dimension == CalcDimension(currency: 1),
            let simplified = derived(value.effective * unit.factor, dimension: dimension, unit: unit)
        {
            value = simplified
            operationCount += 1
        }
        return value
    }

    /// Pratt 解析主循环：先取一个操作数，再按绑定力依次合并二元运算符。
    private mutating func parseExpression(minBindingPower: Int) -> CalcValue? {
        guard var left = parseOperand(), left.effective.isFinite else { return nil }
        if let target = peekAdditiveConversion() {
            position += 2
            operationCount += 1
            guard let converted = converted(left, to: target) else { return nil }
            left = converted
        }
        while let binary = peekBinary(left: left), binary.bindingPower >= minBindingPower {
            if binary.consumesToken { position += 1 }
            operationCount += 1
            guard
                let right = parseExpression(minBindingPower: binary.rightBindingPower),
                let combined = apply(
                    binary.op, left, right, implicit: !binary.consumesToken), combined.effective.isFinite
            else { return nil }
            left = combined
        }
        return left
    }

    /// 仅当 `to` 后面跟着 `+`/`-` 时才当作表达式中间的换算：`to usd * 30` 确实有歧义，不处理。
    private func peekAdditiveConversion() -> String? {
        guard position + 2 < tokens.count, CalcUnits.isConnector(tokens[position]),
            case .ident(let name) = tokens[position + 1],
            CalcUnits.byName[name] != nil || CalcCurrency.byName[name] != nil,
            case .op(let next) = tokens[position + 2], next == .add || next == .subtract
        else { return nil }
        return name
    }

    /// 一个二元运算符、其绑定力、右操作数的最小绑定力，以及它是否消耗当前 token。
    struct BinaryOp {
        let op: CalcOperator
        let bindingPower: Int
        let rightBindingPower: Int
        let consumesToken: Bool
    }

    /// 判断当前位置能否作为二元运算符——包括显式运算符、单词形式（`mod`/`of`）与隐式乘法。
    private func peekBinary(left: CalcValue) -> BinaryOp? {
        switch current {
        case .op(let op) where op.bindingPower != nil:
            let power = op.bindingPower ?? 0
            return BinaryOp(
                op: op, bindingPower: power,
                rightBindingPower: power + (op == .power ? 0 : 1), consumesToken: true)
        case .ident("mod"):
            return BinaryOp(op: .percent, bindingPower: 20, rightBindingPower: 21, consumesToken: true)
        case .ident("power"):
            return BinaryOp(op: .power, bindingPower: 30, rightBindingPower: 30, consumesToken: true)
        case .ident("xor"):
            return BinaryOp(op: .bitXor, bindingPower: 6, rightBindingPower: 7, consumesToken: true)
        case .ident("of"):
            return BinaryOp(op: .multiply, bindingPower: 20, rightBindingPower: 21, consumesToken: true)
        default:
            if case .op(.open) = current {
                return BinaryOp(op: .multiply, bindingPower: 20, rightBindingPower: 21, consumesToken: false)
            }
            if case .ident(let name) = current,
                CalcMath.constants[name] != nil || CalcMath.isFunction(name)
                    || ((name == "square" || name == "cube") && position + 1 < tokens.count
                        && tokens[position + 1] == .ident("root"))
            {
                return BinaryOp(op: .multiply, bindingPower: 20, rightBindingPower: 21, consumesToken: false)
            }
            if !isScalar(left.kind), startsQuantity(current) {
                return BinaryOp(
                    op: .add, bindingPower: Self.compositeBindingPower,
                    rightBindingPower: Self.compositeBindingPower + 1, consumesToken: false)
            }
            return nil
        }
    }

    /// 根据运算符对左右操作数求值，负责比较、位运算、百分比与四则运算的分发。
    private mutating func apply(
        _ op: CalcOperator, _ left: CalcValue, _ right: CalcValue, implicit: Bool
    ) -> CalcValue? {
        guard !left.isBoolean, !right.isBoolean else { return nil }
        switch op {
        case .equal, .notEqual, .less, .greater, .lessEqual, .greaterEqual:
            guard let amount = comparable(right, to: left), amount.isFinite else { return nil }
            let result: Bool
            switch op {
            case .equal: result = left.effective == amount
            case .notEqual: result = left.effective != amount
            case .less: result = left.effective < amount
            case .greater: result = left.effective > amount
            case .lessEqual: result = left.effective <= amount
            default: result = left.effective >= amount
            }
            return CalcValue(amount: result ? 1 : 0, kind: .scalar, isBoolean: true)
        case .percent:
            guard isScalar(left.kind), isScalar(right.kind) else { return nil }
            return CalcValue(
                amount: left.effective.truncatingRemainder(dividingBy: right.effective), kind: .scalar)
        case .bitAnd, .bitOr, .bitXor, .shiftLeft, .shiftRight:
            guard isScalar(left.kind), isScalar(right.kind),
                let result = CalcMath.bitwise(op, left.effective, right.effective)
            else { return nil }
            return CalcValue(amount: result, kind: .scalar)
        case .add, .subtract:
            return addOrSubtract(op, left, right, implicit: implicit)
        case .multiply:
            return multiply(left, right)
        case .divide:
            return divide(left, right)
        case .power:
            guard isScalar(right.kind) else { return nil }
            return power(left, exponent: right.effective)
        default:
            return nil
        }
    }

    /// 加减法：支持百分比增减、同位单位/货币的换算相加，以及纯数字与单位的隐式拼接。
    private mutating func addOrSubtract(
        _ op: CalcOperator, _ left: CalcValue, _ right: CalcValue, implicit: Bool
    ) -> CalcValue? {
        let direction = op == .add ? 1.0 : -1.0
        if right.isPercent {
            let output = left.effective * (1 + direction * right.amount / 100)
            return CalcValue(amount: output, kind: left.kind)
        }

        switch (left.kind, right.kind) {
        case (.scalar, .scalar):
            return CalcValue(
                amount: left.effective + direction * right.effective, kind: .scalar)
        case (.unit(let lhs), .unit(let rhs)):
            guard lhs.isCompatible(with: rhs) else {
                return fail(
                    cannotAddOrSubtract(
                        op, lhs.category.displayName(language), rhs.category.displayName(language))
                )
            }
            if lhs.category == .temperature, lhs.symbol != rhs.symbol {
                return fail(L10n.string(CalculatorKey.errorTemperatureUnits, language: language))
            }
            // 复合单位（"5 feet 3 inches"）以前导单位作答；`+`/`-` 则以后者为准。
            if implicit {
                guard let converted = convertedMeasurement(right.amount, from: rhs, to: lhs) else {
                    return nil
                }
                return CalcValue(
                    amount: left.amount + direction * converted, kind: .unit(lhs))
            }
            guard let converted = convertedMeasurement(left.amount, from: lhs, to: rhs) else { return nil }
            return CalcValue(
                amount: converted + direction * right.amount, kind: .unit(rhs))
        case (.currency(let lhs), .currency(let rhs)):
            if implicit {
                guard let converted = convertedCurrency(right.amount, from: rhs, to: lhs)
                else { return nil }
                return CalcValue(
                    amount: left.amount + direction * converted, kind: .currency(lhs))
            }
            guard let converted = convertedCurrency(left.amount, from: lhs, to: rhs)
            else { return nil }
            return CalcValue(
                amount: converted + direction * right.amount, kind: .currency(rhs))
        case (.unit(let lhs), .currency):
            return fail(
                cannotAddOrSubtract(
                    op, lhs.category.displayName(language),
                    L10n.string(CalculatorKey.categoryCurrency, language: language))
            )
        case (.currency, .unit(let rhs)):
            return fail(
                cannotAddOrSubtract(
                    op, L10n.string(CalculatorKey.categoryCurrency, language: language),
                    rhs.category.displayName(language))
            )
        // 纯数字会吸收其旁的单位；相邻而不接单位时保持沉默，因为可能是写一半的单位。
        case (.unit, .scalar), (.currency, .scalar):
            guard !implicit else { return nil }
            return CalcValue(
                amount: left.amount + direction * right.effective, kind: left.kind)
        case (.scalar, .unit), (.scalar, .currency):
            guard !implicit else { return nil }
            return CalcValue(
                amount: left.effective + direction * right.amount, kind: right.kind)
        }
    }

    /// 乘法：数字与任意值的缩放，以及单位/货币相乘得到复合量纲。
    private mutating func multiply(
        _ left: CalcValue, _ right: CalcValue
    ) -> CalcValue? {
        switch (left.kind, right.kind) {
        case (.scalar, .scalar):
            return CalcValue(amount: left.effective * right.effective, kind: .scalar)
        case (.scalar, _):
            return CalcValue(
                amount: left.effective * right.effective, kind: right.kind)
        case (_, .scalar):
            return CalcValue(
                amount: left.effective * right.effective, kind: left.kind)
        case (.unit, .unit), (.unit, .currency), (.currency, .unit):
            return combine(left, right, dividing: false)
        default:
            return fail(L10n.string(CalculatorKey.errorUnitMultiplication, language: language))
        }
    }

    /// 除法：同类单位相除得倍率，并支持倒数与量纲相消。
    private mutating func divide(
        _ left: CalcValue, _ right: CalcValue
    ) -> CalcValue? {
        guard right.effective != 0 else { return nil }
        switch (left.kind, right.kind) {
        case (.scalar, .scalar):
            return finiteDivision(left.effective, right.effective, kind: .scalar)
        case (.unit, .scalar), (.currency, .scalar):
            return finiteDivision(left.effective, right.effective, kind: left.kind)
        case (.scalar, .unit), (.scalar, .currency):
            guard let unit = arithmeticUnit(right.kind), let inverted = CalcUnitExpression.power(unit, -1),
                let dimension = inverted.dimension
            else { return nil }
            if inverted.currency != nil { usedCurrencyRate = true }
            return derived(
                left.effective / (right.effective * unit.factor), dimension: dimension,
                unit: CalcUnits.baseUnits[dimension] ?? inverted)
        case (.unit(let lhs), .unit(let rhs)):
            if !lhs.isCompatible(with: rhs) || lhs.currency != nil || rhs.currency != nil {
                return combine(left, right, dividing: true)
            }
            guard lhs.category != .temperature else {
                return fail(
                    L10n.string(CalculatorKey.errorTemperatureDivision, language: language))
            }
            let numerator = left.amount * lhs.factor
            let denominator = right.amount * rhs.factor
            return finiteDivision(numerator, denominator, kind: .scalar)
        case (.currency(let lhs), .currency(let rhs)):
            guard let denominator = convertedCurrency(right.amount, from: rhs, to: lhs)
            else { return nil }
            return finiteDivision(left.amount, denominator, kind: .scalar)
        case (.unit, .currency), (.currency, .unit):
            return combine(left, right, dividing: true)
        }
    }

    /// 把值类型映射为参与复合运算的单位定义（货币按其代码取对应单位）。
    private func arithmeticUnit(_ kind: CalcValue.Kind) -> UnitDef? {
        switch kind {
        case .unit(let unit): return unit
        case .currency(let currency): return CalcUnitExpression.named(currency.code.lowercased())
        case .scalar: return nil
        }
    }

    /// 单位/货币的乘除：先尝试量纲运算，否则通过货币汇率折算后合成复合单位。
    private mutating func combine(_ left: CalcValue, _ right: CalcValue, dividing: Bool) -> CalcValue? {
        guard let lhs = arithmeticUnit(left.kind), var rhs = arithmeticUnit(right.kind) else { return nil }
        if lhs.currency == nil, rhs.currency == nil, let leftDimension = lhs.dimension,
            let rightDimension = rhs.dimension
        {
            let dimension = leftDimension.adding(rightDimension, scale: dividing ? -1 : 1)
            let unit = (dividing ? nil : CalcUnits.productUnit(lhs, rhs)) ?? CalcUnits.baseUnits[dimension]
            if dimension == .scalar || unit != nil {
                let amount =
                    dividing
                    ? left.effective * lhs.factor / (right.effective * rhs.factor)
                    : left.effective * lhs.factor * right.effective * rhs.factor
                return derived(amount, dimension: dimension, unit: unit)
            }
        }
        var amount = right.effective
        if let source = rhs.currency, let target = lhs.currency, source != target {
            guard let factor = convertedCurrency(1, from: source, to: target), let dimension = rhs.dimension
            else { return nil }
            amount *= pow(factor, dimension.currency)
            rhs = UnitDef(
                rhs.symbol.replacingOccurrences(of: source.code, with: target.code), rhs.name,
                rhs.category, rhs.factor, dimension: dimension, currency: target)
        }
        guard let combined = CalcUnitExpression.combine(lhs, rhs, dividing: dividing),
            let dimension = combined.dimension
        else {
            return fail(L10n.string(CalculatorKey.errorUnitMultiplication, language: language))
        }
        if lhs.currency != nil || rhs.currency != nil { usedCurrencyRate = true }
        let base =
            dividing
            ? left.effective * lhs.factor / (amount * rhs.factor)
            : left.effective * lhs.factor * amount * rhs.factor
        let preferred = dividing ? nil : CalcUnits.productUnit(lhs, rhs)
        return derived(
            base, dimension: dimension, unit: preferred ?? CalcUnits.baseUnits[dimension] ?? combined)
    }

    /// 按量纲挑选基准单位，把基准量（base）折算为可展示的数值；无量纲则直接返回标量。
    private func derived(_ amount: Double, dimension: CalcDimension, unit: UnitDef? = nil) -> CalcValue? {
        guard amount.isFinite else { return nil }
        if dimension == .scalar { return CalcValue(amount: amount, kind: .scalar) }
        guard let unit = unit ?? CalcUnits.baseUnits[dimension] else { return nil }
        if dimension == CalcDimension(currency: 1), let currency = unit.currency {
            return CalcValue(amount: amount, kind: .currency(currency))
        }
        let output = amount / unit.factor
        return output.isFinite ? CalcValue(amount: output, kind: .unit(unit)) : nil
    }

    /// 幂运算：标量直接取幂，带单位时同时对量纲升幂；货币不支持幂。
    private func power(_ value: CalcValue, exponent: Double) -> CalcValue? {
        switch value.kind {
        case .scalar:
            return derived(pow(value.effective, exponent), dimension: .scalar)
        case .unit(let unit):
            guard let dimension = unit.dimension else { return nil }
            let raised = dimension.raised(to: exponent)
            return derived(
                pow(value.amount * unit.factor, exponent), dimension: raised,
                unit: CalcUnits.baseUnits[raised] ?? CalcUnitExpression.power(unit, exponent))
        case .currency:
            return nil
        }
    }

    /// 做除法并在结果非有限（如除以零）时返回 nil。
    private func finiteDivision(
        _ numerator: Double, _ denominator: Double, kind: CalcValue.Kind
    ) -> CalcValue? {
        let output = numerator / denominator
        return output.isFinite ? CalcValue(amount: output, kind: kind) : nil
    }

    /// 解析单个操作数：在基础值之后继续吸收单位、百分号与阶乘等后缀。
    private mutating func parseOperand() -> CalcValue? {
        guard var value = parsePrefix() else { return nil }
        while true {
            switch current {
            case .ident(let name):
                guard isScalar(value.kind), !value.isPercent, !value.isBoolean,
                    let kind = dimension(named: name)
                else { return value }
                value.kind = kind
                dimensionCount += 1
                position += 1
            case .op(let op) where op == .multiply || op == .divide:
                guard case .ident? = position + 1 < tokens.count ? tokens[position + 1] : nil,
                    let unit = arithmeticUnit(value.kind),
                    let next = CalcUnitExpression.factor(tokens, at: position + 1),
                    next.end == tokens.count || CalcQuantity.numberValue(tokens[next.end]) == nil,
                    let combined = CalcUnitExpression.combine(unit, next.unit, dividing: op == .divide)
                else { return value }
                value.kind = .unit(combined)
                if combined.currency != nil { usedCurrencyRate = true }
                dimensionCount += 1
                position = next.end
            case .op(.percent):
                guard isScalar(value.kind), !value.isPercent, !value.isBoolean else { return nil }
                value.isPercent = true
                position += 1
            case .op(.factorial):
                guard isScalar(value.kind), !value.isPercent, !value.isBoolean,
                    let factorial = CalcMath.factorial(value.amount)
                else { return nil }
                value.amount = factorial
                position += 1
            default:
                return value
            }
        }
    }

    /// 解析基础值：数字字面量、一元运算符、括号分组、常量、函数调用、单位与货币。
    private mutating func parsePrefix() -> CalcValue? {
        switch current {
        case .number(let value), .compactNumber(let value):
            position += 1
            return CalcValue(amount: value, kind: .scalar)
        case .intLiteral(let value, _):
            position += 1
            return CalcValue(amount: Double(value), kind: .scalar)
        case .op(.bitNot):
            position += 1
            guard let value = parseExpression(minBindingPower: Self.unaryBindingPower),
                isScalar(value.kind), !value.isBoolean,
                let result = CalcMath.bitwise(.bitNot, value.effective)
            else { return nil }
            return CalcValue(amount: result, kind: .scalar)
        case .op(.subtract):
            position += 1
            guard let value = parseExpression(minBindingPower: Self.unaryBindingPower), !value.isBoolean
            else { return nil }
            return CalcValue(amount: -value.effective, kind: value.kind)
        case .op(.add):
            position += 1
            guard let value = parseExpression(minBindingPower: Self.unaryBindingPower), !value.isBoolean
            else { return nil }
            return value
        case .op(.open):
            return parseGrouped()
        case .ident(let name):
            if name == "square" || name == "cube", position + 1 < tokens.count,
                tokens[position + 1] == .ident("root")
            {
                position += 2
                if current == .ident("of") { position += 1 }
                guard let value = parseOperand(), !value.isBoolean else { return nil }
                operationCount += 1
                if name == "square" { return power(value, exponent: 0.5) }
                guard
                    let result = power(
                        CalcValue(amount: abs(value.effective), kind: value.kind), exponent: 1.0 / 3)
                else { return nil }
                return CalcValue(amount: value.amount < 0 ? -result.amount : result.amount, kind: result.kind)
            }
            if let constant = CalcMath.constants[name] {
                position += 1
                return CalcValue(amount: constant, kind: .scalar)
            }
            if CalcMath.multipleArguments.contains(name), position + 1 < tokens.count,
                tokens[position + 1] == .op(.open)
            {
                return parseFunction(name)
            }
            if let function = CalcMath.functions[name] {
                position += 1
                guard let argument = parseOperand(), !argument.isBoolean else { return nil }
                operationCount += 1
                if isScalar(argument.kind) {
                    return derived(function(argument.effective), dimension: .scalar)
                }
                if case .unit(let unit) = argument.kind, unit.category == .angle,
                    ["sin", "cos", "tan", "cot", "sec", "csc"].contains(name)
                {
                    return derived(function(argument.amount * unit.factor), dimension: .scalar)
                }
                if name == "sqrt" { return power(argument, exponent: 0.5) }
                if name == "cbrt" {
                    guard
                        let result = power(
                            CalcValue(amount: abs(argument.amount), kind: argument.kind), exponent: 1.0 / 3)
                    else { return nil }
                    return CalcValue(
                        amount: argument.amount < 0 ? -result.amount : result.amount, kind: result.kind)
                }
                if ["abs", "floor", "ceil", "round", "trunc"].contains(name) {
                    return CalcValue(amount: function(argument.amount), kind: argument.kind)
                }
                return nil
            }
            guard CalcUnits.byName[name] == nil,
                let definition = CalcCurrency.byName[name],
                let amount = number(at: position + 1)
            else { return nil }
            position += 2
            recordCurrency(definition.code)
            dimensionCount += 1
            return CalcValue(amount: amount, kind: .currency(definition))
        default:
            return nil
        }
    }

    /// 把待比较的值换算到参考值的单位/货币下，无法比较则记录 issue 并返回 nil。
    private mutating func comparable(_ value: CalcValue, to reference: CalcValue) -> Double? {
        guard !value.isBoolean, !reference.isBoolean else { return nil }
        switch (reference.kind, value.kind) {
        case (.scalar, .scalar): return value.effective
        case (.unit(let target), .unit(let source)):
            guard target.isCompatible(with: source) else { return failComparison() }
            return convertedMeasurement(value.effective, from: source, to: target)
        case (.currency(let target), .currency(let source)):
            return convertedCurrency(value.effective, from: source, to: target)
        default: return failComparison()
        }
    }

    /// 记录量纲不同导致的比较失败。
    private mutating func failComparison() -> Double? {
        issue = L10n.string(CalculatorKey.errorCompareDimensions, language: language)
        return nil
    }

    /// 解析多参函数调用 `f(a, b, ...)`，根据函数名决定是否保留第一个参数的单位。
    private mutating func parseFunction(_ name: String) -> CalcValue? {
        position += 2
        var values: [CalcValue] = []
        while true {
            guard let value = parseExpression(minBindingPower: 0), !value.isBoolean else { return nil }
            values.append(value)
            if current == .op(.close) { position += 1; break }
            guard current == .comma else { return nil }
            position += 1
        }
        operationCount += 1
        let first = values[0]
        let keepsUnit = CalcMath.measurements.contains(name)
        var amounts: [Double] = []
        for (index, value) in values.enumerated() {
            if name == "round", index == 1 {
                guard isScalar(value.kind) else { return nil }
                amounts.append(value.effective)
            } else if keepsUnit {
                guard let amount = comparable(value, to: first) else { return nil }
                amounts.append(amount)
            } else {
                guard isScalar(value.kind) else { return nil }
                amounts.append(value.effective)
            }
        }
        guard let result = CalcMath.evaluate(name, amounts) else { return nil }
        return CalcValue(amount: result, kind: keepsUnit ? first.kind : .scalar)
    }

    /// 括号分组自成换算作用域，因此 `(20 sgd to usd) * 30` 会先换算再相乘。
    private mutating func parseGrouped() -> CalcValue? {
        guard let close = matchingParenthesis() else { return nil }
        position += 1
        let target = CalcQuantity.conversionTarget(tokens, from: position, to: close)
        guard let value = parseGroupedValue(upTo: target?.start ?? close)
        else { return nil }
        position = close + 1
        guard let target else { return value }
        operationCount += 1
        return converted(value, to: target.name)
    }

    /// 单独的单位或货币隐含数量 1，正如 `eur to usd` 已经做的那样。
    private mutating func parseGroupedValue(upTo end: Int) -> CalcValue? {
        if end - position == 1, case .ident(let name) = tokens[position],
            let kind = dimension(named: name)
        {
            position = end
            dimensionCount += 1
            return CalcValue(amount: 1, kind: kind)
        }
        if position < end, case .ident = tokens[position],
            let unit = CalcUnitExpression.parse(Array(tokens[position..<end]))
        {
            position = end
            dimensionCount += 1
            if unit.currency != nil { usedCurrencyRate = true }
            return CalcValue(amount: 1, kind: .unit(unit))
        }
        guard let value = parseExpression(minBindingPower: 0), position == end else { return nil }
        return value
    }

    /// 返回与当前位置的开括号配对的闭括号下标，无配对则 nil。
    private func matchingParenthesis() -> Int? {
        guard case .op(.open)? = current else { return nil }
        var depth = 0
        for index in position..<tokens.count {
            if case .op(.open) = tokens[index] { depth += 1 }
            if case .op(.close) = tokens[index] {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    /// 把值换算到目标名称（单位或货币），不兼容时回传友好错误。
    mutating func converted(
        _ value: CalcValue, to targetName: String
    ) -> CalcValue? {
        switch value.kind {
        case .scalar:
            return nil
        case .unit(let from):
            if let to = CalcUnits.byName[targetName] ?? compoundTarget(targetName) {
                guard from.isCompatible(with: to) else {
                    return fail(
                        cannotConvert(
                            from.category.displayName(language),
                            to.category.displayName(language)))
                }
                guard let output = convertedMeasurement(value.effective, from: from, to: to), output.isFinite
                else { return nil }
                return CalcValue(amount: output, kind: .unit(to))
            }
            if CalcCurrency.byName[targetName] != nil {
                return fail(
                    cannotConvert(
                        from.category.displayName(language),
                        CalcCurrency.categoryName(language)))
            }
            return nil
        case .currency(let from):
            if let to = CalcCurrency.byName[targetName] {
                guard let output = convertedCurrency(value.amount, from: from, to: to)
                else { return nil }
                return CalcValue(amount: output, kind: .currency(to))
            }
            if let to = CalcUnits.byName[targetName] {
                return fail(
                    cannotConvert(
                        CalcCurrency.categoryName(language),
                        to.category.displayName(language)))
            }
            return nil
        }
    }

    /// 目标名称由多个 token 拼成的复合单位（如 `m/s`）时，重新分词后解析。
    private func compoundTarget(_ name: String) -> UnitDef? {
        guard name.contains(" "), let tokens = CalcTokenizer.tokenize(name) else { return nil }
        return CalcUnitExpression.parse(tokens)
    }

    /// 单位之间的数值换算，带货币单位时先按汇率折算再换算。
    private mutating func convertedMeasurement(_ amount: Double, from: UnitDef, to: UnitDef) -> Double? {
        var amount = amount
        if let source = from.currency, let target = to.currency, source != target {
            guard let factor = convertedCurrency(1, from: source, to: target), let dimension = from.dimension
            else { return nil }
            amount *= pow(factor, dimension.currency)
        }
        return CalcQuantity.convertUnit(amount, from: from, to: to)
    }

    /// 把名称解析为对应的单位或货币值类型；货币会登记到 currencyCodes。
    private mutating func dimension(named name: String) -> CalcValue.Kind? {
        if let unit = CalcUnits.byName[name] {
            return .unit(unit)
        }
        guard let definition = CalcCurrency.byName[name] else { return nil }
        recordCurrency(definition.code)
        return .currency(definition)
    }

    /// 按汇率换算货币，并记录所使用的货币代码；汇率缺失/无报价时写入 issue。
    private mutating func convertedCurrency(
        _ amount: Double, from: CurrencyDef, to: CurrencyDef
    ) -> Double? {
        recordCurrency(from.code)
        recordCurrency(to.code)
        guard let rates else {
            issue = L10n.string(CalculatorKey.errorRatesUnavailable, language: language)
            return nil
        }
        guard rates.rate(for: from.code) != nil else {
            issue = noExchangeRate(from.code)
            return nil
        }
        guard rates.rate(for: to.code) != nil else {
            issue = noExchangeRate(to.code)
            return nil
        }
        return rates.convert(amount, from: from.code, to: to.code)
    }

    /// 记录本次求值用到的货币代码。
    private mutating func recordCurrency(_ code: String) {
        usedCurrency = true
        if !currencyCodes.contains(code) { currencyCodes.append(code) }
    }

    /// 读取指定位置 token 所代表的数值（若为数字）。
    private func number(at index: Int) -> Double? {
        guard index < tokens.count else { return nil }
        return CalcQuantity.numberValue(tokens[index])
    }

    /// 判断当前 token 是否可作为隐式加法的数量起点（数字字面量或「货币代码 + 数值」）。
    private func startsQuantity(_ token: CalcToken?) -> Bool {
        switch token {
        case .number, .compactNumber, .intLiteral:
            return true
        case .ident(let name):
            return CalcUnits.byName[name] == nil && CalcCurrency.byName[name] != nil
                && number(at: position + 1) != nil
        default:
            return false
        }
    }

    /// 判断值类型是否为纯标量。
    private func isScalar(_ kind: CalcValue.Kind) -> Bool {
        if case .scalar = kind { return true }
        return false
    }

    /// 量纲不一致的加法/减法提示。
    private func cannotAddOrSubtract(
        _ op: CalcOperator, _ lhs: String, _ rhs: String
    ) -> String {
        let key: CalculatorKey = op == .add ? .errorCannotAdd : .errorCannotSubtract
        return String(format: L10n.string(key, language: language), lhs, rhs)
    }

    /// 量纲不一致的换算提示。
    private func cannotConvert(_ from: String, _ to: String) -> String {
        String(
            format: L10n.string(CalculatorKey.errorCannotConvert, language: language), from, to)
    }

    /// 某货币没有报价的提示。
    private func noExchangeRate(_ code: String) -> String {
        String(format: L10n.string(CalculatorKey.errorNoRate, language: language), code)
    }

    /// 记录一条错误信息并返回 nil，供调用方向上传递失败。
    private mutating func fail(_ message: String) -> CalcValue? {
        issue = message
        return nil
    }
}
