// 文件职责：消息 HUD 的胶囊视图，展示语气图标或加载指示器。
// 分层：UI；带取消回调时悬停会变为可点击的关闭按钮。
import SwiftUI

/// 消息胶囊，开头是语气对应的标记或加载指示器。见 docs/ui.md#dialogs--hud。
struct MessageHUDView: View {
    /// 消息 HUD 的附件类型：语气图标或进行中状态。
    enum Accessory {
        case tone(DialogTone)
        case progress
    }

    private static let glowOpacity = 0.14
    private static let glowRadius: CGFloat = 150
    private static let rimOpacity = 0.25

    let message: String
    let accessory: Accessory
    var onCancel: (() -> Void)? = nil
    @State private var hovered = false
    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Group {
            if let onCancel {
                Button(action: onCancel) {
                    content
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    String(format: settings.text(WindowsKey.hudCancelFormat), message))
            } else {
                content
            }
        }
        .onHover { isHovered in
            if onCancel != nil {
                withAnimation(.easeOut(duration: Theme.Duration.hover)) {
                    hovered = isHovered
                }
            }
        }
    }

    /// 根据附件类型选定强调色。
    private var tint: Color {
        switch accessory {
        case .tone(let tone): tone.tint
        case .progress: Theme.Colors.progress
        }
    }

    /// 胶囊主体：标记与消息文本。
    private var content: some View {
        HStack(spacing: metrics.spacing.md) {
            mark
            Text(message)
                .font(metrics.typography.bar)
                .foregroundStyle(Color.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, metrics.spacing.xl)
        .padding(.vertical, metrics.spacing.lg)
        .frame(maxWidth: metrics.size.hudMaxWidth, alignment: .leading)
        .fixedSize()
        .background { glow }
        // 不用玻璃效果：背后没有可折射的内容时会退化为不透明底衬而暴露出来。
        .background(hovered ? Theme.Colors.controlHover : Theme.Colors.panelScrim)
        .background(GlassEffectView())
        .clipShape(Capsule())
        .overlay { rim }
    }

    /// 位于标记处的随色调渐隐光晕，向右侧逐渐消失。
    private var glow: some View {
        GeometryReader { proxy in
            Capsule().fill(
                RadialGradient(
                    colors: [tint.opacity(Self.glowOpacity), tint.opacity(0.03), .clear],
                    center: UnitPoint(
                        x: (metrics.spacing.xl + metrics.size.menuIcon / 2) / proxy.size.width,
                        y: 0.5),
                    startRadius: 0, endRadius: Self.glowRadius))
        }
    }

    /// 胶囊描边：悬停时用实描边，否则从左到右渐隐。
    private var rim: some View {
        Capsule().strokeBorder(
            hovered
                ? AnyShapeStyle(Theme.Colors.border)
                : AnyShapeStyle(
                    LinearGradient(
                        colors: [tint.opacity(Self.rimOpacity), tint.opacity(0.06), .clear],
                        startPoint: .leading, endPoint: .trailing)),
            lineWidth: Theme.Size.hairline)
    }

    /// 两种标记共用同一个尺寸框，因此加载指示器切换为结果图标时不会改变胶囊大小。
    private var mark: some View {
        Group {
            if hovered, onCancel != nil {
                Image(systemName: "xmark")
                    .font(metrics.typography.menuIcon.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: metrics.size.menuIcon, height: metrics.size.menuIcon)
                    .transition(.opacity)
            } else {
                symbol
                    .font(metrics.typography.menuIcon)
                    .frame(width: metrics.size.menuIcon, height: metrics.size.menuIcon)
                    .transition(.opacity)
            }
        }
    }

    /// 按附件类型选择要显示的标记图标。
    @ViewBuilder
    private var symbol: some View {
        switch accessory {
        case .tone(let tone):
            Image(systemName: tone.hudSymbol)
                .foregroundStyle(tone.tint)
        case .progress:
            // `ProgressView` 的加载指示器由 AppKit 绘制，会忽略施加给它的任何 tint。
            Image(systemName: "progress.indicator")
                .foregroundStyle(Theme.Colors.progress)
                .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing)
        }
    }
}

/// 有意限定在文件作用域内，避免构建对话框时误用到它。
extension DialogTone {
    fileprivate var hudSymbol: String {
        switch self {
        case .neutral: return "info"
        case .success: return "checkmark"
        case .danger: return "exclamationmark"
        }
    }
}
