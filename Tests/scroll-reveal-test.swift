// 文件职责：SelectionReveal（选中行滚动揭示逻辑）的独立测试 harness，验证可见带内的行保持不动、越界行对齐到相应边缘、底栏背后条带与超高行的处理。
// 分层：测试 harness；使用调色板真实比例常量做纯几何断言，无 UI 依赖。
import CoreGraphics
import Foundation

/// 带内的行不得滚动；位于底栏背后的行则必须滚动。
@main
@MainActor
struct SelectionRevealTests {
    static var failures = 0
    static var passes = 0

    /// 调色板的真实比例：两条栏之间 369pt 的可见带，行高 36pt。
    static let band: CGFloat = 369
    static let rowHeight: CGFloat = 36

    /// 断言：实际边缘与期望一致则计入通过，否则打印失败并计数。
    static func expect(
        _ actual: SelectionReveal.Edge?, _ expected: SelectionReveal.Edge?, _ message: String
    ) {
        if actual == expected {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message) — got \(String(describing: actual)), want \(expected as Any)")
        }
    }

    /// 构造一个高 `rowHeight`、顶端位于 `top` 的行，模拟列表行报告自身几何的方式。
    static func edge(rowTop top: CGFloat, height: CGFloat = rowHeight) -> SelectionReveal.Edge? {
        SelectionReveal.edge(rowTop: top, rowBottom: top + height, band: band)
    }

    static func main() {
        rowsInsideTheBandStayPut()
        rowsPastAnEdgeAlignToIt()
        theStripBehindTheBottomBar()
        aRowTallerThanTheBand()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Leaving a visible row alone

    /// 带内的行不需要滚动。
    static func rowsInsideTheBandStayPut() {
        expect(edge(rowTop: 0), nil, "the first row at the band's top edge needs no scroll")
        expect(edge(rowTop: 180), nil, "nor does a row in the middle")
        expect(edge(rowTop: band - rowHeight), nil, "nor one flush with the bottom edge")
        // 舍入不能造成抖动：几何数据是以小数点传入的。
        expect(edge(rowTop: -0.3), nil, "a third of a point over the top edge is still inside")
        expect(edge(rowTop: band - rowHeight + 0.3), nil, "and so is a third of a point under")
    }

    // MARK: - Moving a row that has left the band

    /// 越过边界的行对齐到被越过的那条边。
    static func rowsPastAnEdgeAlignToIt() {
        expect(edge(rowTop: -1), .top, "a row a point above the band aligns to the top")
        expect(edge(rowTop: -rowHeight), .top, "so does one scrolled a full row above it")
        expect(edge(rowTop: -4000), .top, "and one far above, after a jump to the list's start")
        expect(edge(rowTop: band - rowHeight + 1), .bottom, "a row a point below aligns to the bottom")
        expect(edge(rowTop: band + 4000), .bottom, "and so does one far below it")
    }

    // MARK: - The strip the bug lived in

    /// 底栏背后条带内的行会被移入可见带。
    static func theStripBehindTheBottomBar() {
        // 来自应用实测：可见带止于 369，而 369…405 虽可见却被底栏遮住。
        expect(edge(rowTop: 369), .bottom, "the row that lands in the strip is moved into the band")
        expect(edge(rowTop: 333), nil, "while the row flush above the strip is left alone")
    }

    // MARK: - Rows that cannot fit

    /// 高于可见带的行只能显示开头，因此稳定状态是对齐到顶部。
    static func aRowTallerThanTheBand() {
        // 只有行的开头能显示出来，因此对齐顶部是稳定终态，而不是循环的起点。
        expect(edge(rowTop: 0, height: band + 100), nil, "a too-tall row pinned at the top is settled")
        expect(edge(rowTop: -50, height: band + 100), .top, "one scrolled past its top is pulled back")
        expect(edge(rowTop: 20, height: band + 100), .top, "and one hanging below the top is too")
    }
}
