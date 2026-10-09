// 文件职责：定义货币与汇率的数据模型（CurrencyDef、CurrencyRates），并维护货币名称查找表（byName，含 CLDR/ISO 修正与加密货币）与「表达式 → 货币换算」的解析逻辑。
// 分层：Model；仅用静态数据与纯函数，不发起网络请求，汇率快照由 CurrencyRateStore 注入。
import Foundation

/// 一种货币：code 是金额旁展示的 ISO 4217 代码，name 是卡片徽标使用的完整名称。
struct CurrencyDef: Equatable, Sendable {
    let code: String  // "EUR"
    let name: String  // "Euro"
}

/// 汇率快照，数值表示 1 单位 `base` 能兑换的对应货币数量。由 `CurrencyRateStore` 拉取，引擎自身从不请求。
struct CurrencyRates: Codable, Equatable, Sendable {
    let base: String
    let rates: [String: Double]
    /// 下载时间：用于判断汇率是否过期，同时充当 `CalcMemo` 的缓存键。
    let fetchedAt: Date

    func rate(for code: String) -> Double? {
        if let rate = rates[code], rate > 0, rate.isFinite { return rate }
        return code == base ? 1 : nil
    }

    /// 以 base 货币为中介做交叉汇率换算。
    func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard let source = rate(for: from), let target = rate(for: to) else { return nil }
        let output = amount / source * target
        return output.isFinite ? output : nil
    }
}

/// 货币换算的入口命名空间：名称表、加密货币定义与换算解析。
enum CalcCurrency {
    /// 货币换算解析的结果，供引擎转成卡片或错误提示。
    enum ConversionParse: Equatable {
        case value(input: Double, from: CurrencyDef, to: CurrencyDef, output: Double)
        /// 一侧是货币、另一侧是计量单位，例如 `10 usd to kg`。
        case mismatch(from: String, to: String)
        /// 两侧都是货币，但汇率快照没有其中一种的报价。
        case noRate(code: String)
        /// 从未下载过任何汇率快照（首次运行或始终离线）。
        case unavailable
    }

    /// 类型不匹配提示中使用的类别标签，与 `UnitCategory.displayName` 保持一致。
    static func categoryName(_ language: AppLanguage) -> String {
        L10n.string(CalculatorKey.categoryCurrency, language: language)
    }

    /// 解析 `expr currency (to|in|->) currency` 形式，结构与 `CalcUnits.parseConversion` 相同，并在其后执行。
    static func parseConversion(
        _ tokens: [CalcToken], rates: CurrencyRates?, language: AppLanguage = .english
    ) -> ConversionParse? {
        let tokens = amountFirst(tokens)
        guard tokens.count >= 3, CalcUnits.isConnector(tokens[tokens.count - 2]),
            case .ident(let toName) = tokens[tokens.count - 1],
            case .ident(let fromName) = tokens[tokens.count - 3]
        else { return nil }

        // 某一侧既不是货币也不是单位时视为拼写错误，不产出卡片。
        switch (byName[fromName], byName[toName]) {
        case (nil, nil):
            return nil
        case (.some, nil):
            guard let to = CalcUnits.byName[toName] else { return nil }
            return .mismatch(from: categoryName(language), to: to.category.displayName(language))
        case (nil, .some):
            guard let from = CalcUnits.byName[fromName] else { return nil }
            return .mismatch(from: from.category.displayName(language), to: categoryName(language))
        case (let from?, let to?):
            let valueTokens = Array(tokens[0..<(tokens.count - 3)])
            let input: Double
            if valueTokens.isEmpty {
                input = 1
            } else if let value = CalcExpressionParser.scalar(valueTokens) {
                input = value
            } else {
                return nil
            }

            guard let rates else { return .unavailable }
            guard rates.rate(for: from.code) != nil else { return .noRate(code: from.code) }
            guard rates.rate(for: to.code) != nil else { return .noRate(code: to.code) }
            guard let output = rates.convert(input, from: from.code, to: to.code) else {
                return .noRate(code: to.code)
            }
            return .value(input: input, from: from, to: to, output: output)
        }
    }

    /// 货币金额常把符号写在最前（如 `€20`），这里换回「金额 货币」的顺序。
    private static func amountFirst(_ tokens: [CalcToken]) -> [CalcToken] {
        guard tokens.count >= 2, case .ident(let name) = tokens[0], byName[name] != nil,
            numberToken(tokens[1])
        else { return tokens }
        var reordered = tokens
        reordered.swapAt(0, 1)
        return reordered
    }

