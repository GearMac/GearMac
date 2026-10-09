// 文件职责：扩展设置编辑器（sheet/popover 形式）共用的视觉组件：面板表面、标题、按钮样式与输入框样式。
// 分层：UI（SwiftUI 视图与 ViewModifier）；只提供样式与布局，不持有业务状态。
import SwiftUI

/// 扩展设置编辑器的组合样式入口：统一面板表面与输入框外观。
extension View {
    /// 扩展自有的面板表面；设置外壳只把它当作一个不透明的盒子承载。
    func extensionSettingsEditorPanelSurface() -> some View {
        modifier(ExtensionSettingsEditorPanelSurface())
    }

    /// 统一的扩展设置输入框样式：无边框、固定高度、圆角控件底色。
    func extensionSettingsEditorTextField() -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(height: Theme.Size.dialogButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Theme.Colors.controlSurface))
    }
}

/// 面板表面修饰器：底色加玻璃效果，按面板圆角裁切。
private struct ExtensionSettingsEditorPanelSurface: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
        content
            .background(Theme.Colors.panelScrim, in: shape)
            .glassSurface(in: shape)
    }
}

/// 编辑器面板标题区：主标题加可选副标题。
struct ExtensionSettingsEditorHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title).font(Theme.Typography.panelTitle)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 编辑器按钮样式：分 standard / primary / cancel 三种角色。
struct ExtensionSettingsEditorButtonStyle: ButtonStyle {
    /// 按钮角色，决定填充色与文字颜色。
    enum Role { case standard, primary, cancel }

    let role: Role
    var fillsWidth = true

    /// 按角色与是否撑满宽度构造按钮外观。
    func makeBody(configuration: Configuration) -> some View {
        ExtensionSettingsEditorButtonBody(
            configuration: configuration, role: role, fillsWidth: fillsWidth)
    }
}

/// 按钮样式的具体渲染体，处理悬停、按下与禁用态。
private struct ExtensionSettingsEditorButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let role: ExtensionSettingsEditorButtonStyle.Role
    let fillsWidth: Bool

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        configuration.label
            .font(Theme.Typography.rowTrailing)
            .foregroundStyle(labelColor)
            .padding(.horizontal, Theme.Spacing.xl)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(height: Theme.Size.dialogButtonHeight)
            .contentShape(Capsule())
            .background(Capsule().fill(fill))
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { hovered = $0 }
    }

    /// 按钮背景色：主操作半透明高亮，其余在悬停或按下时用选中色。
    private var fill: Color {
        switch role {
        case .primary:
            Theme.Colors.primaryAction.opacity(isHighlighted ? 0.28 : 0.20)
        case .standard, .cancel:
            isHighlighted ? Theme.Colors.selection : Theme.Colors.controlSurface
        }
    }

    /// 按钮文字颜色，按角色区分。
    private var labelColor: Color {
        switch role {
        case .standard: .primary
        case .primary: Theme.Colors.primaryAction
        case .cancel: Theme.Colors.textSecondary
        }
    }

    /// 是否处于悬停或按下状态。
    private var isHighlighted: Bool { hovered || configuration.isPressed }
}
