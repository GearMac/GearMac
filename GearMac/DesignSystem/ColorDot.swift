// 文件职责：提供用于给相邻文字标签做颜色编码的小圆点视图 `ColorDot`。
// 分层：UI（DesignSystem）；纯展示组件，尺寸来自 `InterfaceMetrics`，不对 VoiceOver 暴露。
import SwiftUI

/// 给旁边标签做颜色标记的实心小圆点；它只作装饰，因此对 VoiceOver 隐藏。
struct ColorDot: View {
    @Environment(\.metrics) private var metrics
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: metrics.size.colorDot, height: metrics.size.colorDot)
            .accessibilityHidden(true)
    }
}
