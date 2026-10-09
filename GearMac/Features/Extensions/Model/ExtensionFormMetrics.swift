// 文件职责：集中定义扩展表单所有控件共用的几何度量（尺寸、内缩、间距与 popover 布局尺寸）。
// 分层：Model；纯几何计算，不含视图代码，不 import AppKit/SwiftUI。
import Foundation

/// 所有表单控件共用的几何度量；保持纯粹，以便测试可直接驱动其布局规则。
struct ExtensionFormMetrics {
    /// 默认 Interface Size 下的 `Theme`，供纯布局规则及其测试使用。
    static let base = ExtensionFormMetrics(scale: 1)

    /// 归属此类型而非 `DesignSystem`：扩展永远不会改变启动器界面。
    let scale: CGFloat

    /// 单个控件的宽高，按扩展表单编写时所依据的比例给出。
    var controlWidth: CGFloat { scaled(360) }
    var controlHeight: CGFloat { scaled(32) }

    /// 让标签与居中的控件并排摆放而计算出的标签宽度。
    func labelWidth(for panelWidth: CGFloat, gap: CGFloat) -> CGFloat {
        max(0, ((panelWidth - controlWidth) / 2 - gap).rounded())
    }

    /// 文本区是一个“长高了的控件”：宽度与边框相同，只是有多行高。
    var textAreaHeight: CGFloat { scaled(78) }
    /// 控件自身文本到其圆角边缘的内缩。
    var textInset: CGFloat { scaled(10) }
    /// 各处统一的上内缩，使输入框与文本区的文字起始在同一条线上。
    var verticalInset: CGFloat { scaled(7) }
    /// 扣除 `NSTextView` 的行片段内边距，使其文本与输入框对齐。
    var textViewGutter: CGFloat { scaled(5) }
    /// 复选框绘制的方块尺寸，以及它到旁边标签的间距。
    var checkboxSize: CGFloat { scaled(14) }
    /// 带标签的行与下一行之间的间距，凭目测调出而非推导得出。
    var rowSpacing: CGFloat { scaled(18) }
    /// 分隔线两侧增加的间距，使一组内容与上一组区分开来。
    var separatorSpacing: CGFloat { scaled(4) }
    /// 首行之上、末行之下留出的空间，使两者都不贴近上下栏。
    var formVerticalPadding: CGFloat { scaled(16) }
    /// 控件与其弹出的 popover 之间的间距（无论 popover 从哪一侧弹出）。
    var popoverGap: CGFloat { scaled(6) }
    /// 重申 ⌘K 面板的行距：启动器的改动不得使表单位置发生变化。
    var popoverRowHeight: CGFloat { scaled(36) }
    var popoverRowSpacing: CGFloat { 1 }
    var popoverFadeBand: CGFloat { scaled(30) }
    /// 选择器列表中的分区标题；因是标签，比普通行更矮。
    var popoverSectionHeaderHeight: CGFloat { scaled(24) }
    /// 六行加第七行的一半，使长列表看起来可滚动，而不是被截断。
    var popoverVisibleRows: CGFloat { 6.5 }
    /// popover 打开时顶部的搜索或表达式输入行高度（若有）。
    var popoverSearchHeight: CGFloat { scaled(30) }
    /// 代替控件本应拥有却未获得的输入框编辑器而绘制的光标。
    var caretWidth: CGFloat { 1 }
    var caretHeight: CGFloat { scaled(15) }
    var caretBlink: TimeInterval { 0.5 }
    /// 空输入框提示文本左侧光标的偏移量，与输入框编辑器的位置一致。
    var caretPromptGap: CGFloat { scaled(2) }
    /// 四周均为 `Theme.Spacing.sm`，与 ⌘K 面板自身的内缩一致。
    var popoverPadding: CGFloat { scaled(6) }

    /// 取整：奇数列行距若出现半行，会使 popover 边缘落在半像素上。
    var popoverRowsMaxHeight: CGFloat {
        (popoverVisibleRows * (popoverRowHeight + popoverRowSpacing)).rounded()
    }

    /// 精确计算：每行高度已知，无需测量流程，也无需贪婪的滚动视图。
    func popoverListContentHeight(rows: Int, headers: Int = 0) -> CGFloat {
        guard rows > 0 else { return 0 }
        let pitch = popoverRowHeight + popoverRowSpacing
        let headings = CGFloat(headers) * (popoverSectionHeaderHeight + popoverRowSpacing)
        return CGFloat(rows) * pitch - popoverRowSpacing + headings
    }

    /// 列表高度：取内容高度与最大可见高度的较小值。
    func popoverListHeight(rows: Int, headers: Int = 0) -> CGFloat {
        min(popoverListContentHeight(rows: rows, headers: headers), popoverRowsMaxHeight)
    }

    /// 整个 popover 的高度：列表加上其上方的一切外壳部分。
    func popoverHeight(rows: Int, hasSearchField: Bool, headers: Int = 0) -> CGFloat {
        // 面板按此尺寸设定，因此空列表也必须把其绘制的行计入高度。
        let list = rows > 0 ? popoverListHeight(rows: rows, headers: headers) : popoverRowHeight
        let search = hasSearchField ? popoverSearchHeight : 0
        return list + search + popoverPadding * 2
    }

    /// 给定所属控件及周围可用空间时，popover 应处的位置。
    struct Placement: Equatable {
        /// popover 顶边，与测量锚点处于同一坐标系。
        let y: CGFloat
        /// 下方无空间、popover 改为向上弹出时为 true。
        let flipped: Bool
    }

    /// 空间足够时位于控件下方，否则位于上方；并做限制，使其永远不会超出容器。
    func placement(
        anchor: CGRect, popoverHeight: CGFloat, containerHeight: CGFloat
    ) -> Placement {
        let below = anchor.maxY + popoverGap
        let above = anchor.minY - popoverGap - popoverHeight
        // 与菜单一致的首选策略：向下弹出，除非底部会将其截断。
        if below + popoverHeight <= containerHeight {
            return Placement(y: below, flipped: false)
        }
        if above >= 0 {
            return Placement(y: above, flipped: true)
        }
        // 无论怎样都比容器高：显示其起始部分，因为选中项就在那里。
        return Placement(y: max(0, min(below, containerHeight - popoverHeight)), flipped: false)
    }

    /// 取整数点，与 `InterfaceMetrics` 一致：带小数的行距会使行边缘偏离像素。
    private func scaled(_ value: CGFloat) -> CGFloat {
        scale == 1 ? value : (value * scale).rounded()
    }
}
