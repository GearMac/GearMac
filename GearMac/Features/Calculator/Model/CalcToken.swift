// 文件职责：定义计算器分词后使用的 token 类型，覆盖数字、缩写数、进制字面量、标识符、运算符、箭头与逗号。
// 分层：Model；纯数据枚举，不 import AppKit/SwiftUI。
import Foundation

/// 计算器分词结果的最小单元。
enum CalcToken: Equatable, Sendable {
    case number(Double)
    /// 缩写数（`10k`、`1e5`、`2 million`）：单独成词时也保留类型区分，使其仍能生成结果卡片。
    case compactNumber(Double)
    /// 带进制前缀的整数字面量（0xff / 0b1010 / 0o777）：为进制转换保持精确值。
    case intLiteral(UInt64, base: CalcNumberBase)
    case ident(String)
    case op(CalcOperator)
    case arrow  // -> 或 →
    case comma
}
