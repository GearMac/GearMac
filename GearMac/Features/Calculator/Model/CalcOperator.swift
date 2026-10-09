// 文件职责：定义计算器支持的运算符枚举，及其优先级（binding power）与回显文本。
// 分层：Model；纯枚举，不 import AppKit/SwiftUI。
enum CalcOperator: Character, Sendable {
    case add = "+"
    case subtract = "-"
    case multiply = "*"
    case divide = "/"
    case power = "^"
    case factorial = "!"
    case percent = "%"
    case open = "("
    case close = ")"
    case bitAnd = "&"
    case bitOr = "|"
    case bitNot = "~"
    case bitXor = "⊻"
    case shiftLeft = "«"
    case shiftRight = "»"
    case equal = "≡"
    case notEqual = "≠"
    case less = "<"
    case greater = ">"
    case lessEqual = "≤"
    case greaterEqual = "≥"

    /// 运算符的绑定强度（优先级）：数值越大结合越紧；返回 nil 表示不参与二元表达式（如括号、阶乘）。
    var bindingPower: Int? {
        switch self {
        case .equal, .notEqual, .less, .greater, .lessEqual, .greaterEqual: return 2
        case .bitOr: return 5
        case .bitXor: return 6
        case .bitAnd: return 7
        case .shiftLeft, .shiftRight: return 8
        case .add, .subtract: return 10
        case .multiply, .divide: return 20
        case .power: return 30
        default: return nil
        }
    }

    /// 运算符的回显文本；部分符号展示时改用 ASCII 写法（如 `≡`→`==`）。
    var text: String {
        switch self {
        case .equal: return "=="
        case .shiftLeft: return "<<"
        case .shiftRight: return ">>"
        case .bitXor: return "xor"
        default: return String(rawValue)
        }
    }

}
