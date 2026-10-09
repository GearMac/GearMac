// 文件职责：玻璃背景视图：macOS 26 用 AppKit 原生 Liquid Glass，旧系统回落到 NSVisualEffectView。
// 分层：UI（DesignSystem）；AppKit 桥接层，仅透传原生视图，不承载任何状态或业务逻辑。
import SwiftUI

/// GearMac 无边框面板使用的玻璃背景。
struct GlassEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            NSGlassEffectView()
        } else {
            fallbackView()
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    /// macOS 15 回落：活性材质 + 窗口后方混合，近似 Liquid Glass 的悬浮面板观感。
    private func fallbackView() -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
}
