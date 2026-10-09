// 文件职责：实现细的自动隐藏 SwiftUI 覆盖式滚动条（滚动时显示细滑块，悬停时展开轨道）。
// 分层：UI（SwiftUI ViewModifier + AppKit 交互视图）；所有指针处理都放在 AppKit 的 `ScrollbarInteraction` 中，以绕过 SwiftUI/AppKit 事件路由的缺口。
import AppKit
import SwiftUI

/// 细的自动隐藏 SwiftUI 覆盖式滚动条（滚动时显示细滑块，加上悬停时才露出的轨道）；所有指针处理都隔离在 AppKit 的 `ScrollbarInteraction` 视图中，以绕过 SwiftUI/AppKit 事件路由的缺口。
struct ThinScrollbar: ViewModifier {
    private struct Metrics: Equatable {
        /// 原始的 `contentOffset.y`；在带 `safeAreaInset` 浮动条时它静止于 `-insetTop`，因此映射到轨道比例前需用 `insetTop` 归一化。
        var offset: CGFloat = 0
        var insetTop: CGFloat = 0
        var content: CGFloat = 0
        var viewport: CGFloat = 0
        var scrollable: Bool { content > viewport + 1 }
    }

    // 交互信号——分开保存，使每个「显示滚动条」的来源彼此独立。
    @State private var isScrolling = false
    @State private var isHoveringTrack = false
    /// 镜像 AppKit 侧的滑块拖动状态（真正的拖动状态由 `ScrollbarInteraction` 持有）。
    @State private var isDragging = false

    @State private var metrics = Metrics()
    /// 即时的「指针位于右侧悬停区」镜像，用于检测区域状态的切换。
    @State private var inZone = false
    @State private var scrollStop: Task<Void, Never>?
    @State private var hoverExit: Task<Void, Never>?

    // 滑块/轨道几何参数：静止时较细，悬停/拖动时变粗——类似 macOS 的 overlay 滑块。
    private let thinWidth: CGFloat = 6
    private let expandedWidth: CGFloat = 10
    private let inset: CGFloat = 3
    private let minThumb: CGFloat = 28
    private let hoverZone: CGFloat = 16  // 用于揭示轨道的右侧条带；比滑块本身更宽

    // 各交互过渡共用的动画曲线。
    private let fadeCurve: Animation = .easeOut(duration: 0.18)
    private let morphCurve: Animation = .spring(response: 0.28, dampingFraction: 0.85)

    private var visible: Bool { isScrolling || isHoveringTrack || isDragging }
    private var expanded: Bool { isHoveringTrack || isDragging }

    func body(content: Content) -> some View {
        content
            .scrollIndicators(.hidden)  // 完全去掉原生滚动条（及其闪烁效果）
            // 几何信息只用于决定滑块的尺寸/位置，绝不用来决定其可见性。
            .onScrollGeometryChange(for: Metrics.self) { geo in
                Metrics(
                    offset: geo.contentOffset.y,
                    insetTop: geo.contentInsets.top,
                    content: geo.contentSize.height,
                    viewport: geo.containerSize.height
                )
            } action: { _, new in
                metrics = new
            }
            // 滚动会显示滑块（而非轨道），并在停止后稍晚重新隐藏；拖动滑块没有滚动阶段，其可见性由各自的处理函数负责。
            .onScrollPhaseChange { _, phase in
                guard !isDragging else { return }
                phase == .idle ? scheduleScrollStop() : beganScrolling()
            }
            .overlay(alignment: .topTrailing) { bar }
            // 用一个覆盖整条右侧条带的跟踪视图接管所有指针处理：除滑块范围外全部透明；在滑块上时接管拖动并转发滚轮事件，且不会像内容级 hover 那样让轨道闪烁。
            .overlay {
                ScrollbarInteraction(
                    edgeWidth: hoverZone,
                    inset: inset,
                    thumbY: thumbOffset,
                    thumbHeight: thumbHeight,
                    thumbGrabbable: metrics.scrollable && visible,
                    railActive: metrics.scrollable && expanded,
                    onZoneChange: updateZone,
                    onDragChange: dragChanged
                )
            }
    }

