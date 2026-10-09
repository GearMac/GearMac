// 文件职责：拖拽调色板时用于标记其默认位置的对齐参考线视图（竖线与横线，含虚实与淡出效果）。
// 分层：UI（SwiftUI）；纯展示，不持有拖拽状态。
import SwiftUI

/// 拖拽进行中标记调色板默认位置的对齐参考线。
struct PaletteDropGuideView: View {
    /// 默认位置的左上角，位于参考线窗口的翻转坐标系中。
    let topLeft: CGPoint
    let width: CGFloat
    let horizontalDistance: CGFloat
    let verticalDistance: CGFloat
    let verticalFlash: Bool
    let horizontalFlash: Bool

    var body: some View {
        ZStack {
            DropGuidePath(topLeft: outerCorner, width: outerWidth, vertical: true)
                .stroke(
                    verticalFlash ? Theme.Colors.dropGuideArmed : Theme.Colors.dropGuide,
                    style: strokeStyle(dash: Theme.Size.dropGuideDash, crossing: outerCorner.y)
                )
                .opacity(opacity(at: horizontalDistance))
                .animation(.easeInOut(duration: Theme.Duration.dropGuide), value: verticalFlash)
            DropGuidePath(topLeft: outerCorner, width: outerWidth, vertical: false)
                .stroke(
                    horizontalFlash ? Theme.Colors.dropGuideArmed : Theme.Colors.dropGuide,
                    style: strokeStyle(dash: horizontalDash, crossing: outerCorner.x)
                )
                .opacity(min(opacity(at: horizontalDistance), opacity(at: verticalDistance)))
                .animation(.easeInOut(duration: Theme.Duration.dropGuide), value: horizontalFlash)
        }
    }

    private var outerCorner: CGPoint {
        CGPoint(
            x: topLeft.x - Theme.Size.dropGuideWidth,
            y: topLeft.y - Theme.Size.dropGuideWidth / 2)
    }

    private var outerWidth: CGFloat { width + Theme.Size.dropGuideWidth * 2 }

    private var horizontalDash: CGFloat {
        let period = Theme.Size.dropGuideDash + Theme.Size.dropGuideGap
        let cycles = max(1, (outerWidth / period).rounded())
        return outerWidth / cycles - Theme.Size.dropGuideGap
    }

    private func strokeStyle(dash: CGFloat, crossing: CGFloat) -> StrokeStyle {
        let gap = Theme.Size.dropGuideGap
        let period = dash + gap
        let phase = (dash + gap / 2 - crossing).truncatingRemainder(dividingBy: period)
        return StrokeStyle(
            lineWidth: Theme.Size.dropGuideWidth,
            dash: [dash, gap],
            dashPhase: phase < 0 ? phase + period : phase)
    }

    private func opacity(at distance: CGFloat) -> Double {
        let beyondThreshold = max(0, distance - Theme.Size.dropGuideFadeThreshold)
        return Double(max(0, 1 - beyondThreshold / Theme.Size.dropGuideFadeDistance))
    }
}

/// 面板两侧边缘贯穿整个高度；顶边贯穿整个宽度。
private struct DropGuidePath: Shape {
    let topLeft: CGPoint
    let width: CGFloat
    let vertical: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if vertical {
            for x in [topLeft.x, topLeft.x + width] {
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
        } else {
            path.move(to: CGPoint(x: rect.minX, y: topLeft.y))
            path.addLine(to: CGPoint(x: rect.maxX, y: topLeft.y))
        }
        return path
    }
}
