// 文件职责：提供调色板扩展相关的视图修饰符 —— 动作快捷键分发、Toast 插槽与表单按键处理。
// 分层：UI；修饰符只转发事件，具体决策交由 `ExtensionCommandScreen`、`ExtensionManager` 与 `ExtensionFormKey`。
import SwiftUI

/// 操作自身的快捷键，在调色板绑定处理之前先行匹配。
struct ExtensionShortcutKeys: ViewModifier {
    let screen: ExtensionCommandScreen?
    let selection: Int

    func body(content: Content) -> some View {
        content.onKeyPress(phases: .down) { press in
            guard let screen, !press.modifiers.isEmpty else { return .ignored }
            return screen.dispatchShortcut(
                key: ASCIIKeyboardLayout.keyEquivalent(fallingBackTo: press.key),
                modifiers: press.modifiers,
                at: selection) ? .handled : .ignored
        }
    }
}

/// 在内容上层展示当前扩展 Toast，并接管其动作与关闭回调。
struct ExtensionToastSlot: ViewModifier {
    @Environment(\.metrics) private var metrics
    let extensions: ExtensionManager
    let showing: Bool

    func body(content: Content) -> some View {
        let toast = showing ? extensions.toasts.last : nil
        ZStack(alignment: .leading) {
            content
                .opacity(toast == nil ? 1 : 0)
                .allowsHitTesting(toast == nil)
            if let toast {
                ExtensionToastPill(
                    toast: toast, onAction: { extensions.runToastAction(token: $0) },
                    onDismiss: { extensions.hide(toast: toast.id) }
                )
                .padding(.trailing, metrics.spacing.md)
                .id(toast.id)
                .transition(.scale(scale: 0.5, anchor: .leading).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(duration: 0.3, bounce: 0.2), value: toast?.id)
    }
}

/// 把表单控件上的回车/空格按键解析为激活、提交或忽略。
struct ExtensionFormKeys: ViewModifier {
    let field: ExtensionFormField
    let onActivate: () -> Void
    let onSubmit: () -> Void
    @Environment(PaletteState.self) private var palette

    func body(content: Content) -> some View {
        content.onKeyPress(keys: ExtensionFormKey.enterKeys.union([.space]), phases: [.down, .repeat]) {
            press in
            switch ExtensionFormKey.resolve(
                field: field, key: press.key, modifiers: press.modifiers,
                repeating: press.phase == .repeat, menuOpen: palette.menuOpen,
                composing: palette.isComposing)
            {
            case .activate: onActivate()
            case .submit: onSubmit()
            case .consume: break
            case .ignored: return .ignored
            }
            return .handled
        }
    }
}
