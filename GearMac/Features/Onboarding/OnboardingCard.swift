// 文件职责：提供引导窗口专用的卡片、分隔线与行布局视图（OnboardingCard / OnboardingDivider / OnboardingRow）。
// 分层：UI；引导窗口自带外观，不复用设置面板的 `Form` 版式。
import SwiftUI

// 引导窗口自己的卡片样式：设置面板用的是系统 `Form` 分区，而本窗口不是。

/// 一组圆角、细描边的引导行容器。
struct OnboardingCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Colors.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
            )
    }
}

/// `OnboardingCard` 内部的内缩分隔线，与行的标题左对齐。
struct OnboardingDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Colors.cardStroke)
            .frame(height: 1)
            .padding(.leading, Theme.Spacing.xl + Theme.Size.settingsRowIcon + Theme.Spacing.lg)
    }
}

/// 单条引导行；固定间距节奏让各卡片无论控件如何都保持对齐。
struct OnboardingRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    var tint: Color = .secondary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: Theme.Size.settingsRowIcon)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                Text(title)
                    .font(.body)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Spacing.xl)
            trailing
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }
}
