// 文件职责：计算器的总入口：把原始输入按日期时间、时区、进制转换、单位/货币换算等语法依次尝试并产出 CalcResult。
// 分层：Model；所有环境事实（now、calendar、汇率、区域、数字格式）均由参数注入，不依赖全局状态。
import Foundation

/// 单次计算器求值结果，供启动器内联卡片展示。
struct CalcResult: Equatable, Sendable {
    /// 卡片主体：可复制的值，或面向用户的友好错误。
    enum Payload: Equatable, Sendable {
        /// `display` 已分组（"1,234,567"）；`copyText` 是同一答案但未分组。
        case value(display: String, copyText: String)
        /// 友好错误，仅用于明确的换算尝试——绝不用在写一半的表达式上。
        case error(message: String)

        /// 由数值生成「展示 + 复制」两段文本，可选后缀。
        static func number(_ value: Double, suffix: String = "") -> Self {
            let text = CalcFormatter.copyText(value)
            return .value(display: CalcFormatter.grouped(text) + suffix, copyText: text + suffix)
        }

        /// CSS 长度无空格复制（"24px"），以便答案直接粘贴进样式表。
        static func measurement(_ value: Double, unit: UnitDef) -> Self {
            let text = CalcFormatter.copyText(value)
            let copySeparator = unit.category == .pixels ? "" : " "
            return .value(
                display: "\(CalcFormatter.grouped(text)) \(unit.symbol)",
                copyText: text + copySeparator + unit.symbol)
        }
    }

    /// 被求值内容的规范化回显，展示在卡片左侧（"3×3"、"10 km"）。
    let expression: String
    /// 两侧下方的可选词名胶囊；纯算术时为 nil。
    let sourceBadge: String?
    let targetBadge: String?
    let payload: Payload
    /// 当复制文本作为查询重新输入时得不到同一答案则为 false：日期、时间、布尔值。
    let canChain: Bool

    init(
        expression: String, sourceBadge: String? = nil, targetBadge: String? = nil, payload: Payload,
        canChain: Bool = true
    ) {
        self.expression = expression
        self.sourceBadge = sourceBadge
        self.targetBadge = targetBadge
        self.payload = payload
        self.canChain = canChain
    }

    /// 仅对可复制的值成立；错误卡片既无主操作也无操作菜单。
    var isActionable: Bool {
        if case .value = payload { return true }
        return false
    }
}

