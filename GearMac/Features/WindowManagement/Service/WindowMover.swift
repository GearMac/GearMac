// 文件职责：通过 AX 把窗口命令（移动/缩放/平铺/全屏等）落到目标窗口上。
// 分层：Service；@MainActor 隔离，外部窗口经 AX 写入、自身窗口经 NSWindow 写入，二者统一到 decide→resolve→write→commit 流程。
import AppKit
@preconcurrency import ApplicationServices

/// 通过 AX 应用窗口命令。参见 docs/features/window-management.md#applying-a-placement。
@MainActor
final class WindowMover {
    /// `CFEqual`/`CFHash` 是受支持的身份判定；pid 用于区分两个进程的元素。
    private struct ExternalKey: Hashable {
        let pid: pid_t
        let element: AXUIElement

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.pid == rhs.pid && CFEqual(lhs.element, rhs.element)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(pid)
            hasher.combine(CFHash(element))
        }
    }

    /// 已关闭窗口的标识可以被复用；`decide` 会根据 frame 拒绝过期记录。
    private enum MoverKey: Hashable {
        case external(ExternalKey)
        case own(ObjectIdentifier)
    }

    /// 要么是我们自己的窗口，要么是其他应用的：对自身进程发起 AX 调用会卡住主线程。
    @MainActor
    private enum Surface {
        case external(application: AXUIElement, window: AXUIElement)
        case own(NSWindow)

        var isFullScreen: Bool {
            switch self {
            case .external(_, let window): AXWindowAccess.isFullScreen(window)
            case .own(let window): window.styleMask.contains(.fullScreen)
            }
        }

        var canMove: Bool {
            switch self {
            case .external(_, let window):
                AXWindowAccess.isSettable(kAXPositionAttribute, on: window)
            case .own(let window): window.isMovable
            }
        }

        var canResize: Bool {
            switch self {
            case .external(_, let window):
                AXWindowAccess.isSettable(kAXSizeAttribute, on: window)
            case .own(let window): window.styleMask.contains(.resizable)
            }
        }

        func frame(in geometry: AXGeometry) -> CGRect? {
            switch self {
            case .external(_, let window): AXWindowAccess.frame(of: window)
            case .own(let window): geometry.flip(window.frame)
            }
        }

        /// 我们自己的窗口无需抑制：那是远程应用的辅助功能设置。
        func suppressEnhancedUserInterface() -> () -> Void {
            guard case .external(let application, _) = self else { return {} }
            return AXWindowAccess.suppressEnhancedUserInterface(on: application)
        }

        func write(
            _ placement: WindowPlacementEngine.Placement, current: CGRect, canResize: Bool,
            canvas: CGRect?, geometry: AXGeometry
        ) -> CGRect? {
            switch self {
            case .external(_, let window):
                AXWindowAccess.write(
                    placement.frame, anchor: placement.anchor, to: window, current: current,
                    canResize: canResize, canvas: canvas)
            case .own(let window):
                Self.writeOwn(
                    placement, to: window, current: current, canResize: canResize,
                    canvas: canvas, geometry: geometry)
            }
        }

        /// `setFrame` 是原子且本地的，因此 AX 的 size → position → size 序列无额外收益。
        private static func writeOwn(
            _ placement: WindowPlacementEngine.Placement, to window: NSWindow, current: CGRect,
            canResize: Bool, canvas: CGRect?, geometry: AXGeometry
        ) -> CGRect? {
            var target =
                canResize
                ? placement.frame : placement.anchor.place(current.size, in: placement.frame)
            if !canResize, let canvas {
                target = WindowPlacementEngine.clamped(target, into: canvas)
            }
            window.setFrame(geometry.flip(WindowPlacementEngine.rounded(target)), display: true)
            var actual = geometry.flip(window.frame)

            // `contentMinSize` 可能拒绝宽度或高度；按锚点重新安放一次。
            if actual.width > target.width + AXWindowAccess.clampTolerance
                || actual.height > target.height + AXWindowAccess.clampTolerance
            {
                var slot = placement.anchor.place(actual.size, in: placement.frame)
                if let canvas { slot = WindowPlacementEngine.clamped(slot, into: canvas) }
                window.setFrameOrigin(geometry.flip(WindowPlacementEngine.rounded(slot)).origin)
                actual = geometry.flip(window.frame)
            }
            return actual
        }
    }

    private var memory = WindowActionMemory<MoverKey>()
    private var terminationToken: NotificationToken?
    private var windowCloseToken: NotificationToken?

    init() {
        // 丢弃已退出应用的窗口，而不是等待 LRU 淘汰来回收它们。
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated {
                self?.memory.forget { key in
                    guard case .external(let external) = key else { return false }
                    return external.pid == pid
                }
            }
        }
        terminationToken = NotificationToken(token, center: NSWorkspace.shared.notificationCenter)

        // 已关闭窗口的标识可以被复用，因此在它还属于我们时就把记录丢弃。
        let closeToken = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let closed = note.object as? NSWindow else { return }
            let key = MoverKey.own(ObjectIdentifier(closed))
            Task { @MainActor [weak self] in self?.memory.forget(key: key) }
        }
        windowCloseToken = NotificationToken(closeToken, center: .default)
    }

    /// 一次按键只解析一次的命令目标窗口。
    private struct FocusedWindow {
        let surface: Surface
        let key: MoverKey
    }

    /// 把观测到的 frame、显示器集合与记忆层的决策汇总成一个目标。
    private typealias Resolver = (
        _ current: CGRect, _ screens: [WindowPlacementEngine.Screen],
        _ decision: WindowActionMemory<MoverKey>.Decision
    ) -> WindowPlacementEngine.Placement?

    /// 对 `target` 的聚焦窗口执行 `command`，返回是否发生了实际变化。
    @discardableResult
    func perform(
        _ command: WindowCommand.ID, target: WindowTarget?, gap: CGFloat, cycle: WindowCycle
    ) -> Bool {
        guard let catalogued = WindowCommandCatalog.command(id: command),
            let focused = focusedWindow(of: target)
        else { return false }

        if catalogued.kind == .fullscreen {
            guard toggleFullScreen(focused.surface) else { return false }
            // 尺寸链在这里无关紧要，但 GearMac 介入前的 frame 仍是 Restore 的目标。
            memory.forgetCycle(key: focused.key)
            return true
        }
        return place(
            focused, command: command, gap: gap,
            cycleLength: {
                WindowPlacementEngine.cycleLength(for: command, screens: $0, cycle: cycle)
            }
        ) { current, screens, decision in
            WindowPlacementEngine.placement(
                for: WindowPlacementEngine.Input(
                    command: command, windowFrame: current, screens: screens, gap: gap,
                    step: decision.step, cycle: cycle, originScreenID: decision.originScreenID,
                    restoreFrame: decision.canRestore ? decision.restoreFrame : nil,
                    lastTileCommand: decision.lastTileCommand))
        }
    }

    /// 对 `target` 的聚焦窗口应用 `size`；Restore 像任何命令一样将其撤销。
    @discardableResult
    func perform(_ size: CustomWindowSize, target: WindowTarget?, gap: CGFloat) -> Bool {
        guard let focused = focusedWindow(of: target) else { return false }
        return place(
            focused, command: nil, gap: gap, cycleLength: { _ in 1 },
            resolve: { current, screens, _ in
                size.placement(for: current, screens: screens, gap: gap)
            })
    }

    private func focusedWindow(of target: WindowTarget?) -> FocusedWindow? {
        switch target {
        case .own(let window):
            // 摆放我们自己的窗口无需辅助功能授权。
            guard window.isVisible else { return nil }
            return FocusedWindow(surface: .own(window), key: .own(ObjectIdentifier(window)))
        case .external(let app):
            // 由显式的用户手势触发，因此在这里请求授权是正确的。
            guard Permissions.ensureAccessibility() else { return nil }
            guard !app.isTerminated,
                app.processIdentifier != ProcessInfo.processInfo.processIdentifier
            else { return nil }

            let application = AXWindowAccess.application(for: app.processIdentifier)
            guard let window = AXWindowAccess.targetWindow(in: application) else { return nil }
            AXUIElementSetMessagingTimeout(window, AXWindowAccess.messagingTimeout)
            return FocusedWindow(
                surface: .external(application: application, window: window),
                key: .external(ExternalKey(pid: app.processIdentifier, element: window)))
        case nil:
            return nil
        }
    }

    /// 每次几何命令都要走的唯一 decide → resolve → write → commit 序列。
    private func place(
        _ focused: FocusedWindow, command: WindowCommand.ID?, gap: CGFloat,
        cycleLength: ([WindowPlacementEngine.Screen]) -> Int, resolve: Resolver
    ) -> Bool {
        let surface = focused.surface
        let geometry = AXGeometry(screens: NSScreen.screens)
        // 对原生全屏窗口做平铺会与窗口服务器冲突；保持原样。
        guard !surface.isFullScreen, let current = surface.frame(in: geometry) else { return false }

        let screens = AXScreens.converted(NSScreen.screens, geometry: geometry)
        guard let host = WindowPlacementEngine.screen(containing: current, in: screens) else {
            return false
        }

        // 整个命令只用一个时间戳，因此循环超时不会跨越两次读数。
        let now = Date()
        let decision = memory.decide(
            key: focused.key, command: command, currentFrame: current, currentScreenID: host.id,
            cycleLength: cycleLength(screens), now: now)
        guard let placement = resolve(current, screens, decision) else { return false }

        // 在写入前检查，因此无法定位的窗口会保持原样。
        guard surface.canMove else { return false }
        let canResize = placement.resizes && surface.canResize

        let destination = screens.first { $0.id == placement.screenID }
        let canvas = destination.map {
            WindowPlacementEngine.canvas(
                $0.visibleFrame,
                gap: WindowPlacementEngine.sanitizedGap(gap, in: $0.visibleFrame))
        }
        let restoreEnhancedUI = canResize ? surface.suppressEnhancedUserInterface() : {}
        defer { restoreEnhancedUI() }

        guard
            let applied = surface.write(
                placement, current: current, canResize: canResize, canvas: canvas,
                geometry: geometry)
        else { return false }

        let landedOn =
            WindowPlacementEngine.screen(containing: applied, in: screens)?.id
            ?? placement.screenID
        memory.commit(
            key: focused.key, command: command, decision: decision, appliedFrame: applied,
            screenID: landedOn, now: now)
        return !applied.equalTo(current)
    }

    // MARK: - Fullscreen

    /// 先尝试 `AXFullScreen`，再尝试绿色按钮。docs/features/window-management.md
    private func toggleFullScreen(_ surface: Surface) -> Bool {
        switch surface {
        case .own(let window):
            // AppKit 会让任何可缩放窗口进入全屏，除非它选择退出，如“备忘录”面板那样。
            guard window.styleMask.contains(.resizable),
                window.collectionBehavior.isDisjoint(with: [.fullScreenAuxiliary, .fullScreenNone])
            else { return false }
            window.toggleFullScreen(nil)
            return true
        case .external(_, let window):
            let target: CFBoolean =
                AXWindowAccess.isFullScreen(window) ? kCFBooleanFalse : kCFBooleanTrue
            if AXWindowAccess.isSettable(
                AXWindowAccess.fullScreenAttribute as String, on: window),
                AXUIElementSetAttributeValue(
                    window, AXWindowAccess.fullScreenAttribute, target) == .success
            {
                return true
            }
            guard
                let button = AXWindowAccess.element(
                    window, AXWindowAccess.fullScreenButtonAttribute as String)
            else { return false }
            return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
        }
    }
}
