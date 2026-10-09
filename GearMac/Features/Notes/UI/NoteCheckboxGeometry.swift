// 文件职责：计算笔记任务项复选框的几何位置，供绘制与点击判定共用，保证“看得见的”就是“点得中的”。
// 分层：UI 支持层；纯几何计算，不持有视图状态。
import AppKit

/// 任务复选框的位置计算；绘制与命中测试共用同一套几何，确保显示位置与点击区域一致。
enum NoteCheckboxGeometry {
    /// 单个列表层级的标记槽宽度：共享的标记宽度，随正文字号缩放。
    static func slot(bodyPointSize: CGFloat) -> CGFloat {
        (Theme.Size.markdownListMarker * bodyPointSize / NSFont.systemFontSize).rounded()
    }

    /// 返回片段局部坐标系中的复选框矩形，其 x 原点为容器左边缘。
    static func rect(level: Int, firstLineHeight: CGFloat, bodyPointSize: CGFloat) -> CGRect {
        let side = bodyPointSize.rounded()
        let slot = slot(bodyPointSize: bodyPointSize)
        return CGRect(
            x: CGFloat(level) * slot + (slot - side) / 2, y: (firstLineHeight - side) / 2,
            width: side, height: side)
    }
}
