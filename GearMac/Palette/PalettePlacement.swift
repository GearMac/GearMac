// 文件职责：调色板的纯几何运算（默认位置、偏移换算、吸附与恢复校验）以及菜单窗口角的定位计算。
// 分层：Model；纯函数，所有屏幕信息均注入，可在无显示器环境下测试。
import CoreGraphics

/// 纯几何逻辑，所有屏幕事实均由外部注入，因此能脱离显示器进行测试。
enum PalettePlacement {
    /// 允许进入吸附的最大速度（点/秒）。
    static let maxSnapEntrySpeedPointsPerSecond: CGFloat = 600

    /// 未经调整的默认位置：水平居中，顶边从顶部下移一段比例，向下增长。
    static func defaultAnchor(
        in visibleFrame: CGRect, width: CGFloat, topMarginFraction: CGFloat
    )
        -> CGPoint
    {
        CGPoint(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.maxY - visibleFrame.height * topMarginFraction)
    }

    /// 剪贴板横条的停靠帧：占满可见区整宽，底边贴合可见区底边。
    static func bottomBarFrame(in visibleFrame: CGRect, height: CGFloat) -> CGRect {
        CGRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: visibleFrame.width,
            height: height)
    }

    /// 相对显示器保留：右为距左边缘，下为距顶部。
    static func offset(of anchor: CGPoint, on visibleFrame: CGRect) -> CGPoint {
        CGPoint(x: anchor.x - visibleFrame.minX, y: visibleFrame.maxY - anchor.y)
    }

    /// 由保留偏移量反算回锚点。
    static func anchor(for offset: CGPoint, on visibleFrame: CGRect) -> CGPoint {
        CGPoint(x: visibleFrame.minX + offset.x, y: visibleFrame.maxY - offset.y)
    }

    /// 展开状态下保持顶部固定时的中心 y。
    static func expandedCenterY(in visibleFrame: CGRect, expandedHeight: CGFloat) -> CGFloat {
        visibleFrame.midY + expandedHeight / 2
    }

    /// 当显示器上可见的紧凑栏过少、无法抓回时返回 nil。
    static func restored(
        _ stored: CGPoint, graspable: CGSize, visibleFrame: CGRect, minimumVisible: CGFloat
    ) -> CGPoint? {
        let bar = CGRect(
            x: stored.x, y: stored.y - graspable.height,
            width: graspable.width, height: graspable.height)
        let shown = visibleFrame.intersection(bar)
        return !shown.isNull && shown.width >= minimumVisible && shown.height >= minimumVisible
            ? stored : nil
    }

    /// 高度吸附位置：归位默认高度或展开居中。
    enum HeightSnap: Equatable {
        case home
        case expandedCenter
    }

    /// 一次吸附的结果：锚点、是否水平居中，以及高度吸附位置。
    struct Snap {
        let anchor: CGPoint
        let centeredX: Bool
        let height: HeightSnap?
    }

    /// 高度挡位仅存在于那条不可见的垂直中线上。
    static func snapped(
        _ anchor: CGPoint, home: CGPoint, visibleFrame: CGRect,
        expandedHeight: CGFloat, within distance: CGFloat, previous: Snap?, speed: CGFloat
    ) -> Snap {
        let wasCentered = previous?.centeredX ?? false
        let allowsEntry = speed <= maxSnapEntrySpeedPointsPerSecond
        guard abs(anchor.x - home.x) <= distance * (wasCentered ? 2 : 1),
            wasCentered || allowsEntry
        else {
            return Snap(anchor: anchor, centeredX: false, height: nil)
        }
        let expandedY = expandedCenterY(in: visibleFrame, expandedHeight: expandedHeight)
        let candidateHeight: HeightSnap?
        if abs(anchor.y - home.y) <= distance
            && abs(anchor.y - home.y) <= abs(anchor.y - expandedY)
        {
            candidateHeight = .home
        } else if abs(anchor.y - expandedY) <= distance {
            candidateHeight = .expandedCenter
        } else {
            candidateHeight = nil
        }
        let height = allowsEntry || candidateHeight == previous?.height ? candidateHeight : nil
        let y: CGFloat =
            switch height {
            case .home: home.y
            case .expandedCenter: expandedY
            case nil: anchor.y
            }
        return Snap(anchor: CGPoint(x: home.x, y: y), centeredX: true, height: height)
    }
}

/// 菜单窗口可跟随的三种屏幕空间锚点。
enum MenuPanelCorner: Equatable {
    case bottomLeading
    case bottomTrailing
    case belowHeaderTrailing
    /// 面板停靠在屏幕底部时，菜单从面板上边缘向上悬挂。
    case aboveLeading
    case aboveTrailing
    /// 锚定在某个具体目标（如被右键的卡片）正上方；携带屏幕坐标系中的目标矩形。
    case aboveRect(CGRect)

    /// 该角在层坐标系中的锚点（0/1 比例）。
    var layerAnchor: CGPoint {
        switch self {
        case .bottomLeading, .aboveLeading: CGPoint(x: 0, y: 0)
        case .bottomTrailing, .aboveTrailing: CGPoint(x: 1, y: 0)
        case .belowHeaderTrailing: CGPoint(x: 1, y: 1)
        case .aboveRect: CGPoint(x: 0.5, y: 0)
        }
    }

    /// 由画布尺寸计算该角的层位置。
    func layerPosition(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width * layerAnchor.x, y: size.height * layerAnchor.y)
    }

    /// 按内容尺寸、父窗口帧、边距与头部高度计算该角对应的窗口帧。
    func frame(
        contentSize: CGSize, parentFrame: CGRect, inset: CGFloat, headerExtent: CGFloat
    ) -> CGRect {
        let origin: CGPoint =
            switch self {
            case .bottomLeading:
                CGPoint(x: parentFrame.minX + inset, y: parentFrame.minY + inset)
            case .bottomTrailing:
                CGPoint(
                    x: parentFrame.maxX - inset - contentSize.width,
                    y: parentFrame.minY + inset)
            case .belowHeaderTrailing:
                CGPoint(
                    x: parentFrame.maxX - inset * 2 - contentSize.width,
                    y: parentFrame.maxY - headerExtent - contentSize.height)
            case .aboveLeading:
                CGPoint(x: parentFrame.minX + inset, y: parentFrame.maxY + inset)
            case .aboveTrailing:
                CGPoint(
                    x: parentFrame.maxX - inset - contentSize.width,
                    y: parentFrame.maxY + inset)
            case .aboveRect(let target):
                // 水平居中于目标，但夹在父面板范围内，目标贴边时菜单不会溢出屏幕。
                CGPoint(
                    x: min(
                        max(target.midX - contentSize.width / 2, parentFrame.minX + inset),
                        parentFrame.maxX - inset - contentSize.width),
                    y: target.maxY + inset)
            }
        return CGRect(origin: origin, size: contentSize)
    }

    /// 以自身锚点为基准缩放帧（用于入场/退场动画）。
    func scaledFrame(_ frame: CGRect, by scale: CGFloat) -> CGRect {
        let size = CGSize(width: frame.width * scale, height: frame.height * scale)
        let anchor = layerAnchor
        let origin = CGPoint(
            x: frame.minX - (size.width - frame.width) * anchor.x,
            y: frame.minY - (size.height - frame.height) * anchor.y)
        return CGRect(origin: origin, size: size)
    }
}
