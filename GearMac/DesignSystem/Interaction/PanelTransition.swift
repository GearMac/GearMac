// 文件职责：统一所有无边框窗口的淡入淡出进出场动画，以及面板内容的缩放入场效果。
// 分层：UI（AppKit 窗口动画 + SwiftUI ViewModifier）；淡出可被中断，完成回调在主线程执行。
import AppKit
import SwiftUI

// 所有无边框面板统一的进出场方式，让对话框与 HUD 的观感一致。

extension NSWindow {
    /// 淡入整个窗口（含阴影）；`order` 在窗口仍然不可见时执行。
    func fadeIn(duration: TimeInterval, order: () -> Void) {
        alphaValue = 0
        order()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        } completionHandler: { [weak self] in
            // AppKit 会在主线程执行该回调，只是参数类型上没有标注这一点。
            MainActor.assumeIsolated {
                // 阴影是按首次绘制时的窗口尺寸缓存的（并做了缩放），因此需让其缓存失效。
                self?.invalidateShadow()
            }
        }
    }

    /// 可安全中断（完成回调会检查透明度）；`done` 在窗口完全移出屏幕后执行一次。
    func fadeOut(duration: TimeInterval, done: (@MainActor () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.alphaValue == 0 else { return }
                self.orderOut(nil)
                done?()
            }
        }
    }

    /// 立即恢复为完全不透明，并替换掉同一 key path 上正在进行的淡入淡出动画。
    func cancelFade() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            animator().alphaValue = 1
        }
    }
}

extension View {
    /// 随窗口淡入一起放大，并在测量出的 frame 内部完成，因此不会被裁切。
    func panelEntrance() -> some View {
        modifier(PanelEntrance())
    }
}

private struct PanelEntrance: ViewModifier {
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(appeared ? 1 : Self.entryScale)
            .onAppear {
                withAnimation(.easeOut(duration: Theme.Duration.enter)) { appeared = true }
            }
    }

    private static let entryScale: CGFloat = 0.94
}
