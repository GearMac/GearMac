// 文件职责：用「计算器卡片 + 各分组行数」描述屏幕的可见行顺序，并在扁平索引与 (section, offset) 之间互转。
// 分层：Model（纯值类型，仅 import Foundation）；分组标题不参与选中，也不占索引位。
import Foundation

/// 扁平选中索引解析后的结果。分组标题不可选中，也不占索引位。
enum PaletteRow: Equatable {
    case calculator
    case element(section: Int, offset: Int)
}

/// 屏幕可见行的顺序：若有计算器卡片则位于索引 0，其后依次是各个分组。
struct PaletteRowIndex: Equatable {
    let hasCalculator: Bool
    let sectionCounts: [Int]

    init(hasCalculator: Bool = false, sectionCounts: [Int]) {
        self.hasCalculator = hasCalculator
        self.sectionCounts = sectionCounts
    }

    /// 可见行总数（计算器卡片 + 各分组行数之和）。
    var count: Int { (hasCalculator ? 1 : 0) + sectionCounts.reduce(0, +) }

    /// 屏幕实际高亮到的选中项：越界的值会被夹取到结果范围内。
    func clamped(_ selection: Int) -> Int {
        count == 0 ? 0 : min(max(selection, 0), count - 1)
    }

    /// 把扁平索引解析为具体行；索引越界时返回 nil。
    func row(at index: Int) -> PaletteRow? {
        guard index >= 0, index < count else { return nil }
        if hasCalculator, index == 0 { return .calculator }
        var offset = hasCalculator ? index - 1 : index
        for (section, sectionCount) in sectionCounts.enumerated() {
            if offset < sectionCount { return .element(section: section, offset: offset) }
            offset -= sectionCount
        }
        return nil
    }

    /// `row(at:)` 的逆运算——用于列表自身变动后，屏幕应把高亮放在哪个索引。
    func index(section: Int, offset: Int) -> Int? {
        guard sectionCounts.indices.contains(section), offset >= 0,
            offset < sectionCounts[section]
        else { return nil }
        let preceding = sectionCounts[..<section].reduce(0, +)
        return (hasCalculator ? 1 : 0) + preceding + offset
    }
}
