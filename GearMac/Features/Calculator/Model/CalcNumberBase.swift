// 文件职责：定义计算器支持的进制枚举及其名称、字面量前缀。
// 分层：Model；纯枚举，不 import AppKit/SwiftUI，不产生副作用。
enum CalcNumberBase: Int, Sendable {
    case binary = 2
    case octal = 8
    case decimal = 10
    case hexadecimal = 16

    /// 用名称构造进制：支持 `bin`/`oct`/`dec`/`hex` 及其全称，无法识别时返回 nil。
    init?(name: String) {
        switch name {
        case "bin", "binary": self = .binary
        case "oct", "octal": self = .octal
        case "dec", "decimal": self = .decimal
        case "hex", "hexadecimal": self = .hexadecimal
        default: return nil
        }
    }

    /// 进制的显示名（如 `Hexadecimal`），按界面语言解析。
    func name(_ language: AppLanguage) -> String {
        let key: CalculatorKey =
            switch self {
            case .binary: .baseBinary
            case .octal: .baseOctal
            case .decimal: .baseDecimal
            case .hexadecimal: .baseHexadecimal
            }
        return L10n.string(key, language: language)
    }

    /// 该进制的字面量前缀（如 `0x`）；十进制无前缀。
    var prefix: String {
        switch self {
        case .binary: "0b"
        case .octal: "0o"
        case .decimal: ""
        case .hexadecimal: "0x"
        }
    }
}
