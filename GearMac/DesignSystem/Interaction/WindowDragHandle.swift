// 文件职责：提供窗口拖动把手（鼠标按下即拖窗口）以及空输入框的拖动处理。
// 分层：UI（AppKit 事件跟踪）；自行跟踪拖拽过程，以区分拖动与普通点击。
import SwiftUI

/// 在鼠标按下时就开始拖动窗口——否则宿主视图会先吃掉这次点击。
struct WindowDragHandle: NSViewRepresentable {
    var onBegan: () -> Void
    var onEnded: () -> Void

    func makeNSView(context: Context) -> NSView { DragView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? DragView)?.bind(onBegan: onBegan, onEnded: onEnded)
    }
}

extension View {
    /// 把一块区域标记为窗口拖动把手；以 overlay 形式实现，从而在命中测试中优先。
    func windowDraggable(
        _ enabled: Bool,
        onBegan: @escaping () -> Void = {},
        onEnded: @escaping () -> Void = {}
    ) -> some View {
        overlay {
            if enabled { WindowDragHandle(onBegan: onBegan, onEnded: onEnded) }
        }
    }
}

/// 作为背景使用，因此只有空白区域才触发拖动；`performDrag(with:)` 由窗口决定要移动什么。
struct WindowDragBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { BackgroundDragView() }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class BackgroundDragView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

/// 用于拖动没有可选中内容的输入框；一旦框内有文本，每次按下都交给编辑处理。
struct EmptyFieldDragHandle: NSViewRepresentable {
    var isEmpty: Bool
    var onBegan: () -> Void
    var onEnded: () -> Void
    var onClick: () -> Void

    func makeNSView(context: Context) -> NSView { EmptyFieldDragView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? EmptyFieldDragView else { return }
        view.isEmpty = isEmpty
        view.bind(onBegan: onBegan, onEnded: onEnded, onClick: onClick)
    }
}

/// 自行跟踪拖拽：`performDrag(with:)` 会立即返回，不会告知鼠标何时松开。
private class DragView: NSView {
    private var onBegan: (() -> Void)?
    private var onEnded: (() -> Void)?
    private var onClick: (() -> Void)?
    /// 判定为拖拽前的移动阈值，使没有位移的按下仍算作点击。
    private static let dragSlop: CGFloat = 3

    func bind(
        onBegan: @escaping () -> Void, onEnded: @escaping () -> Void,
        onClick: (() -> Void)? = nil
    ) {
        self.onBegan = onBegan
        self.onEnded = onEnded
        self.onClick = onClick
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        // 位移基于 `mouseLocation` 计算，避免视图或窗口坐标转换带来的漂移。
        let origin = window.frame.origin
        let start = NSEvent.mouseLocation
        var dragging = false
        window.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { tracked, stop in
            guard let tracked, tracked.type != .leftMouseUp else {
                stop.pointee = true
                return
            }
            let mouse = NSEvent.mouseLocation
            guard dragging || hypot(mouse.x - start.x, mouse.y - start.y) > Self.dragSlop else {
                return
            }
            if !dragging {
                dragging = true
                self.onBegan?()
            }
            window.setFrameOrigin(
                CGPoint(x: origin.x + mouse.x - start.x, y: origin.y + mouse.y - start.y))
        }
        // 没有产生位移的按下，是对把手覆盖内容的点击，而不是拖动。
        if dragging { onEnded?() } else { onClick?() }
    }
}

/// 直接让出命中测试，而不去测量文本：有光标或选区时都不应触发拖动。
private final class EmptyFieldDragView: DragView {
    var isEmpty = true

    override func hitTest(_ point: NSPoint) -> NSView? { isEmpty ? super.hitTest(point) : nil }
}
