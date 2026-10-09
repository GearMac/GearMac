// 文件职责：HUD 用的无边框面板，只作显示、不获取键盘焦点，始终位于命令面板之上。
// 分层：UI；面板永不成为 key 窗口。
import AppKit

/// 用于临时读数提示的无边框面板：永不成为 key 窗口，始终位于命令面板之上。
final class HUDPanel: NSPanel {
    /// 创建 HUD 面板；acceptsMouseEvents 决定是否接收鼠标事件。
    init(acceptsMouseEvents: Bool = false) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isOpaque = false
        backgroundColor = .clear
        // 两个 HUD 都沿用命令面板的表面配方，因此都不带明显的浮起阴影层次。
        hasShadow = true
        level = .palette
        ignoresMouseEvents = !acceptsMouseEvents
        hidesOnDeactivate = false
        // 关闭 AppKit 自带的窗口动画，改由 `fadeIn`/`fadeOut` 接管。
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
