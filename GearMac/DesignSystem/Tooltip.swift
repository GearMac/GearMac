// 文件职责：实现 GearMac 自有的悬停提示（tooltip）修饰器，以及 `.tooltip(_:)` / `.tooltip(keyCap:)` 视图扩展。
// 分层：UI（DesignSystem）；提示内容与对齐边由调用方指定，延迟与动效来自 `Theme`，用于替代系统 `.help()` 提示。
import SwiftUI

/// 提示内容：纯文字或键帽样式。
private enum TooltipLabel {
    case text(String)
    case keyCap(String)
}

/// 使用 GearMac 自身视觉语言的悬停标签，用于替代系统 `.help()` 提示。
private struct TooltipModifier: ViewModifier {
    let label: TooltipLabel?
    let alignment: HorizontalAlignment
    let edge: VerticalEdge
    @Environment(\.metrics) private var metrics
    @State private var hovered = false
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .onHover {
                hovered = label != nil && $0
                if !hovered { visible = false }
            }
            .task(id: hovered) {
                guard hovered else { return }
                try? await Task.sleep(for: .seconds(Theme.Duration.tooltipDelay))
                guard !Task.isCancelled, hovered else { return }
                withAnimation(.easeOut(duration: Theme.Duration.tooltip)) { visible = true }
            }
            .overlay(alignment: Alignment(horizontal: alignment, vertical: side)) {
                if let label, visible { tile(label) }
            }
    }

    /// 提示挂在控件的上边还是下边。
    private var side: VerticalAlignment { edge == .top ? .top : .bottom }

    /// 绘制提示气泡本体，并用零高度 frame 让它紧贴控件边缘悬挂。
    private func tile(_ label: TooltipLabel) -> some View {
        let shape = RoundedRectangle(cornerRadius: metrics.radius.tooltip, style: .continuous)
        return chip(label)
            .padding(metrics.spacing.xs)
            .background {
                shape.fill(Color(nsColor: .windowBackgroundColor))
                shape.fill(Theme.Colors.controlSurface)
            }
            .shadow(
                color: Theme.Colors.tooltipShadow, radius: metrics.spacing.xs,
                y: metrics.spacing.xxs
            )
            .fixedSize()
            // 控件边缘上的零高度 frame，使任意高度的提示标签都从该处悬挂出去。
            .frame(height: 0, alignment: edge == .top ? .bottom : .top)
            .offset(y: edge == .top ? -metrics.spacing.sm : metrics.spacing.sm)
            .transition(.opacity)
            .allowsHitTesting(false)
    }

    /// 按内容类型渲染提示：普通文字或键帽。
    @ViewBuilder private func chip(_ label: TooltipLabel) -> some View {
        switch label {
        case .text(let text):
            Text(text)
                .font(metrics.typography.keyCap)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal, metrics.spacing.xs)
                .frame(minHeight: metrics.size.keyCap)
        case .keyCap(let cap):
            KeyCapChip(text: cap, style: .outline)
        }
    }
}

extension View {
    /// 将提示对齐到侧边；控件位于窗口顶部时改为挂在下方（`.bottom`）。
    func tooltip(
        _ text: String?, alignment: HorizontalAlignment = .center, edge: VerticalEdge = .top
    ) -> some View {
        modifier(
            TooltipModifier(label: text.map(TooltipLabel.text), alignment: alignment, edge: edge))
    }

    /// 以键帽样式展示快捷键提示。
    func tooltip(keyCap: String?) -> some View {
        modifier(
            TooltipModifier(label: keyCap.map(TooltipLabel.keyCap), alignment: .center, edge: .top))
    }
}
