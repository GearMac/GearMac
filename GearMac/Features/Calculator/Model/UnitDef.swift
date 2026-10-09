// 文件职责：定义单个单位的数据模型，含符号、展示名、分类与换算参数。
// 分层：Model；不可变值语义的引用类型，不得 import AppKit/SwiftUI。
import Foundation

/// 单位定义：以仿射映射换算到基础单位，即 `base = value * factor + offset`；仅温度会用到 offset。
/// 持有符号、展示名、分类与换算参数，并判定与其他单位是否可换算。
final class UnitDef: Equatable, Sendable {
    let symbol: String  // 规范展示形式："mi"、"°F"、"GiB"
    let name: String  // 卡片徽标用的完整名称："Miles"、"Fahrenheit"
    let category: UnitCategory
    let factor: Double
    let offset: Double
    let derivedDimension: CalcDimension?
    let currency: CurrencyDef?

    /// 该单位的量纲：优先使用派生量纲，否则回退到所属分类的量纲。
    var dimension: CalcDimension? { derivedDimension ?? category.dimension }

    /// 相等判定：同一实例，或符号、名称、分类、换算参数与量纲均一致。
    static func == (lhs: UnitDef, rhs: UnitDef) -> Bool {
        lhs === rhs
            || (lhs.symbol == rhs.symbol && lhs.name == rhs.name && lhs.category == rhs.category
                && lhs.factor == rhs.factor && lhs.offset == rhs.offset
                && lhs.derivedDimension == rhs.derivedDimension
                && lhs.currency == rhs.currency)
    }

    /// 判断两个单位是否属于同一可换算域（同分类，或量纲相同）。
    func isCompatible(with other: UnitDef) -> Bool {
        if category != .compound, category == other.category { return true }
        guard let dimension else { return false }
        return dimension == other.dimension
    }

    /// 创建单位定义；`dimension` 用于复合单位等需要覆盖所属分类量纲的场景。
    @inline(never) init(
        _ symbol: String, _ name: String, _ category: UnitCategory, _ factor: Double,
        offset: Double = 0, dimension: CalcDimension? = nil, currency: CurrencyDef? = nil
    ) {
        self.symbol = symbol
        self.name = name
        self.category = category
        self.factor = factor
        self.offset = offset
        derivedDimension = dimension
        self.currency = currency
    }
}
