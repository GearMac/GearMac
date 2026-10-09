// 文件职责：为 `Grid` 提供基于扁平索引的键盘导航几何计算，使 ↑/↓ 按整行移动并保持所在列。
// 分层：Model；纯索引计算，不 import AppKit/SwiftUI。
/// 对 `Grid` 各分区做扁平索引导航，使 ↑/↓ 整行移动并保持列位置。
struct ExtensionGridGeometry {
    /// 每个分区中可选单元格的数量，按可见顺序排列；空分区从不计入。
    let counts: [Int]
    /// 每行可容纳的列数。
    let columns: Int
    /// 每个分区起始的扁平索引。
    private let starts: [Int]

    init(counts: [Int], columns: Int) {
        self.counts = counts
        self.columns = max(1, columns)
        var starts: [Int] = []
        var running = 0
        for count in counts {
            starts.append(running)
            running += count
        }
        self.starts = starts
    }

    /// 单元格总数。
    var cellCount: Int { counts.reduce(0, +) }

    /// 向下移动一行的目标索引（越过分区时保持列对齐）。
    func down(from index: Int) -> Int {
        guard let section = section(of: index) else { return index }
        let local = index - starts[section]
        let below = local + columns
        if below < counts[section] { return starts[section] + below }
        // 末行较短时，把选中项留在本分区内，而不是跳过它。
        if local / columns < (counts[section] - 1) / columns {
            return starts[section] + counts[section] - 1
        }
        guard section + 1 < counts.count else { return index }
        return starts[section + 1] + min(local % columns, counts[section + 1] - 1)
    }

    /// 向上移动一行的目标索引（越过分区时落在上一分区末行）。
    func up(from index: Int) -> Int {
        guard let section = section(of: index) else { return index }
        let local = index - starts[section]
        if local >= columns { return starts[section] + local - columns }
        guard section > 0 else { return index }
        let previous = counts[section - 1]
        let lastRowStart = ((previous - 1) / columns) * columns
        return starts[section - 1] + min(lastRowStart + local % columns, previous - 1)
    }

    /// 返回该扁平索引所属的分区序号；索引不属任何分区时返回 nil。
    private func section(of index: Int) -> Int? {
        for (position, start) in starts.enumerated().reversed() where index >= start {
            return index < start + counts[position] ? position : nil
        }
        return nil
    }
}
