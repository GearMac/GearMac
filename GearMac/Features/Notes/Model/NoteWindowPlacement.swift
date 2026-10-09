// 文件职责：计算笔记窗口的尺寸与位置（按高度适配并保持在可见区域内）。
// 分层：Model；纯几何计算、不依赖 AppKit/SwiftUI。
import CoreGraphics

/// 笔记窗口的尺寸与位置计算。
enum NoteWindowPlacement {
    /// 顶部保持不动，直到底部超出可见区域，此时窗口上移。
    static func fitting(
        _ frame: CGRect, toHeight height: CGFloat, within heights: ClosedRange<CGFloat>,
        in visibleFrame: CGRect
    ) -> CGRect {
        let height = min(heights.upperBound, visibleFrame.height, max(heights.lowerBound, ceil(height)))
        return CGRect(
            x: frame.minX,
            y: max(visibleFrame.minY, min(frame.maxY, visibleFrame.maxY) - height),
            width: frame.width,
            height: height)
    }

    /// 把窗口放到可见区域的右上角，并保持缩进不超出可见范围。
    static func topRight(_ frame: CGRect, in visibleFrame: CGRect, inset: CGFloat) -> CGRect {
        let horizontalInset = min(inset, max(0, visibleFrame.width - frame.width))
        let verticalInset = min(inset, max(0, visibleFrame.height - frame.height))
        return CGRect(
            x: visibleFrame.maxX - frame.width - horizontalInset,
            y: visibleFrame.maxY - frame.height - verticalInset,
            width: frame.width,
            height: frame.height)
    }
}