/// 原始查询入口：能解答则返回结果，不是计算器输入则返回 nil。见 docs/features/calculator.md。
enum CalcEngine {
    /// 所有环境事实均由外部注入；产出规范化答案，交由 `format` 本地化。
    ///
    /// `language` 只影响卡片上的徽章与错误提示文字，默认英文，因此引擎的
    /// 纯英文输出（含依赖它的测试）保持不变。
    static func evaluate(
        _ raw: String, now: Date, calendar: Calendar, rates: CurrencyRates? = nil,
        region: String? = nil, format: CalcNumberFormat = .english,
        language: AppLanguage = .english
    ) -> CalcResult? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 256, let query = format.canonical(trimmed) else {
            return nil
        }
        if query.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }) {
            return CalcDateTime.namedMoment(query, now: now, calendar: calendar).map(unchained)
        }

        if let dateTime = CalcDateTime.evaluate(
            query, now: now, calendar: calendar, language: language)
        {
            return unchained(dateTime)
        }

        // 在分词之前：`5pm ldn in sf` 全是字母单词，分词器会拒绝。
        if let zone = CalcTimeZone.evaluate(
            query, now: now, calendar: calendar, language: language)
        {
            return unchained(zone)
        }

        guard let tokens = CalcTokenizer.tokenize(query), !tokens.isEmpty else { return nil }

        if let partial = partialResult(
            tokens, query: query, now: now, calendar: calendar, rates: rates, region: region,
            language: language)
        {
            return partial
        }

        // 单个字面量会被当成应用搜索，因此不出卡片——进制字面量（"0xff"）除外。
        if tokens.count == 1 {
            if case .intLiteral(let value, let base) = tokens[0], base != .decimal {
                let display = CalcFormatter.grouped(String(value))
                return CalcResult(
                    expression: query,
                    sourceBadge: base.name(language),
                    targetBadge: L10n.string(CalculatorKey.baseDecimal, language: language),
                    payload: .value(display: display, copyText: String(value)))
            }
            if case .compactNumber(let value) = tokens[0] {
                return CalcResult(
                    expression: query,
                    sourceBadge: expressionBadge(language),
                    targetBadge: resultBadge(language), payload: .number(value))
            }
            return nil
        }

        if let base = baseConversion(tokens, query: query, language: language) { return base }

        // 先跑带单位的算术，使 `pounds` 一类别名在多词表达式中仍能胜出。
        if let quantity = CalcQuantity.evaluate(
            tokens, query: query, rates: rates, region: region, language: language)
        {
            return quantity
        }

        // 换算必须在下面丢掉纯数字之前：`m to ft`、`day s` 都不带数字。
        if let conversion = CalcUnits.parseConversion(tokens) ?? CalcUnits.parseUnitPairConversion(tokens) {
            switch conversion {
            case .value(let input, let from, let to, let output):
                return CalcResult(
                    expression: "\(CalcFormatter.display(input)) \(from.symbol)",
                    sourceBadge: from.name,
                    targetBadge: to.name,
                    payload: .measurement(output, unit: to))
            case .mismatch(let from, let to):
                return CalcResult(
                    expression: query,
                    payload: .error(
                        message: cannotConvert(
                            from.category.displayName(language),
                            to.category.displayName(language), language)))
            }
        }

        // 放在单位之后，使 `10 pounds to kg` 仍按重量处理。
        if let conversion = CalcCurrency.parseConversion(
            tokens, rates: rates, language: language)
        {
            switch conversion {
            case .value(let input, let from, let to, let output):
                let amount = CalcFormatter.currency(output)
                return CalcResult(
                    expression: "\(CalcFormatter.display(input)) \(from.code)",
                    sourceBadge: from.name,
                    targetBadge: to.name,
                    payload: .value(
                        display: "\(CalcFormatter.grouped(amount)) \(to.code)",
                        copyText: "\(amount) \(to.code)"))
            case .mismatch(let from, let to):
                return CalcResult(
                    expression: query,
                    payload: .error(message: cannotConvert(from, to, language)))
            case .noRate(let code):
                return CalcResult(
                    expression: query,
                    payload: .error(
                        message: String(
                            format: L10n.string(CalculatorKey.errorNoRate, language: language),
                            code)))
            case .unavailable:
                return CalcResult(
                    expression: query,
                    payload: .error(
                        message: L10n.string(CalculatorKey.errorRatesUnavailable, language: language)))
            }
        }

        // 无关键词换算：`1m` → 英尺+英寸，`1hr` → 60 min。
        if let bare = CalcUnits.parseBareConversion(tokens) {
            let payload: CalcResult.Payload
            if bare.compound {
                let text = CalcFormatter.compoundFeetInches(bare.output, language: language)
                payload = .value(display: text, copyText: text)
            } else {
                payload = .measurement(bare.output, unit: bare.to)
            }
            return CalcResult(
                expression: "\(CalcFormatter.display(bare.input)) \(bare.from.symbol)",
                sourceBadge: bare.from.name,
                targetBadge: bare.to.name,
                payload: payload)
        }

        // 自然语言百分比：`20% off 500`、`50 as % of 200`。
        if let percent = CalcPercent.evaluate(tokens, query: query, language: language) {
            return percent
        }

        return nil
    }

    // MARK: - Partial expressions

    /// 尾随运算符时仍把最后一个完整前缀留在卡片上，便于用户继续输入。
    private static func partialResult(
        _ tokens: [CalcToken], query: String, now: Date, calendar: Calendar,
        rates: CurrencyRates?, region: String?, language: AppLanguage
    ) -> CalcResult? {
        guard let trailing = tokens.last, let operatorText = partialOperatorText(trailing) else {
            return nil
        }
        let prefixTokens = Array(tokens.dropLast())
        guard !prefixTokens.isEmpty else { return nil }
        if prefixTokens.count == 1, let value = decimalLiteral(prefixTokens[0]) {
            return CalcResult(
                expression: CalcFormatter.expression(query),
                sourceBadge: expressionBadge(language), targetBadge: resultBadge(language),
                payload: .number(value))
        }

        if let quantity = CalcQuantity.evaluate(
            prefixTokens, query: tokenQuery(prefixTokens), rates: rates, region: region,
            preserveStandaloneUnit: true, language: language)
        {
            return replacingExpression(
                quantity, with: "\(quantity.expression) \(operatorText)")
        }

        // 换算的回显会去掉目标，因此改用用户输入作为回显；两侧由徽标各自标明。
        if let complete = evaluate(
            tokenQuery(prefixTokens), now: now, calendar: calendar, rates: rates, region: region,
            language: language)
        {
            return replacingExpression(complete, with: CalcFormatter.expression(query))
        }

        guard let value = CalcExpressionParser.scalar(prefixTokens) else { return nil }
        return CalcResult(
            expression: CalcFormatter.expression(query),
            sourceBadge: expressionBadge(language), targetBadge: resultBadge(language),
            payload: .number(value))
    }

    /// 卡片左列的「表达式」徽章。
    private static func expressionBadge(_ language: AppLanguage) -> String {
        L10n.string(CalculatorKey.badgeExpression, language: language)
    }

    /// 卡片右列的「结果」徽章。
    private static func resultBadge(_ language: AppLanguage) -> String {
        L10n.string(CalculatorKey.badgeResult, language: language)
    }

    /// 量纲不一致时的友好错误。
    private static func cannotConvert(
        _ from: String, _ to: String, _ language: AppLanguage
    ) -> String {
        String(
            format: L10n.string(CalculatorKey.errorCannotConvert, language: language), from, to)
    }

    /// 取尾随运算符的展示文本（`*`→`×`、`/`→`÷`），非运算符则返回 nil。
    private static func partialOperatorText(_ token: CalcToken) -> String? {
        guard case .op(let op) = token else { return nil }
        switch op {
        case .multiply: return "×"
        case .divide: return "÷"
        case .add, .subtract, .power: return String(op.rawValue)
        default: return nil
        }
    }

    /// 把 token 流重建成等价的输入串，用于求值其完整前缀。
    private static func tokenQuery(_ tokens: [CalcToken]) -> String {
        tokens.map { token in
            switch token {
            case .number(let value), .compactNumber(let value):
                if let integer = Int64(exactly: value) { return String(integer) }
                return String(value)
            case .intLiteral(let value, let base):
                // 保留进制前缀，使 `0xff -` 仍报告十六进制来源而非十进制。
                return base.prefix + String(value, radix: base.rawValue)
            case .ident(let name):
                return name
            case .op(let op):
                return op.text
            case .arrow:
                return "->"
            case .comma:
                return ","
            }
        }.joined(separator: " ")
    }

    /// 仅替换 expression 字段，保留其余字段的副本。
    private static func replacingExpression(_ result: CalcResult, with expression: String) -> CalcResult {
        CalcResult(
            expression: expression,
            sourceBadge: result.sourceBadge,
            targetBadge: result.targetBadge,
            payload: result.payload,
            canChain: result.canChain)
    }

    /// 标记结果不可链式编辑（日期、时间、布尔等）。
    private static func unchained(_ result: CalcResult) -> CalcResult {
        CalcResult(
            expression: result.expression,
            sourceBadge: result.sourceBadge,
            targetBadge: result.targetBadge,
            payload: result.payload,
            canChain: false)
    }

    // MARK: - Number bases

    /// `255 to hex`、`2*128 to hex`：左侧是表达式，形如 `CalcUnits.parseConversion`。
    private static func baseConversion(
        _ tokens: [CalcToken], query: String, language: AppLanguage
    ) -> CalcResult? {
        guard tokens.count >= 3, CalcUnits.isConnector(tokens[tokens.count - 2]),
            case .ident(let name) = tokens[tokens.count - 1], let target = CalcNumberBase(name: name)
        else { return nil }

        let valueTokens = Array(tokens[0..<(tokens.count - 2)])
        let literalText = query.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? query
        let source: UInt64
        let sourceBadge: String
        let sourceText: String
        if valueTokens.count == 1, case .intLiteral(let value, let base) = valueTokens[0] {
            source = value
            sourceBadge = base.name(language)
            sourceText = literalText
        } else if valueTokens.count == 1, let value = decimalLiteral(valueTokens[0]),
            value >= 0, value.rounded() == value, value <= 9_007_199_254_740_992
        {
            source = UInt64(value)
            sourceBadge = L10n.string(CalculatorKey.baseDecimal, language: language)
            sourceText = literalText
        } else if let value = CalcExpressionParser.scalar(valueTokens),
            value >= 0, value.rounded() == value, value <= 9_007_199_254_740_992
        {
            source = UInt64(value)
            sourceBadge = L10n.string(CalculatorKey.baseDecimal, language: language)
            sourceText = CalcFormatter.grouped(String(source))
        } else {
            return nil
        }

        let output =
            target == .decimal
            ? CalcFormatter.grouped(String(source))
            : target.prefix + String(source, radix: target.rawValue, uppercase: true)
        return CalcResult(
            expression: sourceText,
            sourceBadge: sourceBadge,
            targetBadge: target.name(language),
            payload: .value(
                display: output, copyText: output.replacingOccurrences(of: ",", with: "")))
    }

    // 纯十进字面量的两种写法——"255" 与紧凑的 "10k"——都原样回显。
    /// 把十进制字面量（普通数字或紧凑数字）取为 Double，其他 token 返回 nil。
    private static func decimalLiteral(_ token: CalcToken) -> Double? {
        switch token {
        case .number(let value), .compactNumber(let value): return value
        default: return nil
        }
    }

}
