// 文件职责：定义单位换算与转换解析：基本单位表、单位乘积规则、显式/裸转换解析，以及无量词转换的目标单位表。
// 分层：Model；只依赖 Foundation 与同层单位目录，不 import AppKit/SwiftUI，不产生副作用。
import Foundation

/// 单位换算与转换短语解析的集中入口。
enum CalcUnits {
    /// 每个量纲选出的基准单位（用于复合单位的规范化）。
    static let baseUnits: [CalcDimension: UnitDef] = {
        var units: [CalcDimension: UnitDef] = [:]
        for name in [
            "m", "kg", "s", "m2", "m3", "b", "m/s", "pa", "bps", "m/s2", "n", "j", "w", "hz",
            "a", "v", "ohm", "as", "m3/s", "px", "px2", "ppi"
        ] {
            if let unit = byName[name], let dimension = unit.category.dimension {
                units[dimension] = unit
            }
        }
        return units
    }()

    /// 把「功率×时间」「电流×时间」等乘积折叠为 Wh/Ah 类衍生单位；不适用时返回 nil。
    static func productUnit(_ lhs: UnitDef, _ rhs: UnitDef) -> UnitDef? {
        let (measure, duration) = lhs.category == .time ? (rhs, lhs) : (lhs, rhs)
        guard duration.category == .time, duration.factor >= 60 else { return nil }
        switch measure.category {
        case .power: return byName[measure.factor >= 1000 ? "kwh" : "wh"]
        case .electricCurrent: return byName[measure.factor <= 0.001 ? "mah" : "ah"]
        default: return nil
        }
    }

    /// 显式转换（`a to b`）的解析结果：成功为 `.value`，量纲不一致为 `.mismatch`。
    enum ConversionParse: Equatable {
        case value(input: Double, from: UnitDef, to: UnitDef, output: Double)
        case mismatch(from: UnitDef, to: UnitDef)
    }

    /// 无量词转换到预设的对应单位；`compound` 表示需要组合输出（如英尺+英寸）。
    struct BareConversion: Equatable {
        let input: Double
        let from: UnitDef
        let to: UnitDef
        let output: Double
        let compound: Bool
    }

    /// `expr unit (to|in|->) unit` 形式的显式转换；从末尾匹配使 "in" 同时可作英寸。
    static func parseConversion(_ tokens: [CalcToken]) -> ConversionParse? {
        guard tokens.count >= 3, isConnector(tokens[tokens.count - 2]),
            case .ident(let toName) = tokens[tokens.count - 1],
            let to = byName[toName],
            case .ident(let fromName) = tokens[tokens.count - 3],
            let from = byName[fromName]
        else { return nil }

        let valueTokens = Array(tokens[0..<(tokens.count - 3)])
        let input: Double
        if valueTokens.isEmpty {
            input = 1
        } else if let value = CalcExpressionParser.scalar(valueTokens) {
            input = value
        } else {
            return nil
        }

        guard from.category == to.category else { return .mismatch(from: from, to: to) }
        let output = (input * from.factor + from.offset - to.offset) / to.factor
        guard output.isFinite else { return nil }
        return .value(input: input, from: from, to: to, output: output)
    }

    /// `day s` → 把 1 天换算成秒（`s`）；仅同量纲，避免两词搜索也产出卡片。
    static func parseUnitPairConversion(_ tokens: [CalcToken]) -> ConversionParse? {
        guard tokens.count == 2,
            case .ident(let fromName) = tokens[0], let from = byName[fromName],
            case .ident(let toName) = tokens[1], let to = byName[toName],
            from.category == to.category
        else { return nil }

        let output = (1 * from.factor + from.offset - to.offset) / to.factor
        guard output.isFinite else { return nil }
        return .value(input: 1, from: from, to: to, output: output)
    }

    /// `expr unit` 的无连接词转换；排除 c/f/k，使 `5k` 仍作为应用搜索。
    static func parseBareConversion(_ tokens: [CalcToken]) -> BareConversion? {
        guard tokens.count >= 2, case .ident(let fromName) = tokens[tokens.count - 1],
            !["c", "f", "k"].contains(fromName),
            let from = byName[fromName],
            let mapping = autoTargets[from.symbol],
            let to = byName[mapping.to]
        else { return nil }

        let valueTokens = Array(tokens[0..<(tokens.count - 1)])
        guard let input = CalcExpressionParser.scalar(valueTokens) else { return nil }

        let output = (input * from.factor + from.offset - to.offset) / to.factor
        guard output.isFinite else { return nil }
        return BareConversion(input: input, from: from, to: to, output: output, compound: mapping.compound)
    }

