// 文件职责：定义弹窗底部动作按钮的 `ButtonStyle`（`ModalActionButtonStyle`），统一按语义角色着色与布局。
// 分层：UI（DesignSystem）；通过 `ButtonStyle` 包装 SwiftUI 按钮状态（悬停/按压/禁用）映射到 `Theme` 颜色。
import SwiftUI

/// 弹窗底部按钮样式：按 `role` 决定填充色与文字颜色，并可选择是否撑满宽度。
struct ModalActionButtonStyle: ButtonStyle {
    /// 按钮语义角色，决定配色与强调程度。
    enum Role { case standard, primary, cancel, destructive }

    let role: Role
    var fillsWidth = true

    func makeBody(configuration: Configuration) -> some View {
        ButtonBody(configuration: configuration, role: role, fillsWidth: fillsWidth)
    }

    /// 实际绘制的按钮主体，负责读取悬停/按压/启用状态并据此着色。
    private struct ButtonBody: View {
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.metrics) private var metrics
        let configuration: ButtonStyleConfiguration
        let role: Role
        let fillsWidth: Bool
        @State private var hovered = false

        var body: some View {
            configuration.label
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(labelColor)
                .padding(.horizontal, metrics.spacing.xl)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .frame(height: metrics.size.dialogButtonHeight)
                .contentShape(Capsule())
                .background(Capsule().fill(fill))
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { hovered = $0 }
        }

        private var fill: Color {
            switch role {
            case .primary:
                Theme.Colors.primaryAction.opacity(accentOpacity)
            case .destructive:
                Theme.Colors.destructive.opacity(accentOpacity)
            case .standard, .cancel:
                if configuration.isPressed {
                    Theme.Colors.controlPressed
                } else if hovered {
                    Theme.Colors.controlHover
                } else {
                    Theme.Colors.controlSurface
                }
            }
        }

        private var accentOpacity: Double {
            if configuration.isPressed { return 0.36 }
            if hovered { return 0.28 }
            return 0.20
        }

        private var labelColor: Color {
            switch role {
            case .standard: .primary
            case .primary: Theme.Colors.primaryAction
            case .cancel: Theme.Colors.textSecondary
            case .destructive: Theme.Colors.destructive
            }
        }
    }
}

extension ButtonStyle where Self == ModalActionButtonStyle {
    static func modalAction(
        _ role: ModalActionButtonStyle.Role, fillsWidth: Bool = true
    ) -> ModalActionButtonStyle {
        ModalActionButtonStyle(role: role, fillsWidth: fillsWidth)
    }
}
