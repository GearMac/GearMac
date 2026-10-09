// 文件职责：实现列表行的点击选中/激活与拖出（拖放）行为，并定义行拖放的数据。
// 分层：UI（AppKit 事件与 NSDraggingSource）；仅支持 copy，避免用户文件被意外移动。
import SwiftUI

/// 行拖放到目标应用时交给对方的数据，以及跟随指针移动的拖拽图像。
struct RowDragItem {
    let writer: any NSPasteboardWriting
    let image: NSImage

    /// `image` 使用行已预热好的缩略图：在 mouse-down 时再做解码会卡住拖拽开始的那一帧。
    static func file(_ url: URL, image: NSImage?) -> RowDragItem {
        RowDragItem(writer: url as NSURL, image: image ?? NSWorkspace.shared.icon(forFile: url.path))
    }
}

/// 可被其他应用接收的行数据。只做复制，因此用户的文件、应用或自有数据都不会被移走。
struct RowDrag {
    /// 在拖拽开始时读取（而非行绘制时）；返回 nil 表示拒绝拖拽。
    let item: () -> RowDragItem?
    /// 仅在拖放成功落地时触发；被拒绝的拖拽会飞回原行，因此不触发，以此区分未生效的拖拽。
    let dropped: () -> Void
}

extension View {
    /// 在按下时即选中（而非等一个双击间隔之后）；双击则执行激活。
    func onRowClick(
        select: @escaping () -> Void, activate: @escaping () -> Void, drag: RowDrag? = nil
    ) -> some View {
        overlay(
            RowPressCatcher(activation: .doubleClick, select: select, activate: activate, drag: drag))
    }

    /// 可拖出的单击：激活要等到松开鼠标，因此拖拽不会误触发激活。
    @ViewBuilder
    func onRowTap(drag: RowDrag?, perform activate: @escaping () -> Void) -> some View {
        if let drag {
            overlay(RowPressCatcher(activation: .release, select: {}, activate: activate, drag: drag))
        } else {
            onTapGesture(perform: activate)
        }
    }
}

/// 用 AppKit 而非 `onDrag`：只有 `NSDraggingSource` 才能在同一卷内强制使用 `.copy` 而非移动。
private struct RowPressCatcher: NSViewRepresentable {
    let activation: RowPressView.Activation
    let select: () -> Void
    let activate: () -> Void
    let drag: RowDrag?

    func makeNSView(context: Context) -> RowPressView { RowPressView() }

    func updateNSView(_ view: RowPressView, context: Context) {
        view.activation = activation
        view.select = select
        view.activate = activate
        view.drag = drag
    }
}

/// 独占整个左键按下流程，否则宿主视图会先把这次点击吃掉。
private final class RowPressView: NSView, NSDraggingSource {
    enum Activation {
        /// 在双击的第一次按下时触发：位于预览旁边的列表用单击即可选中。
        case doubleClick
        /// 在单击松开时触发，此刻才能确定该次按下不是拖拽。
        case release
    }

    private static let dragSlop: CGFloat = 4

    var activation = Activation.doubleClick
    var select: () -> Void = {}
    var activate: () -> Void = {}
    var drag: RowDrag?

    /// 只处理左键，这样行的右键 catcher 仍能打开操作菜单。
    override func hitTest(_ point: NSPoint) -> NSView? {
        switch NSApp.currentEvent?.type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
            return super.hitTest(point)
        default:
            return nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        select()
        if activation == .doubleClick {
            guard event.clickCount < 2 else {
                activate()
                return
            }
            guard drag != nil else { return }
        }
        guard pressBecomesDrag() else {
            if activation == .release { activate() }
            return
        }
        guard let item = drag?.item() else { return }
        beginDrag(item, with: event)
    }

    /// 与 `WindowDragHandle` 一样自行跟踪这次按下，直到松开或移动超出阈值。
    private func pressBecomesDrag() -> Bool {
        guard let window else { return false }
        // 位移基于 `mouseLocation` 计算，避免坐标转换带来的漂移。
        let start = NSEvent.mouseLocation
        var passedSlop = false
        window.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { tracked, stop in
            guard let tracked, tracked.type != .leftMouseUp else {
                stop.pointee = true
                return
            }
            let mouse = NSEvent.mouseLocation
            guard hypot(mouse.x - start.x, mouse.y - start.y) > Self.dragSlop else { return }
            passedSlop = true
            stop.pointee = true
        }
        return passedSlop
    }

    /// 以给定事件开始一次拖拽会话，并把拖拽图像按光标居中。
    private func beginDrag(_ item: RowDragItem, with event: NSEvent) {
        let image = item.image
        let dragging = NSDraggingItem(pasteboardWriter: item.writer)
        // 尺寸取图像本身并居中于光标；若用行的形状会拉伸缩略图。
        let origin = convert(event.locationInWindow, from: nil)
        dragging.setDraggingFrame(
            NSRect(
                x: origin.x - image.size.width / 2, y: origin.y - image.size.height / 2,
                width: image.size.width, height: image.size.height),
            contents: image)
        let session = beginDraggingSession(with: [dragging], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    // MARK: - NSDraggingSource

    func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation
    ) {
        guard operation != [] else { return }
        drag?.dropped()
    }
}