    @ViewBuilder private var bar: some View {
        if metrics.scrollable {
            ZStack(alignment: .top) {
                // 轨道：一条淡淡的满高背景，只在悬停/拖动时出现。
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .frame(width: expandedWidth, height: track)
                    .offset(y: inset)
                    .opacity(expanded ? 1 : 0)

                // 滑块：按比例计算的把手，静止时较细，展开时变粗。
                Capsule()
                    .fill(Color.primary.opacity(isDragging ? 0.5 : (expanded ? 0.42 : 0.30)))
                    .frame(width: expanded ? expandedWidth : thinWidth, height: thumbHeight)
                    .frame(width: expandedWidth)
                    .offset(y: thumbOffset)
                    .opacity(visible ? 1 : 0)
            }
            .frame(width: expandedWidth)
            .padding(.trailing, inset)
            // 纯视觉元素；点击、拖动与滚轮转发都由上层的 ScrollbarInteraction 负责。
            .allowsHitTesting(false)
        }
    }

    /// 可用的垂直行程，上下两端各留出一点内边距。
    private var track: CGFloat { max(0, metrics.viewport - inset * 2) }

    private var thumbHeight: CGFloat {
        guard metrics.content > 0 else { return minThumb }
        return min(track, max(minThumb, track * metrics.viewport / metrics.content))
    }

    private var thumbOffset: CGFloat {
        let maxScroll = max(0, metrics.content - metrics.viewport)
        guard maxScroll > 0 else { return inset }
        let fraction = min(1, max(0, (metrics.offset + metrics.insetTop) / maxScroll))
        return inset + fraction * (track - thumbHeight)
    }

    // MARK: - Scroll signal

    private func beganScrolling() {
        scrollStop?.cancel()
        withAnimation(fadeCurve) { isScrolling = true }
    }

    /// 滚动停止后稍晚淡出滑块，与原生 overlay 滚动条一致。
    private func scheduleScrollStop() {
        scrollStop?.cancel()
        scrollStop = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            withAnimation(fadeCurve) { isScrolling = false }
        }
    }

    // MARK: - Drag signal

    private func dragChanged(_ dragging: Bool) {
        withAnimation(morphCurve) { isDragging = dragging }
        if dragging {
            scrollStop?.cancel()
        } else {
            // 像普通滚动一样多停留一会儿，之后若不再悬停/滚动则淡出。
            isScrolling = true
            scheduleScrollStop()
        }
    }

    // MARK: - Hover signal

    /// 每次指针移动都会调用；只在进入/离开区域这一*状态切换*时才真正处理。
    private func updateZone(_ nowInZone: Bool) {
        guard nowInZone != inZone else { return }
        inZone = nowInZone
        if nowInZone {
            hoverExit?.cancel()
            withAnimation(morphCurve) { isHoveringTrack = true }
        } else {
            scheduleHoverExit()
        }
    }

    /// 离开区域后延迟一小段时间才收起轨道，避免短暂移出造成闪烁。
    private func scheduleHoverExit() {
        hoverExit?.cancel()
        hoverExit = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            withAnimation(morphCurve) { isHoveringTrack = false }
        }
    }
}

extension View {
    /// 附加到 `ScrollView` 上，得到只在滚动时出现的细滚动条。
    func thinScrollbar() -> some View {
        modifier(ThinScrollbar())
    }

    /// 附加在 `ScrollView` *内部*（作用于其内容），移除原生滚动条，使只剩我们的 `thinScrollbar` 可见。
    func hideNativeScrollers() -> some View {
        background(NativeScrollerHider().frame(width: 0, height: 0))
    }
}

/// 把背后的 `NSScrollView` 强制为隐藏的 `.overlay` 滚动条样式（去掉常驻的旧式控件及其占用的边槽），并在 `preferredScrollerStyleDidChangeNotification` 时重新施加，因为 macOS 否则会把它改回去。
private struct NativeScrollerHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { HiderView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? HiderView)?.applyOverlayStyle()
    }

    private final class HiderView: NSView {
        private var retriesLeft = 10
        private var styleChangeObserver: NotificationToken?

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }
        override init(frame: NSRect) { super.init(frame: frame) }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                stopObservingStyleChanges()
                return
            }
            startObservingStyleChanges()
            retriesLeft = 10  // (重新)挂载后是全新的视图层级，因此重新允许拼接重试几次
            applyOverlayStyle()
        }

        private func startObservingStyleChanges() {
            guard styleChangeObserver == nil else { return }
            let token = NotificationCenter.default.addObserver(
                forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                // 在下一轮事件循环（AppKit 自身的处理已重置样式之后）重新施加。
                DispatchQueue.main.async { self?.applyOverlayStyle() }
            }
            styleChangeObserver = NotificationToken(token, center: .default)
        }

        private func stopObservingStyleChanges() {
            styleChangeObserver = nil
        }

        func applyOverlayStyle() {
            guard let scrollView = enclosingScrollView else {
                // 尚未拼接到滚动视图的层级中；下一轮重试，且次数有上限，避免永远未加入的视图在主线程上空转。
                guard retriesLeft > 0 else { return }
                retriesLeft -= 1
                DispatchQueue.main.async { [weak self] in self?.applyOverlayStyle() }
                return
            }
            // 幂等：已处于目标状态就提前返回，使重复执行不会反复触发布局。
            guard
                scrollView.scrollerStyle != .overlay
                    || scrollView.hasVerticalScroller
                    || scrollView.hasHorizontalScroller
            else { return }
            scrollView.scrollerStyle = .overlay  // 浮在内容之上——不占用布局宽度
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            // 在同一次布局中回收旧式滚动条占用的右侧边槽。
            scrollView.tile()
        }
    }
}

