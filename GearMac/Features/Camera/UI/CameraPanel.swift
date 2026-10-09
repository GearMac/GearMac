// 文件职责：摄像头浮层面板（NSPanel）：键盘事件分发（↵/Esc）、失焦点击监听与屏幕居中。
// 分层：UI（AppKit）；面板为非激活式，全部按键处理集中在 sendEvent，不依赖子视图获得焦点。
import AppKit
import Carbon.HIToolbox

/// 摄像头界面的面板；按键经由 `sendEvent` 分发，因此 ↵ 与 Esc 无需任何子视图获得焦点。
final class CameraPanel: NSPanel {
    /// 面板动作：主操作（↵）与取消（Esc）。
    enum Action {
        case primary
        case cancel
    }

    var onAction: ((Action) -> Void)?
    private var clickMonitors: [Any] = []

    /// 创建无边框非激活式浮动面板，并以传入视图作为内容。
    init(content: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: content.frame.size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // 层级高于面板、低于对话框：确认框必须仍能压在其上。
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // 关闭 AppKit 自带的窗口动画，改由 `fadeIn`/`fadeOut` 实现。
        animationBehavior = .none
        isReleasedWhenClosed = false
        isRestorable = false
        contentView = content
    }

    /// 拦截 Esc/回车：直接触发对应动作，其余事件交回父类。
    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown, let onAction else {
            super.sendEvent(event)
            return
        }
        switch Int(event.keyCode) {
        case kVK_Escape:
            onAction(.cancel)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            onAction(.primary)
        default:
            super.sendEvent(event)
        }
    }

    /// 获得焦点时停止外部点击监听。
    override func becomeKey() {
        super.becomeKey()
        stopWatchingClicks()
    }

    /// 失去焦点通常意味着点击了别处，除非是系统 UI 抢占：菜单栏切换场景时保留画面。
    override func resignKey() {
        super.resignKey()
        guard let onAction else { return }
        if Self.systemUIIsUnderPointer { watchForClickAway() } else { onAction(.cancel) }
    }

    /// 面板移出屏幕时停止点击监听。
    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        stopWatchingClicks()
    }

    /// 焦点已失去时，再点击别处不会产生新的 `resignKey`，只有事件监听器能捕获到。
    private func watchForClickAway() {
        guard clickMonitors.isEmpty else { return }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let otherApps = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            self?.clickedAway()
        }
        // 全局监听看不到本应用自己的窗口，因此需要本地监听补上。
        let thisApp = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            if event.window !== self { self?.clickedAway() }
            return event
        }
        clickMonitors = [otherApps, thisApp].compactMap { $0 }
    }

    /// 处理点击离开：系统 UI 下忽略，否则取消并停止监听。
    private func clickedAway() {
        guard !Self.systemUIIsUnderPointer else { return }
        stopWatchingClicks()
        onAction?(.cancel)
    }

    /// 移除全部点击监听器。
    private func stopWatchingClicks() {
        clickMonitors.forEach(NSEvent.removeMonitor)
        clickMonitors = []
    }

    /// 菜单栏、其下拉菜单与 Dock 的窗口层级都等于或高于 Dock。
    private static var systemUIIsUnderPointer: Bool {
        let pointer = NSEvent.mouseLocation
        let number = NSWindow.windowNumber(at: pointer, belowWindowWithWindowNumber: 0)
        guard number > 0,
            let info = CGWindowListCopyWindowInfo(
                [.optionOnScreenAboveWindow, .optionIncludingWindow], CGWindowID(number))
                as? [[String: Any]],
            let window = info.first(where: { ($0[kCGWindowNumber as String] as? Int) == number }),
            let layer = window[kCGWindowLayer as String] as? Int
        else { return false }
        return layer >= Int(CGWindowLevelForKey(.dockWindow))
    }

    /// 在鼠标所在屏幕上做视觉居中，并像对话框一样略微上移。
    func centerOnCursorScreen() {
        guard let visible = NSScreen.underCursor?.visibleFrame else { return }
        let size = frame.size
        setFrameOrigin(
            NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.midY - size.height / 2 + visible.height * Self.centerLift))
    }

    /// 居中的垂直上移比例。
    private static let centerLift: CGFloat = 0.08

    /// 面板可以成为 key window，以接收按键。
    override var canBecomeKey: Bool { true }
    /// 但不需要成为 main window。
    override var canBecomeMain: Bool { false }
}
