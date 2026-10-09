// 文件职责：可点选的胶囊形选项按钮（chip），用于对话框中的菜单式单选。
// 分层：UI；只维护自身悬停/选中外观，选择结果由父视图通过闭包回传。
import SwiftUI

/// 自行实现的选择按钮：菜单式 `Picker` 会在毛玻璃表面上弹出 AppKit 的 popover。
struct DialogChip: View {
    @Environment(\.metrics) private var metrics
    let title: String
    let selected: Bool
    let onTap: () -> Void
    @State private var hovered = false

    /// 按选中与悬停状态选定的背景填充色。
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return Theme.Colors.controlSurface
    }

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(selected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .padding(.horizontal, metrics.spacing.lg)
                .frame(height: metrics.size.barButtonHeight)
                .contentShape(Capsule())
                .background(Capsule().fill(fill))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