    /// 判断 token 是否为转换连接词（`->`、`to`、`in`）。
    static func isConnector(_ token: CalcToken) -> Bool {
        switch token {
        case .arrow, .ident("to"), .ident("in"): return true
        default: return false
        }
    }

    /// 每个单位的无量词对应目标；只有 `m→ft` 需要组合输出。
    static let autoTargets: [String: (to: String, compound: Bool)] = [
        // Length
        "mm": ("in", false), "cm": ("in", false), "m": ("ft", true), "km": ("mi", false),
        "dm": ("cm", false), "in": ("cm", false), "ft": ("m", false), "yd": ("m", false), "mi": ("km", false),
        // Weight
        "mg": ("g", false), "g": ("oz", false), "kg": ("lb", false), "oz": ("g", false),
        "lb": ("kg", false),
        // Temperature (bare form requires a spelled/°-prefixed alias — see parseBareConversion)
        "°C": ("f", false), "°F": ("c", false), "K": ("c", false),
        // Time
        "ms": ("s", false), "s": ("ms", false), "min": ("s", false), "hr": ("min", false),
        "day": ("hr", false), "week": ("day", false),
        "mo": ("day", false), "yr": ("day", false),
        "workdays": ("hr", false),
        // Area
        "mm²": ("in2", false), "cm²": ("in2", false), "m²": ("ft2", false), "km²": ("mi2", false),
        "in²": ("cm2", false), "ft²": ("m2", false), "yd²": ("m2", false), "mi²": ("km2", false),
        "acre": ("m2", false), "ha": ("acre", false),
        "dm²": ("cm2", false),
        // Volume
        "mL": ("floz", false), "L": ("gal", false), "cup": ("ml", false), "tbsp": ("ml", false),
        "tsp": ("ml", false), "gal": ("l", false), "qt": ("l", false), "pt": ("ml", false),
        "fl oz": ("ml", false),
        "cL": ("ml", false), "dL": ("ml", false),
        "mm³": ("ml", false), "cm³": ("ml", false), "dm³": ("l", false), "m³": ("l", false),
        "in³": ("ml", false), "ft³": ("l", false), "yd³": ("l", false),
        "L/s": ("l/min", false), "L/min": ("l/h", false), "L/h": ("l/min", false),
        "m³/s": ("l/s", false), "m³/h": ("l/min", false), "gal/min": ("l/min", false),
        // Digital storage
        "bit": ("b", false), "B": ("bit", false), "kB": ("kib", false), "MB": ("mib", false),
        "GB": ("gib", false), "TB": ("tib", false), "PB": ("tb", false), "KiB": ("kb", false),
        "MiB": ("mb", false), "GiB": ("gb", false), "TiB": ("tb", false),
        // Angle
        "deg": ("rad", false), "rad": ("deg", false), "grad": ("deg", false),
        "turn": ("deg", false), "arcmin": ("deg", false), "arcsec": ("deg", false),
        // Speed
        "km/h": ("mph", false), "mph": ("kmh", false), "m/s": ("kmh", false),
        "kn": ("kmh", false), "ft/s": ("mph", false),
        // Pressure
        "bar": ("psi", false), "psi": ("bar", false), "atm": ("psi", false),
        "mbar": ("psi", false), "kPa": ("psi", false), "hPa": ("psi", false),
        "mmHg": ("psi", false), "Torr": ("psi", false),
        // Data transfer rate
        "Mbps": ("kbps", false), "Gbps": ("mbps", false), "Kbps": ("bps", false),
        "bps": ("kbps", false), "Tbps": ("gbps", false),
        "Bps": ("bps", false), "kBps": ("kbps", false), "MBps": ("mbps", false),
        "GBps": ("gbps", false), "TBps": ("tbps", false),
        "Wh": ("kwh", false), "mWh": ("wh", false), "kWh": ("wh", false), "MWh": ("kwh", false),
        "W": ("kw", false), "mW": ("w", false), "kW": ("w", false), "MW": ("kw", false),
        "A": ("ma", false), "mA": ("a", false), "µA": ("ma", false), "MA": ("a", false),
        "V": ("mv", false), "mV": ("v", false), "kV": ("v", false), "MV": ("kv", false),
        "Ω": ("kohm", false), "mΩ": ("ohm", false), "kΩ": ("ohm", false), "MΩ": ("kohm", false),
        "As": ("ah", false), "Ah": ("mah", false), "mAh": ("ah", false), "MAh": ("ah", false),
        "px": ("rem", false), "rem": ("px", false), "em": ("px", false),
        "ppi": ("px/cm", false), "px/cm": ("ppi", false),
        "px/mm": ("ppi", false), "px/m": ("ppi", false)
    ]

    /// 单位名称（含别名）到单位定义的全局索引。
    static let byName = CalcUnitCatalog.makeIndex()
}
