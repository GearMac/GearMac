// 文件职责：提供前置卡片共用的外观（选中/悬停底色）与左右分栏组件，供计算器、日程与颜色卡片复用。
// 分层：UI；只负责卡片外观与排版，具体内容由各功能卡片提供。
import SwiftUI

/// 所有前置卡片共用的填充与悬停效果，使任何卡片对选中的反馈都一致。
private struct LeadCardChrome: ViewModifier {
    @Environment(\.metrics) private var metrics
    let selected: Bool
    @State private var hovered = false

    /// 叠加卡片底色与选中/悬停高亮。
    func body(content: Content) -> some View {
        content
            .background(shape.fill(Theme.Colors.cardFill))
            .background(shape.fill(fill))
            .armedHover($hovered)
    }

    /// 卡片统一使用的连续圆角矩形。
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
    }

    /// 选中优先于悬停，两者都无时透明。
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }
}

extension View {
    /// 内边距仍由各卡片自持：日程卡片刻意比答案卡片更矮。
    func leadCard(selected: Bool) -> some View {
        modifier(LeadCardChrome(selected: selected))
    }
}

/// 双栏前置卡片的一侧：一行数值，下面可选一个词名徽标。
struct LeadCardColumn: View {
    @Environment(\.metrics) private var metrics
    let text: AttributedString
    let badge: String?
    var weight: Font.Weight = .medium

    /// 纵向排列数值与可选徽标，并撑满所在列。
    var body: some View {
        VStack(spacing: metrics.spacing.md) {
            Text(text)
                .font(metrics.typography.calcResult.weight(weight))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let badge { LeadCardBadge(text: badge) }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, metrics.spacing.md)
    }
}

/// 前置卡片用来声明其类型的胶囊——计算器的单位、颜色的记法。
private struct LeadCardBadge: View {
    @Environment(\.metrics) private var metrics
    let text: String

    /// 渲染次要样式的小胶囊文本。
    var body: some View {
        Text(text)
            .font(metrics.typography.keyCap)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(.secondary)
            .padding(.horizontal, metrics.spacing.sm)
            .padding(.vertical, metrics.spacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.keyCap, style: .continuous)
                    .fill(Theme.Colors.controlSurface)
            )
    }
}
