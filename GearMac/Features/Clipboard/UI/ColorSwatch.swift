// 文件职责：颜色色块的统一绘制视图，含透明棋盘底与辅助功能标签；并提供 ColorValue 到 SwiftUI Color 的转换。
// 分层：UI；SwiftUI 视图与一个只读扩展，仅负责呈现。
import SwiftUI

/// 唯一绘制颜色的地方，绘制在可显示透明度的棋盘底之上。
struct ColorSwatch: View {
    @Environment(\.metrics) private var metrics
    let color: ColorValue
    var cornerRadius: CGFloat?

    /// 颜色属于内容而非界面装饰，因此与缩略图一样带一条细描边。
    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: cornerRadius ?? metrics.radius.thumbnail, style: .continuous)
        shape
            .fill(Theme.Colors.controlSurface)
            // 仅在存在透明度时构建，否则每行都要付出一个不可见 Canvas 的开销。
            .overlay { if color.hasAlpha { CheckerboardPattern().clipShape(shape) } }
            .overlay { shape.fill(color.swiftUIColor) }
            .overlay { shape.strokeBorder(Theme.Colors.cardStroke, lineWidth: 1) }
            // 色块不含任何文本，否则 VoiceOver 将无法读取任何内容。
            .accessibilityElement()
            .accessibilityLabel(ColorFormat.primary(for: color).string(for: color))
    }
}

/// 透明度背景：两种灰色，使半透明颜色呈现为透明效果。
private struct CheckerboardPattern: View {
    private static let cell: CGFloat = 5

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)), with: .color(Theme.Colors.checkerLight))
            let columns = Int((size.width / Self.cell).rounded(.up))
            let rows = Int((size.height / Self.cell).rounded(.up))
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    context.fill(
                        Path(
                            CGRect(
                                x: CGFloat(column) * Self.cell, y: CGFloat(row) * Self.cell,
                                width: Self.cell, height: Self.cell)),
                        with: .color(Theme.Colors.checkerDark))
                }
            }
        }
        .drawingGroup()
    }
}

extension ColorValue {
    /// sRGB 进、sRGB 出：这些分量已处于 SwiftUI 初始化器期望的色彩空间。
    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
