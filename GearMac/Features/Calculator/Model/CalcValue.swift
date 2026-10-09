// 文件职责：定义计算器的中间值 `CalcValue`，承载数值、量纲种类与百分比/布尔标记。
// 分层：Model；纯数据值类型，不 import AppKit/SwiftUI。
import Foundation

/// 解析过程中的数值：数量 + 种类（标量/单位/货币）+ 百分比、布尔标记。
struct CalcValue {
    /// 值的量纲种类。
    enum Kind {
        case scalar
        case unit(UnitDef)
        case currency(CurrencyDef)
    }

    var amount: Double
    var kind: Kind
    var isPercent = false
    var isBoolean = false

    /// 去掉百分比语义后的实际数值（百分比除以 100）。
    var effective: Double {
        isPercent ? amount / 100 : amount
    }
}
