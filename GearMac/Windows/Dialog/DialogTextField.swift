// 文件职责：对话框文本框的 SwiftUI 修饰器，统一其外观样式。
// 分层：UI；通过 `View.dialogTextField()` 扩展应用。
import SwiftUI

extension View {
    /// 对话框文本框：无边框样式，位于控件底色之上，高度与 chip 一致。
    func dialogTextField() -> some View {
        modifier(DialogTextField())
    }
}

/// 为视图套用对话框文本框样式的修饰器。
private struct DialogTextField: ViewModifier {
    @Environment(\.metrics) private var metrics

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .labelsHidden()
            .font(metrics.typography.rowTitle)
            .padding(.horizontal, metrics.spacing.lg)
            .frame(height: metrics.size.dialogButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                    .fill(Theme.Colors.controlSurface))
    }
}
