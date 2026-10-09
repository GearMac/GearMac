// 文件职责：提供 `armedHover` 视图修饰符，让行高亮只在指针真实移动时点亮，与键盘选中无关。
// 分层：UI（SwiftUI）；通过 `PaletteState.hoverHighlightArmed` 与 `hoverDisarmToken` 读取武装状态。
import SwiftUI

/// 行悬停修饰符：监听连续悬停事件，并根据 `PaletteState` 的武装标志决定是否高亮。
private struct ArmedHover: ViewModifier {
    @Environment(PaletteState.self) private var palette
    @Binding var hovered: Bool

    func body(content: Content) -> some View {
        content
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active: hovered = palette.hoverHighlightArmed
                case .ended: hovered = false
                }
            }
            // 指针静止时解除武装不会产生 hover 阶段，因此用 drop 事件清掉该行高亮。
            .onChange(of: palette.hoverDisarmToken) { hovered = false }
    }
}

extension View {
    /// 行悬停：仅在指针移动时点亮，与键盘选中相互独立。
    func armedHover(_ hovered: Binding<Bool>) -> some View {
        modifier(ArmedHover(hovered: hovered))
    }
}