/// 唯一的 AppKit 视图（背后 `NSScrollView` 的兄弟视图），负责悬停跟踪、滑块拖动/轨道点击与滚轮转发；它直接驱动 clip view，因为 SwiftUI 的滚动 API 与响应链无法可靠地触达它。
private struct ScrollbarInteraction: NSViewRepresentable {
    let edgeWidth: CGFloat
    let inset: CGFloat
    let thumbY: CGFloat
    let thumbHeight: CGFloat
    let thumbGrabbable: Bool
    let railActive: Bool
    let onZoneChange: @MainActor (Bool) -> Void
    let onDragChange: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        InteractionView(onZoneChange: onZoneChange, onDragChange: onDragChange)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? InteractionView else { return }
        view.edgeWidth = edgeWidth
        view.inset = inset
        view.thumbY = thumbY
        view.thumbHeight = thumbHeight
        view.thumbGrabbable = thumbGrabbable
        view.railActive = railActive
        view.onZoneChange = onZoneChange
        view.onDragChange = onDragChange
    }

    private final class InteractionView: NSView {
        var edgeWidth: CGFloat = 0
        var inset: CGFloat = 0
        var thumbY: CGFloat = 0
        var thumbHeight: CGFloat = 0
        var thumbGrabbable = false
        var railActive = false
        var onZoneChange: @MainActor (Bool) -> Void
        var onDragChange: @MainActor (Bool) -> Void

        private var lastInZone = false
        /// 在 `mouseDown` 时记录指针 y 坐标与内容偏移；仅在拖动滑块期间非 nil。
        private var dragStart: (pointerY: CGFloat, offset: CGFloat)?
        private weak var scrollView: NSScrollView?

        init(
            onZoneChange: @escaping @MainActor (Bool) -> Void,
            onDragChange: @escaping @MainActor (Bool) -> Void
        ) {
            self.onZoneChange = onZoneChange
            self.onDragChange = onDragChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        // 与 SwiftUI 自上而下的坐标系一致，这样 `thumbY` 可以直接使用。
        override var isFlipped: Bool { true }

        // MARK: Hit testing

        /// 在滑块的抓取条带内（轨道展开时为整条右侧条带）不透明，其余位置透明，使内容点击与滚轮事件能穿透。
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let superview else { return nil }
            let p = convert(point, from: superview)
            if grabRect.contains(p) { return self }
            if railActive && p.x >= bounds.width - edgeWidth { return self }
            return nil
        }

        /// 在滑块所处的纵向范围上取整条右侧条带宽度，使极细的滑块也易于抓取。
        private var grabRect: CGRect {
            guard thumbGrabbable else { return .null }
            return CGRect(
                x: bounds.width - edgeWidth, y: thumbY, width: edgeWidth, height: thumbHeight)
        }

        // MARK: Wheel routing

        /// 滚轮事件只有在滚动条上方才会到达这里；把它们交给响应链本来会绕过的兄弟滚动视图处理。
        override func scrollWheel(with event: NSEvent) {
            if let target = targetScrollView() {
                target.scrollWheel(with: event)
            } else {
                super.scrollWheel(with: event)
            }
        }

        // MARK: Thumb drag & track click

        override func mouseDown(with event: NSEvent) {
            guard let target = targetScrollView() else { return }
            let p = convert(event.locationInWindow, from: nil)
            // 点击滑块范围之外的轨道时，滑块会跳到以指针为中心的位置，随后作为拖动继续。
            if !(thumbY...(thumbY + thumbHeight)).contains(p.y) {
                jumpThumb(toPointerY: p.y, in: target)
            }
            dragStart = (p.y, target.contentView.bounds.origin.y)
            onDragChange(true)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let dragStart, let target = targetScrollView() else { return }
            let (minOffset, maxOffset) = offsetRange(of: target.contentView)
            let travel = trackTravel
            guard maxOffset > minOffset, travel > 0 else { return }
            let p = convert(event.locationInWindow, from: nil)
            // 把滑块行程映射回内容偏移，并以 mouse-down 时的位置为基准，使被夹取的过度拖动不会产生漂移。
            let offset =
                dragStart.offset + (p.y - dragStart.pointerY) / travel * (maxOffset - minOffset)
            scroll(target, toOffset: min(maxOffset, max(minOffset, offset)))
        }

        override func mouseUp(with event: NSEvent) {
            guard dragStart != nil else { return }
            dragStart = nil
            onDragChange(false)
        }

        /// 滑块在轨道坐标中的行程：轨道高度减去滑块高度。
        private var trackTravel: CGFloat { (bounds.height - inset * 2) - thumbHeight }

        /// 滚动到滑块中心落在给定指针 y 坐标处（并夹取到轨道范围内）。
        private func jumpThumb(toPointerY y: CGFloat, in target: NSScrollView) {
            let (minOffset, maxOffset) = offsetRange(of: target.contentView)
            let travel = trackTravel
            guard maxOffset > minOffset, travel > 0 else { return }
            let thumbTop = min(inset + travel, max(inset, y - thumbHeight / 2))
            let fraction = (thumbTop - inset) / travel
            scroll(target, toOffset: minOffset + fraction * (maxOffset - minOffset))
        }

        /// 借助 AppKit 自身的约束逻辑求得 clip view 合法的 `bounds.origin.y` 范围；相比简单的 `[0, content − viewport]` 夹取，它能正确处理 inset。
        private func offsetRange(of clip: NSClipView) -> (min: CGFloat, max: CGFloat) {
            var probe = clip.bounds
            probe.origin.y = -1_000_000_000
            let minY = clip.constrainBoundsRect(probe).origin.y
            probe.origin.y = 1_000_000_000
            let maxY = clip.constrainBoundsRect(probe).origin.y
            return (minY, maxY)
        }

        private func scroll(_ target: NSScrollView, toOffset y: CGFloat) {
            let clip = target.contentView
            var origin = clip.bounds.origin
            origin.y = y
            clip.scroll(to: origin)
            target.reflectScrolledClipView(clip)
        }

        /// 取得背后的 `NSScrollView`：向上逐层查找兄弟子树中最近的滚动视图（因为 `enclosingScrollView` 无法到达兄弟视图），并做弱引用缓存。
        private func targetScrollView() -> NSScrollView? {
            if let scrollView, scrollView.window === window { return scrollView }
            var branch: NSView = self
            var node = superview
            while let ancestor = node {
                if let found = Self.firstScrollView(under: ancestor, excluding: branch) {
                    scrollView = found
                    return found
                }
                branch = ancestor
                node = ancestor.superview
            }
            return nil
        }

        private static func firstScrollView(under view: NSView, excluding: NSView?) -> NSScrollView? {
            for sub in view.subviews where sub !== excluding {
                if let scroll = sub as? NSScrollView { return scroll }
                if let scroll = firstScrollView(under: sub, excluding: nil) { return scroll }
            }
            return nil
        }

        // MARK: Hover tracking

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            // `.inVisibleRect` 让跟踪区域随尺寸变化；`.activeAlways` 使非 key 窗口下悬停也能显示轨道。
            addTrackingArea(
                NSTrackingArea(
                    rect: .zero,
                    options: [
                        .mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect
                    ],
                    owner: self
                ))
        }

        override func mouseMoved(with event: NSEvent) { report(event) }
        override func mouseEntered(with event: NSEvent) { report(event) }
        override func mouseExited(with event: NSEvent) { update(inZone: false) }

        private func report(_ event: NSEvent) {
            let x = convert(event.locationInWindow, from: nil).x
            update(inZone: x >= bounds.width - edgeWidth)
        }

        /// 只在区域状态切换时触发回调，使大量 `mouseMoved` 事件的开销保持很低。
        private func update(inZone: Bool) {
            guard inZone != lastInZone else { return }
            lastInZone = inZone
            onZoneChange(inZone)
        }
    }
}
