// 文件职责：定义 Quick Action 结果面板所用的无边框 NSPanel，并在此层拦截 ↵、⌘C 与 Esc 等按键。
// 分层：UI；仅负责窗口与按键事件，不参与结果生成与注入逻辑。
import AppKit
import Carbon.HIToolbox

/// 按键经由 `sendEvent` 处理，因此 ↵、⌘C 与 Esc 无需聚焦的子视图即可到达面板。
final class QuickActionPanel: NSPanel {
    /// 面板支持的按键操作：替换、复制与取消。
    enum Key {
        case replace
        case copy
        case cancel
    }

    /// 按键回调，由面板在拦截到对应按键时调用。
    var onKey: ((Key) -> Void)?

    /// 创建无边框、非激活型面板，并以内容视图的尺寸作为初始大小。
    init(content: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: content.frame.size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // 位于调色板上方、对话框下方：失败报告仍需覆盖在它之上。
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // 抑制 AppKit 自带的窗口动画；改由 `fadeIn`/`fadeOut` 负责。
        animationBehavior = .none
        isReleasedWhenClosed = false
        isRestorable = false
        contentView = content
    }

    /// 拦截按键事件并转换为 `Key` 回调，其余事件交还 AppKit 处理。
    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown, let onKey else {
            super.sendEvent(event)
            return
        }
        // 优先处理 ⌘C：修饰键正是这里区分「复制」与其他操作的关键。
        if event.modifierFlags.contains(.command) {
            guard Int(event.keyCode) == kVK_ANSI_C else {
                super.sendEvent(event)
                return
            }
            onKey(.copy)
            return
        }
        switch Int(event.keyCode) {
        case kVK_Escape:
            onKey(.cancel)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            onKey(.replace)
        default:
            super.sendEvent(event)
        }
    }

    /// 允许面板成为 key window，以便接收键盘事件。
    override var canBecomeKey: Bool { true }
    /// 不允许成为 main window。
    override var canBecomeMain: Bool { false }
}
