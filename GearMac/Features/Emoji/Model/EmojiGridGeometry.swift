// 文件职责：表情网格的分区扁平索引导航，把上下移动映射到跨分区的单元格索引。
// 分层：Model；纯几何计算，不依赖视图或平台框架。
/// 在分区行上的扁平索引导航；上下移动会跨分区保持列位置。
struct EmojiGridGeometry {
    let counts: [Int]
    let columns: Int
    private let starts: [Int]

    /// 根据各分区元素数与列数预计算每个分区的起始扁平索引。
    init(counts: [Int], columns: Int = 8) {
        self.counts = counts
        self.columns = columns
        var starts: [Int] = []
        var running = 0
        for count in counts {
            starts.append(running)
            running += count
        }
        self.starts = starts
    }

    /// 返回扁平索引所在的非空分区；不在任何分区内则为 nil。
    private func section(of sel: Int) -> Int? {
        for (index, start) in starts.enumerated().reversed() where sel >= start {
            return counts[index] > 0 && sel < start + counts[index] ? index : nil
        }
        return nil
    }

    /// 向下移动一格；到本分区末尾时换到下一分区的相同列（不超出其元素数）。
    func down(from sel: Int) -> Int {
        guard let s = section(of: sel) else { return sel }
        let local = sel - starts[s]
        let candidate = local + columns
        if candidate < counts[s] { return starts[s] + candidate }
        // 本分区末行不满时先钳到最后一个格子，再溢出到下一分区。
        if local / columns < (counts[s] - 1) / columns { return starts[s] + counts[s] - 1 }
        guard s + 1 < counts.count else { return sel }
        return starts[s + 1] + min(local % columns, counts[s + 1] - 1)
    }

    /// 向上移动一格；到本分区首行时换到上一分区的相同列（不超出其元素数）。
    func up(from sel: Int) -> Int {
        guard let s = section(of: sel) else { return sel }
        let local = sel - starts[s]
        if local - columns >= 0 { return starts[s] + local - columns }
        guard s > 0 else { return sel }
        let previousCount = counts[s - 1]
        let lastRowStart = ((previousCount - 1) / columns) * columns
        return starts[s - 1] + min(lastRowStart + local % columns, previousCount - 1)
    }

    /// 固定项消失后保持相同的视觉位置，不可行时回退到前一个可用位置。
    static func selectionAfterRemovingPin(at index: Int, remainingCount: Int) -> Int {
        min(max(index, 0), max(remainingCount - 1, 0))
    }

    /// 分区重写后跟进选中字形的位置，找不到时钳到末尾。
    static func selection(
        _ sel: Int, afterSectionAt start: Int, changesFrom old: [String], to new: [String]
    ) -> Int {
        guard sel >= start else { return sel }
        let offset = sel - start
        guard offset < old.count else { return sel + new.count - old.count }
        if let moved = new.firstIndex(of: old[offset]) { return start + moved }
        return start + min(offset, max(new.count - 1, 0))
    }
}
