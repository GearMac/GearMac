// 文件职责：提供只接管右键事件的覆盖层，使 popover 能锚定到固定位置。
// 分层：UI（SwiftUI/AppKit 桥接）；命中测试只放行右键事件，其余事件一律透传。
import SwiftUI

/// 只认领右键事件的覆盖层，使 popover 能锚定到固定的位置点。
struct RightClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView { CatcherView(action: action) }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? CatcherView)?.action = action
    }

    private final class CatcherView: NSView {
        var action: () -> Void
        init(action: @escaping () -> Void) {
            self.action = action
            super.init(frame: .zero)
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func rightMouseDown(with event: NSEvent) { action() }

        override func hitTest(_ point: NSPoint) -> NSView? {
            switch NSApp.currentEvent?.type {
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
                return super.hitTest(point)
            default:
                return nil
            }
        }
    }
}

/// 会回报点击坐标的变体：网格中一个 catcher 即可服务所有单元格。
struct RightClickLocationCatcher: NSViewRepresentable {
    let action: (CGPoint) -> Void

    func makeNSView(context: Context) -> NSView { CatcherView(action: action) }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? CatcherView)?.action = action
    }

    private final class CatcherView: NSView {
        var action: (CGPoint) -> Void
        init(action: @escaping (CGPoint) -> Void) {
            self.action = action
            super.init(frame: .zero)
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        // 翻转坐标系，使回报的坐标与 SwiftUI 以左上角为原点的局部坐标一致。
        override var isFlipped: Bool { true }

        override func rightMouseDown(with event: NSEvent) {
            action(convert(event.locationInWindow, from: nil))
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            switch NSApp.currentEvent?.type {
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
                return super.hitTest(point)
            default:
                return nil
            }
        }
    }
}

extension View {
    /// 为视图添加不接受坐标的右键点击处理。
    func onRightClick(perform action: @escaping () -> Void) -> some View {
        overlay(RightClickCatcher(action: action))
    }

    /// 为视图添加会回报点击位置的右键处理。
    func onRightClick(perform action: @escaping (CGPoint) -> Void) -> some View {
        overlay(RightClickLocationCatcher(action: action))
    }
}
