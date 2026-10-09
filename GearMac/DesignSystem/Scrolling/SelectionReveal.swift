// 文件职责：根据选中行的已测量坐标，判断它是否仍需滚动以及应对齐到哪条边。
// 分层：Model/UI 判定辅助（纯函数，仅 import CoreGraphics）；本身不修改任何状态。
import CoreGraphics

/// 判断选中行是否仍需移动以及移到哪条边；输入坐标均来自实测。
enum SelectionReveal {
    enum Edge {
        case top
        case bottom
    }

    /// 仅因取整不应触发滚动，因此紧贴边缘的行也算作在带内。
    private static let tolerance: CGFloat = 0.5

    /// 返回行应对齐到的边；当它已在带内、无需移动时返回 nil。
    static func edge(rowTop: CGFloat, rowBottom: CGFloat, band: CGFloat) -> Edge? {
        // 比可见带还高的行只能显示开头，因此其顶部在带内即视为合格。
        if rowBottom - rowTop >= band {
            return rowTop < -tolerance || rowTop > tolerance ? .top : nil
        }
        if rowTop < -tolerance { return .top }
        if rowBottom > band + tolerance { return .bottom }
        return nil
    }
}
