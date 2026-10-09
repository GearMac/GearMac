// 文件职责：以单个 Path 绘制「圆角矩形 + 圆角三角指针」的 callout 外形，使玻璃材质能整体作用。
// 分层：UI（Shape）；纯几何绘制，不含状态与副作用。
import SwiftUI

/// 圆角矩形加上圆角三角指针，合为单个 path，使玻璃效果能将其视作一体。
struct CalloutShape: Shape {
    let caretEdge: CalloutPlacement.CaretEdge
    let caretX: CGFloat
    var cornerRadius: CGFloat = Theme.Radius.menuPanel
    var caretWidth: CGFloat = Theme.Size.calloutCaretWidth
    var caretHeight: CGFloat = Theme.Size.calloutCaretHeight
    var tipRadius: CGFloat = Theme.Size.calloutCaretTip

    /// 根据 rect 生成 callout 外形路径。
    func path(in rect: CGRect) -> Path {
        let up = caretEdge == .top
        let body = CGRect(
            x: rect.minX, y: up ? rect.minY + caretHeight : rect.minY,
            width: rect.width, height: rect.height - caretHeight)
        var path = Path(roundedRect: body, cornerRadius: cornerRadius, style: .continuous)

        let half = caretWidth / 2
        let baseY = up ? body.minY : body.maxY
        let tipY = up ? rect.minY : rect.maxY
        // 两条直边在弧线处汇合：一个尖端带圆角的三角形，而不是圆顶。
        path.move(to: CGPoint(x: caretX - half, y: baseY))
        path.addArc(
            tangent1End: CGPoint(x: caretX, y: tipY),
            tangent2End: CGPoint(x: caretX + half, y: baseY),
            radius: tipRadius)
        path.addLine(to: CGPoint(x: caretX + half, y: baseY))
        path.closeSubpath()
        return path
    }
}