    /// 判断 token 是否为普通数字或紧凑数字（如 `10k`）。
    private static func numberToken(_ token: CalcToken) -> Bool {
        switch token {
        case .number, .compactNumber:
            return true
        default:
            return false
        }
    }

    /// 手写维护：CLDR 不会把某个名词分配给多种货币。见 docs/features/calculator.md
    private static let contested: [String: [String]] = [
        "USD": ["dollar", "dollars"],  // 22 种货币共用
        "CHF": ["franc", "francs"],  // 10 种
        "GBP": ["pound", "pounds"],  // 9 种
        "MXN": ["peso", "pesos"],  // 8 种
        "INR": ["rupee", "rupees"],  // 6 种
        "KES": ["shilling", "shillings"],  // 4 种
        "AED": ["dirham", "dirhams"],  // 2 种
        "KRW": ["won"],  // 2 种
        "RON": ["leu", "lei"],  // 2 种
        "RUB": ["ruble", "rubles"],  // 2 种
        "SAR": ["riyal", "riyals"]  // 2 种
    ]

    /// CLDR 与 ISO 4217 名称不一致时采用 ISO 4217 的名称；以标准为准。
    private static let isoNames: [String: [String]] = [
        "CNY": ["rmb", "renminbi"]  // ISO 4217 names CNY "Yuan Renminbi"; CLDR says "Chinese Yuan"
    ]

    /// 日常拼写依据 CLDR 的货币符号、而非 ISO 4217 代码的货币代码。见 docs/features/calculator.md
    private static let signCodes: [String: [String]] = [
        "TWD": ["ntd"]  // CLDR writes TWD "NT$", so Taiwan types the sign's code, not TWD
    ]

    /// 手写维护：没有任何标准机构为加密货币命名。见 docs/features/calculator.md
    static let crypto: [(code: String, name: String, aliases: [String])] = [
        ("ADA", "Cardano", ["cardano"]),
        ("AVAX", "Avalanche", ["avalanche"]),
        ("BCH", "Bitcoin Cash", []),
        ("BNB", "BNB", ["binance"]),
        ("BSV", "Bitcoin SV", []),
        ("BTC", "Bitcoin", ["bitcoin"]),
        ("DASH", "Dash", []),
        ("DOGE", "Dogecoin", ["dogecoin"]),
        ("DOT", "Polkadot", ["polkadot"]),
        ("EOS", "EOS", []),
        ("ETC", "Ethereum Classic", []),
        ("ETH", "Ethereum", ["ethereum", "ether"]),
        ("LTC", "Litecoin", ["litecoin"]),
        ("LUNA", "Terra", ["terra"]),
        ("NEO", "Neo", []),
        ("POL", "Polygon", ["polygon"]),
        ("SHIB", "Shiba Inu", ["shiba"]),
        ("SOL", "Solana", ["solana"]),
        ("TRX", "TRON", ["tron"]),
        ("USDT", "Tether", ["tether"]),
        ("XLM", "Stellar", ["stellar"]),
        ("XMR", "Monero", ["monero"]),
        ("XRP", "XRP", ["ripple"])
    ]

    /// `CurrencyRateStore` 依据它构造请求，因此两个列表不会各自漂移。
    static let cryptoCodes: [String] = crypto.map(\.code)

    /// 小写标识符到货币定义的查找表；先生成数据、后覆盖手写表，因此上面的手写表优先。
    static let byName: [String: CurrencyDef] = {
        var defs: [String: CurrencyDef] = [:]
        var table: [String: CurrencyDef] = [:]
        defs.reserveCapacity(CurrencyData.all.count + crypto.count)
        table.reserveCapacity(CurrencyData.all.count + CurrencyData.aliases.count + crypto.count)
        for entry in CurrencyData.all {
            let def = CurrencyDef(code: entry.code, name: entry.name)
            defs[entry.code] = def
            table[entry.code.lowercased()] = def
        }
        for (word, code) in CurrencyData.aliases { table[word] = defs[code] }
        // 放在生成的名称之后，使行情代码优先：`sol` 指 Solana，而 `soles` 仍归 PEN。
        for entry in crypto {
            let def = CurrencyDef(code: entry.code, name: entry.name)
            defs[entry.code] = def
            table[entry.code.lowercased()] = def
            for word in entry.aliases { table[word] = def }
        }
        for (code, words) in contested {
            guard let def = defs[code] else { continue }
            for word in words { table[word] = def }
        }
        for (code, words) in isoNames {
            guard let def = defs[code] else { continue }
            for word in words { table[word] = def }
        }
        for (code, words) in signCodes {
            guard let def = defs[code] else { continue }
            for word in words { table[word] = def }
        }
        return table
    }()
}
