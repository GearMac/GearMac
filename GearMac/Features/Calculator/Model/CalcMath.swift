// 文件职责：提供计算器的数学函数表（三角、对数、取整等）、常量表，以及多参数函数与按位运算的求值实现。
// 分层：Model；纯静态表与纯函数，不 import AppKit/SwiftUI，不产生副作用。
import Foundation

/// 计算器的数学运算库：集中提供单参数函数、常量、多参数函数与按位运算的求值入口。
enum CalcMath {
    /// 单参数函数表：函数名（小写）映射到实现，供 `isFunction` 与 `evaluate` 查询。
    static let functions: [String: @Sendable (Double) -> Double] = [
        "sqrt": { sqrt($0) }, "log": { log10($0) }, "ln": { log($0) }, "sin": { sin($0) },
        "cos": { cos($0) }, "tan": { tan($0) }, "abs": { abs($0) }, "floor": { floor($0) },
        "ceil": { ceil($0) }, "round": { $0.rounded() },
        "cot": { 1 / tan($0) }, "sec": { 1 / cos($0) }, "csc": { 1 / sin($0) },
        "asin": { asin($0) }, "acos": { acos($0) }, "atan": { atan($0) },
        "arcsin": { asin($0) }, "arccos": { acos($0) }, "arctan": { atan($0) },
        "sinh": { sinh($0) }, "cosh": { cosh($0) }, "tanh": { tanh($0) },
        "asinh": { asinh($0) }, "acosh": { acosh($0) }, "atanh": { atanh($0) },
        "cbrt": { cbrt($0) }, "exp": { exp($0) }, "log2": { log2($0) },
        "sign": { $0 > 0 ? 1 : ($0 < 0 ? -1 : 0) }, "trunc": { $0.rounded(.towardZero) }
    ]

    /// 常量表：`pi`/`π`、`e`、`tau`/`τ`、`phi`。
    static let constants: [String: Double] = [
        "pi": .pi, "π": .pi, "e": M_E, "tau": 2 * .pi, "τ": 2 * .pi, "phi": (1 + sqrt(5.0)) / 2
    ]

    /// 非负整数的阶乘；170! 是 Double 能表示的最后一个阶乘值。
    static func factorial(_ value: Double) -> Double? {
        guard value >= 0, value.rounded() == value, value <= 170 else { return nil }
        var result = 1.0
        var next = 2.0
        while next <= value {
            result *= next
            next += 1
        }
        return result
    }

    /// 需要多个参数的函数名集合；它们不能按单参数函数表直接求值。
    static let multipleArguments: Set<String> = [
        "hypot", "round", "log", "gcd", "lcm", "atan2", "pow", "root", "fmod",
        "min", "max", "sum", "avg", "mean", "average"
    ]
    /// 在多参数函数中保留单位的函数名；其参数需同量纲可比，结果沿用首个参数的单位。
    static let measurements: Set<String> = [
        "hypot", "round", "min", "max", "sum", "avg", "mean", "average"
    ]

    /// 判断名字是否是已知函数（单参数表中的函数或多参数函数）。
    static func isFunction(_ name: String) -> Bool {
        CalcMath.functions[name] != nil || multipleArguments.contains(name)
    }

    /// 按函数名对若干数值求值；输入非有限、参数个数不符或结果非有限时返回 nil。
    static func evaluate(_ name: String, _ values: [Double]) -> Double? {
        guard !values.isEmpty, values.allSatisfy(\.isFinite) else { return nil }
        let first = values[0]
        let result: Double
        switch name {
        case "min": result = values.min() ?? first
        case "max": result = values.max() ?? first
        case "sum": result = values.reduce(0, +)
        case "avg", "mean", "average": result = values.reduce(0) { $0 + $1 / Double(values.count) }
        case "hypot": result = values.reduce(0) { hypot($0, $1) }
        case "gcd", "lcm":
            var accumulator: Int64 = name == "gcd" ? 0 : 1
            for value in values {
                guard let integer = exactInteger(value) else { return nil }
                let positive = abs(integer)
                var a = accumulator
                var b = positive
                while b != 0 { (a, b) = (b, a % b) }
                if name == "gcd" {
                    accumulator = a
                } else if a == 0 {
                    accumulator = 0
                } else {
                    let product = (accumulator / a).multipliedReportingOverflow(by: positive)
                    guard !product.overflow else { return nil }
                    accumulator = product.partialValue
                }
            }
            return abs(Double(accumulator)) < 9_007_199_254_740_992 ? Double(accumulator) : nil
        default:
            if values.count == 1, let function = CalcMath.functions[name] {
                result = function(first)
            } else {
                guard values.count == 2 else { return nil }
                let second = values[1]
                switch name {
                case "round":
                    guard let digits = Int(exactly: second), (-308...308).contains(digits) else { return nil }
                    let factor = pow(10, second)
                    let scaled = first * factor
                    result = scaled.isFinite ? scaled.rounded() / factor : first
                case "log":
                    guard first > 0, second > 0, second != 1 else { return nil }
                    result = log(first) / log(second)
                case "atan2": result = atan2(first, second)
                case "pow": result = pow(first, second)
                case "root":
                    guard second != 0 else { return nil }
                    result =
                        first < 0 && second.truncatingRemainder(dividingBy: 2) != 0
                            && second.rounded() == second
                        ? -pow(-first, 1 / second) : pow(first, 1 / second)
                case "fmod": result = first.truncatingRemainder(dividingBy: second)
                default: return nil
                }
            }
        }
        return result.isFinite ? result : nil
    }

    /// 把 Double 无损转换为 Int64；超出 2^53 安全整数范围或存在小数时返回 nil。
    private static func exactInteger(_ value: Double) -> Int64? {
        guard abs(value) < 9_007_199_254_740_992 else { return nil }
        return Int64(exactly: value)
    }

    /// 执行按位运算（与/或/异或/取反/移位）；操作数非整数、位移越界或结果超范围时返回 nil。
    static func bitwise(_ op: CalcOperator, _ left: Double, _ right: Double = 0) -> Double? {
        guard let lhs = exactInteger(left), let rhs = exactInteger(right) else { return nil }
        let result: Int64
        switch op {
        case .bitAnd: result = lhs & rhs
        case .bitOr: result = lhs | rhs
        case .bitXor: result = lhs ^ rhs
        case .bitNot: result = ~lhs
        case .shiftLeft:
            guard (0..<64).contains(rhs) else { return nil }
            result = lhs << rhs
            guard result >> rhs == lhs else { return nil }
        case .shiftRight:
            guard (0..<64).contains(rhs) else { return nil }
            result = lhs >> rhs
        default: return nil
        }
        return abs(Double(result)) < 9_007_199_254_740_992 ? Double(result) : nil
    }
}
