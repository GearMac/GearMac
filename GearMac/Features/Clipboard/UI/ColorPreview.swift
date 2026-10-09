// 文件职责：颜色类条目的预览视图，展示色块与复制时的原始文本。
// 分层：UI；SwiftUI 视图，仅呈现颜色值，不包含颜色转换逻辑。
import SwiftUI

/// 颜色条目的预览：色块与复制时的文本，符号表示法由 ⌘K 菜单负责。
struct ColorPreview: View {
    @Environment(\.metrics) private var metrics
    let color: ColorValue
    let text: String

    /// 在任意面板宽度下保持固定尺寸：铺满边缘会让色块看起来像背景。
    private static let swatchSize = CGSize(width: 220, height: 130)

    var body: some View {
        VStack(spacing: metrics.spacing.lg) {
            ColorSwatch(color: color, cornerRadius: metrics.radius.card)
                .frame(width: Self.swatchSize.width, height: Self.swatchSize.height)
            Text(text)
                .font(.system(.subheadline, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, metrics.spacing.xxl)
    }
}
