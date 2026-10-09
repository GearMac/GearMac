// 文件职责：提供快捷键键帽（keycap）胶囊组件 `KeyCapChip`，用于行内快捷键提示与底部快捷操作。
// 分层：UI（DesignSystem）；纯展示控件，尺寸、圆角与字体均取自 `InterfaceMetrics`。
import SwiftUI

/// 单个键帽胶囊：`.outline` 用于行内的快捷键提示，`.filled` 用于底部的快捷操作。
struct KeyCapChip: View {
    /// 键帽内的文字内容，可选前缀（如修饰键符号）与主文本并排展示。
    struct Label: View {
        let text: String
        var prefix: String?
        var spacing: CGFloat = Theme.Spacing.xxs

        var body: some View {
            if let prefix {
                HStack(spacing: spacing) {
                    Text(prefix).textScale(.secondary)
                    Text(text)
                }
            } else {
                Text(text)
            }
        }
    }

    /// 键帽外观：描边或填充。
    enum Style {
        case outline
        case filled
    }

    /// 允许使用的键帽尺寸：更大或更小都应该是具名选项，而不是随手写死的 frame。
    enum Scale {
        case compact
        case standard
        case hero

        /// 返回该尺寸对应的键帽边长。
        func side(_ metrics: InterfaceMetrics) -> CGFloat {
            switch self {
            case .compact: metrics.size.compactKeyCap
            case .standard: metrics.size.keyCap
            case .hero: metrics.size.heroKeyCap
            }
        }

        /// 返回该尺寸对应的键帽字体。
        @MainActor
        func font(_ metrics: InterfaceMetrics) -> Font {
            switch self {
            case .compact: metrics.typography.compactKeyCap
            case .standard: metrics.typography.keyCap
            case .hero: metrics.typography.heroKeyCap
            }
        }
    }

    let text: String
    var style: Style = .filled
    var scale: Scale = .standard
    var prefix: String?
    @Environment(\.metrics) private var metrics

    /// "↵" 会回退到另一种字面而位置偏高，因此仅在渲染时微调下移。
    private static let returnGlyphDrop: CGFloat = 1.1

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.radius.keyCap, style: .continuous)
        Label(text: text, prefix: prefix, spacing: metrics.spacing.xxs)
            .font(scale.font(metrics))
            .foregroundStyle(Theme.Colors.textSecondary)
            .offset(y: text == "↵" ? Self.returnGlyphDrop : 0)
            .padding(.horizontal, metrics.spacing.xs)
            .frame(minWidth: scale.side(metrics), minHeight: scale.side(metrics))
            .background {
                switch style {
                case .filled: shape.fill(Theme.Colors.controlSurface)
                case .outline: shape.strokeBorder(Theme.Colors.border, lineWidth: 1)
                }
            }
    }
}
