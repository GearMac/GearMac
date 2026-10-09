// 文件职责：对话框用的无边框 NSPanel 子类，直接拦截 Esc/↵/方向键并转发给回调。
// 分层：UI；非激活面板，按键无需子视图获得焦点即可生效。
import AppKit
import Carbon.HIToolbox

/// 单个对话框的面板；按键经由 `sendEvent` 处理，因此 Esc/↵ 无需聚焦到子视图。
final class DialogPanel: NSPanel {
    /// 只表示面板看到的按键，不表示其语义：单步幅度由调用方决定。
    enum Key {
        case cancel
        case confirm
        case increment
        case decrement
    }

    /// 面板解析出的按键回调。
    var onKey: ((Key) -> Void)?
    /// 方向键属于控件而非面板；文本框需要它们移动光标。
    var handlesArrowKeys = false

    /// 用内容视图与圆角创建非激活的浮动面板。
    init(content: NSView, cornerRadius: CGFloat) {
        super.init(
            contentRect: NSRect(origin: .zero, size: content.frame.size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .dialog
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // 关闭 AppKit 自带的窗口动画，改由 `fadeIn`/`fadeOut` 接管。
        animationBehavior = .none
        isReleasedWhenClosed = false
        content.wantsLayer = true
        content.layer?.cornerRadius = cornerRadius
        content.layer?.cornerCurve = .continuous
        content.layer?.masksToBounds = true
        contentView = content
    }

    /// 拦截 Esc、回车与（允许时）方向键，其余事件交回 AppKit。
    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown, let onKey else {
            super.sendEvent(event)
            return
        }
        switch Int(event.keyCode) {
        case kVK_Escape:
            onKey(.cancel)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            onKey(.confirm)
        case kVK_LeftArrow where handlesArrowKeys,
            kVK_DownArrow where handlesArrowKeys:
            onKey(.decrement)
        case kVK_RightArrow where handlesArrowKeys,
            kVK_UpArrow where handlesArrowKeys:
            onKey(.increment)
        default:
            super.sendEvent(event)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 让内容里的第一个可编辑文本框成为 first responder。
    func focusFirstTextField() {
        // SwiftUI 在首次布局时才创建文本框，而面板变 key 时可能尚未布局。
        contentView?.layoutSubtreeIfNeeded()
        guard let field = contentView.flatMap(Self.firstTextField(in:)) else { return }
        makeFirstResponder(field)
    }

    private static func firstTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        return view.subviews.lazy.compactMap(firstTextField(in:)).first
    }
}
