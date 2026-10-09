// 文件职责：验证 PaletteRowIndex 的扁平索引与渲染网格坐标之间的映射，以及启动器、剪贴板、计算器历史、卸载、表情等各屏幕分区形状下的解析、反解与夹取。
// 分层：测试 harness；直接编译真实源码，仅断言纯索引逻辑，不依赖 AppKit/SwiftUI。

import Foundation

/// 校验 PaletteRowIndex 索引映射的测试入口。
@main
@MainActor
struct PaletteRowIndexTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func expect(_ actual: PaletteRow?, _ expected: PaletteRow?, _ message: String) {
        expect(
            actual == expected,
            "\(message) — got \(String(describing: actual)), want \(String(describing: expected))")
    }

    static func expect(_ actual: Int?, _ expected: Int?, _ message: String) {
        expect(
            actual == expected,
            "\(message) — got \(String(describing: actual)), want \(String(describing: expected))")
    }

    /// 扁平索引在渲染网格中的落点：它所在的视觉行，以及该行内的列。
    static func cell(_ flat: Int, counts: [Int], columns: Int) -> (row: Int, column: Int) {
        var row = 0
        var start = 0
        for count in counts {
            if flat < start + count {
                let local = flat - start
                return (row + local / columns, local % columns)
            }
            row += (count + columns - 1) / columns
            start += count
        }
        return (row, 0)
    }

    /// 某个视觉行容纳多少单元格——分区的最后一行通常是残缺行。
    static func rowLength(_ row: Int, counts: [Int], columns: Int) -> Int {
        var first = 0
        for count in counts {
            let rows = (count + columns - 1) / columns
            if row < first + rows { return min(count - (row - first) * columns, columns) }
            first += rows
        }
        return 0
    }

    /// 表情屏幕的约定：网格移动沿同一扁平行序前进一个视觉行。
    static func expectGrid(_ counts: [Int], columns: Int, _ label: String) {
        let grid = EmojiGridGeometry(counts: counts, columns: columns)
        let index = PaletteRowIndex(sectionCounts: counts)
        let lastRow = counts.reduce(0) { $0 + ($1 + columns - 1) / columns } - 1
        for flat in 0..<index.count {
            let here = cell(flat, counts: counts, columns: columns)
            let down = grid.down(from: flat)
            let up = grid.up(from: flat)
            expect(index.row(at: down) != nil, "\(label): down from \(flat) stays on a row")
            expect(index.row(at: up) != nil, "\(label): up from \(flat) stays on a row")
            expect(down >= flat, "\(label): down from \(flat) never moves backwards")
            expect(up <= flat, "\(label): up from \(flat) never moves forwards")
            let below = cell(down, counts: counts, columns: columns)
            let above = cell(up, counts: counts, columns: columns)
            // 保留列位置，除非落到更短的行上，此时夹取到该行的最后一个单元格。
            let lastBelow = rowLength(here.row + 1, counts: counts, columns: columns) - 1
            let lastAbove = rowLength(here.row - 1, counts: counts, columns: columns) - 1
            expect(
                down == flat || below.column == min(here.column, lastBelow),
                "\(label): down from \(flat) keeps its column, clamping onto a shorter row")
            expect(
                up == flat || above.column == min(here.column, lastAbove),
                "\(label): up from \(flat) keeps its column, clamping onto a shorter row")
            expect(
                down == flat ? here.row == lastRow : below.row == here.row + 1,
                "\(label): down from \(flat) moves exactly one visual row, or stops at the last")
            expect(
                up == flat ? here.row == 0 : above.row == here.row - 1,
                "\(label): up from \(flat) moves exactly one visual row, or stops at the first")
            // ←/→ 只是沿同一扁平顺序步进一格，并在两端夹取。
            expect(
                index.clamped(flat + 1) == min(flat + 1, index.count - 1),
                "\(label): → steps one cell from \(flat)")
            expect(
                index.clamped(flat - 1) == max(flat - 1, 0), "\(label): ← steps one cell from \(flat)")
        }
    }

    /// 每个索引都能解析，且解析后再反解会回到起始索引。
    static func expectRoundTrip(_ index: PaletteRowIndex, _ label: String) {
        for flat in 0..<index.count {
            guard let row = index.row(at: flat) else {
                expect(false, "\(label): index \(flat) resolves to a row")
                continue
            }
            switch row {
            case .calculator:
                expect(flat == 0, "\(label): the calculator card only ever sits at index 0")
            case .element(let section, let offset):
                expect(
                    index.index(section: section, offset: offset), flat,
                    "\(label): section \(section) offset \(offset) inverts to \(flat)")
            }
        }
    }

    /// 运行全部索引映射用例并汇总通过/失败数。
    static func main() {
        // 空列表：什么都解析不出来，但夹取仍产出可用的选中项。
        let empty = PaletteRowIndex(sectionCounts: [])
        expect(empty.count == 0, "an empty screen has no rows")
        expect(empty.row(at: 0), nil, "an empty screen resolves no index")
        expect(empty.clamped(0) == 0, "the clamp holds at zero with no rows")
        expect(empty.clamped(7) == 0, "an out-of-range selection clamps to zero with no rows")
        expect(empty.index(section: 0, offset: 0), nil, "an empty screen has no section 0")

        // 所有分区都为空时，该屏幕依然是空屏幕。
        let allEmptySections = PaletteRowIndex(sectionCounts: [0, 0, 0])
        expect(allEmptySections.count == 0, "empty sections contribute no rows")
        expect(allEmptySections.row(at: 0), nil, "empty sections resolve no index")

        // 单个分区、无计算器卡片：扁平索引就是分区内的偏移。
        let single = PaletteRowIndex(sectionCounts: [3])
        expect(single.count == 3, "one section of 3 is 3 rows")
        expect(single.row(at: 0), .element(section: 0, offset: 0), "index 0 is the first result")
        expect(single.row(at: 1), .element(section: 0, offset: 1), "index 1 is the second result")
        expect(single.row(at: 2), .element(section: 0, offset: 2), "index 2 is the last result")
        expect(single.row(at: 3), nil, "one past the end resolves to nothing")
        expect(single.row(at: -1), nil, "a negative index resolves to nothing")
        expectRoundTrip(single, "single section")

        // 计算器卡片占据索引 0，并把每个结果后移一位。
        let withCalc = PaletteRowIndex(hasCalculator: true, sectionCounts: [3])
        expect(withCalc.count == 4, "the calculator card adds one row")
        expect(withCalc.row(at: 0), .calculator, "the calculator card occupies index 0")
        expect(
            withCalc.row(at: 1), .element(section: 0, offset: 0),
            "the first result follows the calculator card")
        expect(
            withCalc.row(at: 3), .element(section: 0, offset: 2),
            "the last result sits at count - 1")
        expect(withCalc.row(at: 4), nil, "one past the end resolves to nothing")
        expect(
            withCalc.index(section: 0, offset: 0), 1,
            "a card present shifts the first result's index to 1")
        expectRoundTrip(withCalc, "single section with calculator")

        // 没有结果时，计算器卡片自身可被选中。
        let calcOnly = PaletteRowIndex(hasCalculator: true, sectionCounts: [])
        expect(calcOnly.count == 1, "a lone calculator card is one row")
        expect(calcOnly.row(at: 0), .calculator, "a lone calculator card is the whole list")
        expect(calcOnly.clamped(9) == 0, "the clamp lands on the card")

        // 多个分区：表头不可选中，因此不占用索引。
        let sections = PaletteRowIndex(sectionCounts: [2, 1, 3])
        expect(sections.count == 6, "three sections of 2, 1 and 3 are 6 selectable rows")
        expect(sections.row(at: 1), .element(section: 0, offset: 1), "the first section's last row")
        expect(
            sections.row(at: 2), .element(section: 1, offset: 0),
            "the next index crosses into the second section, skipping its header")
        expect(
            sections.row(at: 3), .element(section: 2, offset: 0),
            "a one-row section is crossed in a single step")
        expect(sections.row(at: 5), .element(section: 2, offset: 2), "the final row of the last section")
        expect(sections.row(at: 6), nil, "one past the last section resolves to nothing")
        expectRoundTrip(sections, "three sections")

        // 中间的空分区被整体跳过，而不消耗索引。
        let gapped = PaletteRowIndex(sectionCounts: [2, 0, 2])
        expect(gapped.count == 4, "an empty section contributes no rows")
        expect(
            gapped.row(at: 2), .element(section: 2, offset: 0),
            "an empty section is stepped over, not landed in")
        expect(gapped.index(section: 1, offset: 0), nil, "an empty section has no valid offset")
        expectRoundTrip(gapped, "empty middle section")

        // 分区加计算器卡片——启动器的真实形状。
        let launcher = PaletteRowIndex(hasCalculator: true, sectionCounts: [2, 1, 3])
        expect(launcher.count == 7, "the card plus six results")
        expect(launcher.row(at: 0), .calculator, "the card still leads")
        expect(
            launcher.row(at: 3), .element(section: 1, offset: 0),
            "a section crossing accounts for the card")
        expect(
            launcher.index(section: 2, offset: 2), 6,
            "the last row of the last section is the last index")
        expectRoundTrip(launcher, "launcher shape")

        // 空查询启动器：先是收藏，然后按 AppIndex 切片顺序为每类各一个分区。
        let launcherSections = PaletteRowIndex(sectionCounts: [3, 12, 5, 2, 4, 6, 8, 1, 7])
        expect(launcherSections.sectionCounts.count == 9, "the empty-query launcher has nine sections")
        expect(launcherSections.count == 48, "every section's rows are selectable, its header is not")
        expect(
            launcherSections.row(at: 0), .element(section: 0, offset: 0),
            "a pinned favourite is the first row of the whole list")
        expect(
            launcherSections.row(at: 2), .element(section: 0, offset: 2),
            "the last favourite still precedes Applications")
        expect(
            launcherSections.row(at: 3), .element(section: 1, offset: 0),
            "Applications begins where Favorites ends, with no index spent on the header")
        expect(launcherSections.index(section: 8, offset: 6), 47, "the last command is the last index")
        expect(launcherSections.index(section: 9, offset: 0), nil, "there is no tenth section")
        expectRoundTrip(launcherSections, "launcher nine sections")

        // 没有收藏：Applications 领衔，其后每个分区整体上移。
        let launcherNoFavorites = PaletteRowIndex(sectionCounts: [0, 12, 5, 2, 4, 6, 8, 1, 7])
        expect(
            launcherNoFavorites.row(at: 0), .element(section: 1, offset: 0),
            "an empty Favorites section is stepped over, not landed in")
        expect(
            launcherNoFavorites.index(section: 8, offset: 6), 44,
            "dropping three favourites moves every later row up by three")
        expectRoundTrip(launcherNoFavorites, "launcher without favourites")

        // 隐藏的分类会整段消失；剩余的行保持原有顺序。
        let launcherHidden = PaletteRowIndex(sectionCounts: [3, 12, 0, 2, 0, 6, 0, 1, 7])
        expect(launcherHidden.count == 31, "a hidden category contributes no rows")
        expect(
            launcherHidden.row(at: 15), .element(section: 3, offset: 0),
            "Quicklinks follows Applications directly once System Settings is hidden")
        expectRoundTrip(launcherHidden, "launcher with hidden categories")

        // 输入查询后九个分区收拢为一个列表，由卡片领衔。
        let launcherQuery = PaletteRowIndex(hasCalculator: true, sectionCounts: [9])
        expect(launcherQuery.count == 10, "the card plus nine ranked matches")
        expect(launcherQuery.row(at: 0), .calculator, "a typed calculation leads the results")
        expect(
            launcherQuery.row(at: 1), .element(section: 0, offset: 0),
            "the best-ranked match follows the card")
        expect(launcherQuery.index(section: 0, offset: 8), 9, "the last match is the last index")
        expectRoundTrip(launcherQuery, "launcher with a card")

        // ↵、⌘↵ 与 ⌃⇧Q 都经由该索引解析，因此只有索引 0 会是卡片。
        for flat in 0..<launcherQuery.count {
            expect(
                (launcherQuery.row(at: flat) == .calculator) == (flat == 0),
                "launcher: index \(flat) is the card only at 0")
        }

        // 计算结果不匹配任何 app：卡片是唯一可选中行。
        let launcherCardOnly = PaletteRowIndex(hasCalculator: true, sectionCounts: [0])
        expect(launcherCardOnly.count == 1, "a card with no matches is one row")
        expect(launcherCardOnly.row(at: 0), .calculator, "the card is the whole list")
        expect(launcherCardOnly.clamped(6) == 0, "a stale selection clamps back onto the card")

        // 遍历九个分区：单独存在与缺失两种情形，带卡片与不带卡片两种配置。
        for hasCalculator in [false, true] {
            for section in 0..<9 {
                var only = [Int](repeating: 0, count: 9)
                only[section] = 3
                let alone = PaletteRowIndex(hasCalculator: hasCalculator, sectionCounts: only)
                expect(
                    alone.index(section: section, offset: 0), hasCalculator ? 1 : 0,
                    "section \(section) alone starts at the head of the list")
                expectRoundTrip(alone, "only section \(section) calc=\(hasCalculator)")
                var missing = [Int](repeating: 2, count: 9)
                missing[section] = 0
                let gapped = PaletteRowIndex(hasCalculator: hasCalculator, sectionCounts: missing)
                expect(
                    gapped.count == (hasCalculator ? 1 : 0) + 16,
                    "hiding section \(section) drops exactly its rows")
                expect(gapped.index(section: section, offset: 0), nil, "section \(section) has no rows")
                expectRoundTrip(gapped, "section \(section) hidden calc=\(hasCalculator)")
            }
        }

        // 两端夹取，带卡片与不带卡片。
        for index in [single, withCalc, sections, launcher, gapped] {
            expect(index.clamped(-1) == 0, "a selection below zero clamps to the first row")
            expect(index.clamped(-99) == 0, "a far-negative selection clamps to the first row")
            expect(
                index.clamped(index.count) == index.count - 1,
                "a selection one past the end clamps to the last row")
            expect(
                index.clamped(index.count + 50) == index.count - 1,
                "a far-past-the-end selection clamps to the last row")
            expect(
                index.row(at: index.clamped(Int.max)) != nil,
                "a clamped selection always resolves to a row")
            expect(
                index.row(at: index.clamped(Int.min)) != nil,
                "a clamped negative selection always resolves to a row")
        }

        // 越界反解绝不凭空造出索引。
        expect(sections.index(section: 3, offset: 0), nil, "there is no fourth section")
        expect(sections.index(section: -1, offset: 0), nil, "there is no section before the first")
        expect(sections.index(section: 0, offset: 2), nil, "an offset past a section's rows is nothing")
        expect(sections.index(section: 0, offset: -1), nil, "a negative offset is nothing")

        // 卸载屏幕：单一扁平分区、无卡片，表头不占索引。
        let uninstall = PaletteRowIndex(sectionCounts: [4])
        expect(uninstall.count == 4, "the uninstall screen indexes its candidates alone")
        expect(uninstall.row(at: 0), .element(section: 0, offset: 0), "the first candidate leads")
        expect(
            uninstall.row(at: 3), .element(section: 0, offset: 3),
            "the summary header consumes no index")
        expect(uninstall.row(at: 4), nil, "one past the last candidate resolves to nothing")
        expectRoundTrip(uninstall, "uninstall shape")

        // 过滤到只剩一个候选时，高亮停在该项，而不是越到末尾之外。
        let uninstallFiltered = PaletteRowIndex(sectionCounts: [1])
        expect(uninstallFiltered.clamped(3) == 0, "a filter that leaves one row pulls selection to it")

        // 带选项的参数：其选项就是行，与任何其他列表一致。
        let argumentOptions = PaletteRowIndex(sectionCounts: [3])
        expect(argumentOptions.count == 3, "the choice list is the argument form's only section")
        expect(
            argumentOptions.row(at: 2), .element(section: 0, offset: 2), "the last choice is selectable")
        expectRoundTrip(argumentOptions, "argument options shape")

        // 自由文本参数不渲染任何行，选中项必须仍停在 0。
        let argumentFreeText = PaletteRowIndex(sectionCounts: [0])
        expect(argumentFreeText.count == 0, "a free-text argument has nothing to index")
        expect(argumentFreeText.row(at: 0), nil, "a free-text argument resolves no index")
        expect(argumentFreeText.clamped(0) == 0, "selection stays at zero with no choices")
        expect(argumentFreeText.clamped(5) == 0, "a stale selection clamps back to zero")

        // 剪贴板屏幕：置顶分区位于按日期分桶之上，且没有计算器卡片。
        let clipboard = PaletteRowIndex(sectionCounts: [2, 5, 3])
        expect(clipboard.count == 10, "the clipboard indexes pinned and dated entries alike")
        expect(clipboard.row(at: 1), .element(section: 0, offset: 1), "the last pinned entry")
        expect(
            clipboard.row(at: 2), .element(section: 1, offset: 0),
            "the first dated entry follows the Pinned section")
        expect(
            clipboard.index(section: 0, offset: 0), 0,
            "pinning lifts a row to the head of the whole list")
        expectRoundTrip(clipboard, "clipboard shape")

        // 计算器历史：先是实时答案卡片，然后每个日期桶一个分区。
        let historyCard = PaletteRowIndex(hasCalculator: true, sectionCounts: [3, 2])
        expect(historyCard.count == 6, "the card plus five stored entries")
        expect(historyCard.row(at: 0), .calculator, "a typed calculation leads the history")
        expect(
            historyCard.row(at: 1), .element(section: 0, offset: 0),
            "the newest stored entry follows the card")
        expect(
            historyCard.row(at: 4), .element(section: 1, offset: 0),
            "crossing into the next bucket accounts for the card")
        expect(historyCard.index(section: 1, offset: 1), 5, "the oldest entry is the last index")
        expectRoundTrip(historyCard, "history with a card")

        // ⌘⌫ 经由该索引解析，因此只有 `.element` 会是删除目标。
        for flat in 0..<historyCard.count {
            expect(
                (historyCard.row(at: flat) == .calculator) == (flat == 0),
                "history: index \(flat) is the card only at 0")
        }

        // 清空输入框会移除卡片，索引 0 变为最新的已存条目。
        let historyNoCard = PaletteRowIndex(sectionCounts: [3, 2])
        expect(historyNoCard.count == 5, "without a card the stored entries are the whole list")
        expect(historyNoCard.row(at: 0), .element(section: 0, offset: 0), "the newest entry leads")
        expectRoundTrip(historyNoCard, "history without a card")

        // 尚无历史时输入计算式：卡片是唯一可选中行。
        let historyCardOnly = PaletteRowIndex(hasCalculator: true, sectionCounts: [0])
        expect(historyCardOnly.count == 1, "a card with no stored entries is one row")
        expect(historyCardOnly.row(at: 0), .calculator, "the card is the whole list")
        expect(historyCardOnly.row(at: 1), nil, "nothing follows a lone card")
        expect(historyCardOnly.clamped(4) == 0, "a stale selection clamps back onto the card")

        // 表情网格：8、20、5 个单元格的分区铺在 8 列上，与选择器的渲染一致。
        let emoji = PaletteRowIndex(sectionCounts: [8, 20, 5])
        expect(emoji.count == 33, "the grid indexes every cell of every section")
        expect(
            emoji.row(at: 8), .element(section: 1, offset: 0),
            "the flat index crosses into the next section's first cell")
        expectRoundTrip(emoji, "emoji grid shape")
        let emojiGrid = EmojiGridGeometry(counts: [8, 20, 5], columns: 8)
        expect(
            emojiGrid.down(from: 3), 8 + 3,
            "down from the last row of a section lands in the same column of the next")
        expect(
            emojiGrid.up(from: 8 + 3), 3,
            "up from a section's first row lands in the same column of the previous")
        expect(emojiGrid.down(from: 8 + 16 + 3), 28 + 3, "the third section is entered by column")
        expect(emojiGrid.up(from: 28 + 3), 8 + 16 + 3, "and left again by the same column")
        // `EmojiGrid.sections` 会跳过空分类，因此这里的形状都不含空分区。
        expectGrid([8, 20, 5], columns: 8, "emoji grid")
        expectGrid([33], columns: 8, "emoji search results")
        expectGrid([1], columns: 8, "a single emoji result")

        // 穷举：每种网格形状都只移动一个视觉行，并停留在扁平顺序之内。
        for a in 1...9 {
            for b in 1...9 {
                for c in 1...9 {
                    expectGrid([a, b, c], columns: 8, "grid [\(a),\(b),\(c)]")
                }
            }
        }

        // 穷举：在一批形状上，每个扁平索引都与可见行顺序一一对应。
        for hasCalculator in [false, true] {
            for a in 0...3 {
                for b in 0...3 {
                    for c in 0...3 {
                        let index = PaletteRowIndex(
                            hasCalculator: hasCalculator, sectionCounts: [a, b, c])
                        let label = "shape calc=\(hasCalculator) [\(a),\(b),\(c)]"
                        expect(
                            index.count == (hasCalculator ? 1 : 0) + a + b + c,
                            "\(label): the row count is the card plus every section")
                        expectRoundTrip(index, label)
                        let rows = (0..<index.count).compactMap(index.row(at:))
                        expect(
                            Set(rows.map(String.init(describing:))).count == rows.count,
                            "\(label): no two indices resolve to the same row")
                    }
                }
            }
        }

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
