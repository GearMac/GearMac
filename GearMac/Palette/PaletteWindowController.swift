// 文件职责：管理 Palette 的 NSPanel——创建窗口、显示/隐藏、定位与拖拽吸附、粘贴及快捷键监听，并实现 NSWindowDelegate 回调。
// 分层：Coordinator（@MainActor）；窗口状态变更全部回到主 actor，隐藏时释放预览缓存。
import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class PaletteWindowController: NSObject, NSWindowDelegate {
    private unowned let core: AppCore
    private var panel: PalettePanel?
    private(set) var previousApp: NSRunningApplication?
    /// 唤起时的本应用 key window：隐藏时把焦点交还给它（例如 Settings），而非某个已过期的 App。
    private(set) weak var previousOwnWindow: NSWindow?
    private var popToRootTimer: Timer?
    // 重新打开早于超时，因此选中被保留的查询文本。
    private var queryWasPreserved = false
    /// 在隐藏期间回到根搜索时置位，并由下一次 show 消费：该屏幕已经是全新的。
    private(set) var isPoppedToRoot = false
    /// 每次显示时解析一次；顶边是绝不能漂移的那条边。
    private var anchor: CGPoint?
    /// 由我们自己的 setFrame 引起的位置变化；此时不得把它当作用户拖动或锚点漂移。
    private var applyingLayoutFrame = false
    /// 仅在拖拽柄按下与松手之间存在；为 nil 表示这次移动由我们自身引起。
    private var drag: DragSession?
    private let dropGuides = PaletteDropGuideController()
    /// ⌘V：当剪贴板同时含有文本时，`Edit ▸ Paste` 会在 `sendEvent` 之前先认领它。
    private var pasteMonitor: Any?
    /// ⌘⎋：该组合键被窗口服务器接管，响应者链收不到任何按键事件，因此需要全局 tap。
    private lazy var commandEscapeTap = CommandEscapeTap { [weak self] in
        guard let self, self.panel?.isKeyWindow == true else { return false }
        self.core.palette.prepare(mode: .launcher)
        return true
    }

    /// 拖拽进行中的中心线及其高度档位。
    private struct DragSession {
        var home: CGPoint
        var screenFrame: CGRect
        var visibleFrame: CGRect
        var displayKey: String
        var snap: PalettePlacement.Snap
        var verticalEntryY: CGFloat?
        var lastRawAnchor: CGPoint
        var lastSampleTime: TimeInterval?
        var moved = false
    }

    init(core: AppCore) {
        self.core = core
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// 面板在屏幕坐标中的位置，供其下方绘制的覆盖层避让。
    var visibleFrame: CGRect? { panel.flatMap { $0.isVisible ? $0.frame : nil } }

    /// 面板自身的视图，供必须锚定到它的 AppKit UI 使用（而非直接绘制）。
    var anchorView: NSView? { panel?.isVisible == true ? panel?.contentView : nil }

    /// 面板被唤起时遮盖的内容，供其在关闭时展开填充的目标使用。
    var previousTarget: InjectionTarget? {
        InjectionTarget.behindPalette(ownWindow: previousOwnWindow, app: previousApp)
    }

    /// 显示面板：记录前置 App/窗口与粘贴目标，按当前折叠状态定位后再置前。
    func show() {
        Signposts.interval("PaletteWindowController.show") {
            isPoppedToRoot = false
            // 覆盖在我们自己的窗口上唤起时，没有外部的粘贴或焦点目标。
            let frontmost = NSWorkspace.shared.frontmostApplication
            let ownPID = NSRunningApplication.current.processIdentifier
            previousApp = frontmost?.processIdentifier == ownPID ? nil : frontmost
            // 即使前台是别的 App 也记录：我们的面板不激活即可取得 key 状态。
            let key = NSApp.keyWindow
            // 模式切换会在面板仍持有 key 时重新显示它；此时保留它已记录的值。
            if key !== panel { previousOwnWindow = key }
            // 每次唤起只做一次，且源自 `previousApp`，这样标签才能指向粘贴目标。
            core.palette.pasteTarget = PasteTarget(app: previousApp)
            let panel = ensurePanel()
            // 撤销模态窗口遗留的降级层级，除非仍有模态窗口存在。
            if NSApp.modalWindow == nil { panel.level = .palette }
            // 打开时先解除悬停高亮：已经停在某行上的指针不应高亮该行。
            core.palette.disarmHoverHighlight(pointerAt: NSEvent.mouseLocation)
            // 现在重新解析锚点并保持，使后续尺寸变化不会移动窗口。
            anchor = nil
            // 在置前之前先定好尺寸与位置，紧凑唤起才不会闪烁。
            positionPanel(panel, collapsed: core.paletteCoordinator.paletteIsCollapsed)
            // 在屏幕外先完成首次挂载布局，使用户看不到安全区调整的过程。
            panel.contentView?.layoutSubtreeIfNeeded()
            core.inputSourceSwitcher.beginSession(
                preferredInputSourceID: core.settings.autoSwitchInputSourceID)
            // 面板关闭期间事件会过期，倒计时也只在其显示时推进。
            core.calendarCoordinator.paletteDidShow()
            core.palette.noteVisible(true)
            core.clipboardStore.setTextSearchActive(true)
            // 仅在我们显示时启用：全局 tap 不应比窗口存活更久。
            commandEscapeTap.enable()
            // 不激活应用，唤起时不会把本应用的其他辅助窗口顶到它后面。
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
            // 从未激活过的登录项可能丢掉第一次 key 请求，因此再断言一次。
            DispatchQueue.main.async { [weak panel] in
                guard let panel, panel.isVisible, !panel.isKeyWindow else { return }
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    // 使用 isolated，使 deinit 能安全访问主 actor 的监听器；闭包本身已是弱引用。
    isolated deinit {
        if let pasteMonitor { NSEvent.removeMonitor(pasteMonitor) }
    }

    /// 解析纯 ⌘ 组合键对应的字符，经由 ASCII 布局解析，使其不受输入法影响。
    private static func commandCharacter(from event: NSEvent) -> String? {
        guard !event.isARepeat,
            event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command
        else { return nil }
        return ASCIIKeyboardLayout.character(for: event)?.lowercased()
            ?? event.charactersIgnoringModifiers?.lowercased()
    }

    /// 允许带 Shift（多数布局上 ⌘+ 即 Shift+=），以基础按键为准。
    private static func emojiGridZoom(from event: NSEvent) -> EmojiGridZoom? {
        guard !event.isARepeat, event.modifierFlags.isDisjoint(with: [.option, .control]) else {
            return nil
        }
        switch ASCIIKeyboardLayout.character(for: event) {
        case "0": return .actualSize
        case "=", "+": return .zoomIn
        case "-": return .zoomOut
        default: return nil
        }
    }

    /// 本地监听器在菜单派发之前看到按键；返回 nil 即可吞掉该事件。
    private func installPasteMonitor() {
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self, self.panel?.isKeyWindow == true,
                Self.commandCharacter(from: event) == "v"
            else { return event }
            return self.attachPastedFile() ? nil : event
        }
    }

    /// 在此只读取一次：⌘V 属于按键路径，两条分支需要同一个结果。
    private func attachPastedFile() -> Bool {
        let files = PasteboardFiles.urls(on: .general)
        switch core.palette.mode {
        case .ai: return core.quickAICoordinator.attachPastedFile(files: files)
        case .launcher: return core.quickAICoordinator.attachPastedFileFromLauncher(files: files)
        default: return false
        }
    }

    /// 隐藏面板：停用全局 tap、结束各协调器会话并释放缓存；`restoreFocus` 为真时把焦点交还前置窗口或 App。
    func hide(restoreFocus: Bool) {
        panel?.orderOut(nil)
        commandEscapeTap.disable()
        core.inputSourceSwitcher.endSession()
        core.calendarCoordinator.paletteDidHide()
        core.roomCoordinator.paletteDidHide()
        core.palette.noteVisible(false)
        core.clipboardStore.setTextSearchActive(false)
        // 丢弃锚点，使下次唤起按当时使用的屏幕重新解析。
        anchor = nil
        // 拖拽参考线绝不能比它所指向的面板存活更久。
        drag = nil
        dropGuides.hide()
        // 释放数 MB 的预览位图，让闲置内存回落到接近基线。
        ImageThumbnail.purgePreviews()
        FilePreviewThumbnail.purgePreviews()
        IconCache.purgeFitted()
        schedulePopToRoot()
        guard restoreFocus else { return }
        // 优先选自己的窗口：它仍开着，激活其他 App 会把它埋掉。
        if let own = previousOwnWindow, own.isVisible {
            own.makeKeyAndOrderFront(nil)
        } else {
            previousApp?.activate()
        }
    }

    /// 回到根搜索：立即重置，或在延迟后重置——除非被重新打开消费掉。
    private func schedulePopToRoot() {
        // 扩展正在浏览器中等待 OAuth 授权时，不回到根搜索。
        guard !core.extensions.isAuthorizing else { return }
        popToRootTimer?.invalidate()
        let timeout = core.settings.popToRootTimeout
        guard timeout != .immediately else {
            popToRoot()
            return
        }
        popToRootTimer = Timer.scheduledTimer(withTimeInterval: timeout.interval, repeats: false) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.core.extensions.isAuthorizing else { return }
                self.popToRootTimer = nil
                self.popToRoot()
            }
        }
    }

    /// 只重置屏幕：对话不是键入的查询，其生命周期由 `Opens To` 设置决定。
    private func popToRoot() {
        core.palette.prepare(mode: .launcher)
        isPoppedToRoot = true
    }

    /// 跳过 Pop to Root Search 的延迟，用于既要隐藏又要重置的关闭。
    func popToRootNow() {
        guard !core.extensions.isAuthorizing else { return }
        popToRootTimer?.invalidate()
        popToRootTimer = nil
        popToRoot()
    }

    /// 隐藏的面板仍保留关闭前状态时为真；消费该状态即取消重置。
    func consumePreservedState() -> Bool {
        guard let timer = popToRootTimer else { return false }
        timer.invalidate()
        popToRootTimer = nil
        queryWasPreserved = true
        return true
    }

    /// 在面板保持最前的同时，把内容粘贴到之前的 App。
    @discardableResult
    func pasteKeepingWindowOpen(_ item: ClipboardItem, store: ClipboardStore) -> Bool {
        Paster.pasteInPlace(item, store: store, into: previousApp)
    }

    /// 上一个方法的字符串版本，用于粘贴表情/符号。
    func pasteStringKeepingWindowOpen(_ text: String) {
        Paster.pasteStringInPlace(text, into: previousApp)
    }

    // MARK: - NSWindowDelegate

    /// 不适用于对话框或模态窗口：隐藏会拆除正在运行的命令。
    func windowDidResignKey(_ notification: Notification) {
        guard isVisible, !core.isShowingDialog else { return }
        if core.palette.menuOpen { return }
        // 文件面板会在我们下方设置自己的层级，因此降级而非关闭。
        if NSApp.modalWindow != nil {
            panel?.level = .normal
            return
        }
        core.paletteCoordinator.hidePalette(restoreFocus: false)
    }

    /// 延后一拍再重新触发：首次显示时同步触发会早于 `onChange` 生效。
    func windowDidBecomeKey(_ notification: Notification) {
        panel?.level = .palette
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            core.palette.focusToken = UUID()
            // 重新唤起会让第一响应者留在原处，下面两项都收不到事件。
            panel?.trackComposition()
            if let context = panel?.fieldEditorContext {
                core.inputSourceSwitcher.applySession(to: context)
            }
            if queryWasPreserved {
                queryWasPreserved = false
                panel?.selectAllFieldEditorText()
            }
        }
    }

    /// 拖拽会重新锚定会话，使下次尺寸变化从用户留下的位置展开。
    func windowDidMove(_ notification: Notification) {
        guard !applyingLayoutFrame else { return }
        guard let panel else { return }
        let moved = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
        guard moved != anchor else { return }
        guard drag != nil else { anchor = moved; return }
        let snapped = trackDrag(to: moved)
        anchor = snapped
        if snapped != moved {
            panel.setFrameOrigin(CGPoint(x: snapped.x, y: snapped.y - panel.frame.height))
        }
    }

    // MARK: - Dragging

    /// 拖拽柄上的按压超过判定阈值、成为拖拽时触发；参考线随之移动。
    func beginDrag() {
        guard let panel, let screen = panel.screen ?? targetScreen() else { return }
        let home = defaultAnchor(on: screen)
        let current = CGPoint(x: panel.frame.minX, y: panel.frame.maxY)
        let candidate = PalettePlacement.snapped(
            current, home: home, visibleFrame: screen.visibleFrame,
            expandedHeight: metrics.size.panelHeight,
            within: Theme.Size.paletteSnapDistance, previous: nil, speed: 0)
        // 仅接近不应在首次移动前就锁定快速拖拽。
        let pixel = 1 / screen.backingScaleFactor
        let restingSnap = PalettePlacement.Snap(
            anchor: current,
            centeredX: candidate.centeredX && abs(candidate.anchor.x - current.x) <= pixel,
            height: abs(candidate.anchor.y - current.y) <= pixel ? candidate.height : nil)
        drag = DragSession(
            home: home, screenFrame: screen.frame, visibleFrame: screen.visibleFrame,
            displayKey: screen.displayKey, snap: restingSnap,
            lastRawAnchor: current, lastSampleTime: nil)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    /// 归位档恢复默认位置；其他落点则记住相对显示器的位置。
    func endDrag() {
        let session = drag
        drag = nil
        dropGuides.hide()
        guard let session, session.moved, let anchor else { return }
        if session.snap.centeredX && session.snap.height == .home {
            core.settings.setPalettePosition(nil, on: session.displayKey, expandedCenter: false)
            return
        }
        core.settings.setPalettePosition(
            PalettePlacement.offset(of: anchor, on: session.visibleFrame), on: session.displayKey,
            expandedCenter: session.snap.centeredX && session.snap.height == .expandedCenter)
    }

    /// 实时吸附，高度档位仅在中心线上可用。
    private func trackDrag(to moved: CGPoint) -> CGPoint {
        guard var session = drag else { return moved }
        let now = ProcessInfo.processInfo.systemUptime
        let travel = hypot(moved.x - session.lastRawAnchor.x, moved.y - session.lastRawAnchor.y)
        let elapsed = session.lastSampleTime.map { now - $0 } ?? 1.0 / 60
        let speed = travel / max(elapsed, 0.001)
        session.lastRawAnchor = moved
        session.lastSampleTime = now
        if let screen = panel?.screen, screen.frame != session.screenFrame {
            session.screenFrame = screen.frame
            session.visibleFrame = screen.visibleFrame
            session.displayKey = screen.displayKey
            session.home = defaultAnchor(on: screen)
            session.snap = PalettePlacement.Snap(anchor: moved, centeredX: false, height: nil)
            session.verticalEntryY = nil
        }
        let snap = PalettePlacement.snapped(
            moved, home: session.home, visibleFrame: session.visibleFrame,
            expandedHeight: metrics.size.panelHeight, within: Theme.Size.paletteSnapDistance,
            previous: session.snap, speed: speed)
        let enteredVertical = snap.centeredX && !session.snap.centeredX
        let enteredHome = snap.height == .home && session.snap.height != .home
        if enteredVertical { session.verticalEntryY = moved.y }
        if let verticalEntryY = session.verticalEntryY,
            !snap.centeredX || abs(moved.y - verticalEntryY) > Theme.Size.dropGuideCombinedFlashTolerance
        {
            session.verticalEntryY = nil
        }
        if enteredVertical || (snap.height != nil && snap.height != session.snap.height) {
            NSHapticFeedbackManager.defaultPerformer.perform(
                .alignment, performanceTime: .drawCompleted)
        }
        if session.moved {
            dropGuides.move(
                home: session.home, screenFrame: session.screenFrame, dragged: snap.anchor)
        } else {
            dropGuides.show(
                home: session.home, width: metrics.size.panelWidth,
                screenFrame: session.screenFrame, dragged: snap.anchor)
        }
        if enteredHome {
            dropGuides.flash(session.verticalEntryY == nil ? .horizontal : .both)
            session.verticalEntryY = nil
        } else if enteredVertical {
            dropGuides.flash(.vertical)
        }
        session.snap = snap
        session.moved = true
        drag = session
        return snap.anchor
    }

    // MARK: - Private

    /// 惰性创建面板并接线其键位回调（粘贴、退格、Escape、⌘ 快捷键）。
    private func ensurePanel() -> PalettePanel {
        if let panel { return panel }
        let root = RootPaletteView().paletteEnvironment(core)
        let panel = PalettePanel(rootView: root)
        panel.delegate = self
        panel.paletteState = core.palette
        // 该切换仅作用于面板自身的编辑上下文，绝不全局应用。
        panel.onFieldEditorFocused = { [weak self] context in
            self?.core.inputSourceSwitcher.applySession(to: context)
        }
        // 退格承担 Escape 的后退步骤但绝不关闭：根屏幕会退到启动器。
        panel.onBareBackspace = { [weak self] in
            guard let core = self?.core, core.palette.query.isEmpty else { return false }
            // 表单字段独占该键：它删除的是字段自身的文本，而非查询文本。
            if core.palette.isEditingField { return false }
            if core.palette.mode == .extensionCommand {
                core.extensionCoordinator.exitExtensionScreen()
                return true
            }
            if core.palette.mode == .ai, core.quickAICoordinator.removeLastAttachment() {
                return true
            }
            if core.palette.pop() { return true }
            guard core.palette.mode != .launcher else { return false }
            core.palette.prepare(mode: .launcher)
            return true
        }
        installPasteMonitor()
        // 在面板层处理：获得焦点的预览会先于面板自身的处理器应答 Escape。
        panel.onEscape = { [weak self] in
            guard let self, core.palette.fileSearchQuickLook else { return false }
            core.palette.fileSearchQuickLook = false
            return true
        }
        // 在面板层处理：字段编辑器或缺失的主菜单会先吞掉这些按键。
        panel.onCommandShortcut = { [weak self] event in
            guard let self else { return false }
            if self.core.palette.mode == .emoji, let zoom = Self.emojiGridZoom(from: event) {
                self.core.palette.noteEmojiGridZoom(zoom)
                return true
            }
            guard Self.commandCharacter(from: event) != nil else { return false }
            if self.core.palette.mode == .launcher || self.core.palette.mode == .clipboard,
                let index = FavoriteSlots.index(forKeyCode: event.keyCode)
            {
                self.core.palette.noteFavoriteSlot(index)
                return true
            }
            guard let character = Self.commandCharacter(from: event) else { return false }
            switch character {
            case ",":
                self.core.settingsCoordinator.showSettings()
                return true
            // Pin。在所有屏幕都吞掉它，因为 ⌘. 对搜索框而言只意味着取消。
            case ".":
                self.core.palette.notePinChord()
                return true
            case "w":
                self.core.paletteCoordinator.hidePalette()
                return true
            default:
                return false
            }
        }
        self.panel = panel
        return panel
    }

    /// 调整到给定状态并锚定顶边；即使隐藏时也会应用。
    func applyCollapsed(_ collapsed: Bool) {
        guard let panel else { return }
        positionPanel(panel, collapsed: collapsed)
    }

    /// 新宽度会使缓存锚点所编码的位置失效，因此重新解析。
    func applyInterfaceSize() {
        guard let panel else { return }
        anchor = nil
        positionPanel(panel, collapsed: core.paletteCoordinator.paletteIsCollapsed)
    }

    /// 按高度设定尺寸并相对会话锚点定位，使列表向下增长。
    private func positionPanel(_ panel: NSPanel, collapsed: Bool) {
        // 剪贴板以底部横条呈现：停靠在屏幕底部，不占用常规锚点。
        if core.palette.mode == .clipboard {
            dockClipboardBar(panel)
            return
        }
        guard let anchor = resolveAnchor() else { return }
        let size = metrics.size
        let height = collapsed ? size.compactHeight : size.panelHeight
        let frame = NSRect(
            x: anchor.x, y: anchor.y - height, width: size.panelWidth, height: height)
        panel.setFrame(frame, display: true)
    }

    /// 停靠剪贴板横条：占满目标显示器可见区整宽，底边贴合底缘。
    private func dockClipboardBar(_ panel: NSPanel) {
        guard let screen = targetScreen() else { return }
        let frame = PalettePlacement.bottomBarFrame(
            in: screen.visibleFrame,
            height: metrics.size.clipboardBarHeight)
        applyingLayoutFrame = true
        panel.setFrame(frame, display: true)
        applyingLayoutFrame = false
    }

    /// 用于锚定的显示器；绝不使用 `NSScreen.main`，它会跟随聚焦的窗口。
    private func targetScreen() -> NSScreen? {
        core.settings.openOnCursorScreen ? NSScreen.underCursor : NSScreen.primary
    }

    /// 缓存到隐藏为止，使两处定位读取同一个 `visibleFrame`；拖拽结果优先于设置。
    private func resolveAnchor() -> CGPoint? {
        if let anchor { return anchor }
        let resolved = targetScreen().flatMap { restoredAnchor(on: $0) ?? defaultAnchor(on: $0) }
        anchor = resolved
        return resolved
    }

    /// 该显示器自身的角落位置，除非剩余可抓取区域过小。
    private func restoredAnchor(on screen: NSScreen) -> CGPoint? {
        guard let offset = core.settings.palettePosition(on: screen.displayKey) else { return nil }
        let stored = PalettePlacement.anchor(for: offset, on: screen.visibleFrame)
        let position =
            core.settings.paletteExpandedCenterDisplays.contains(screen.displayKey)
            ? CGPoint(
                x: defaultAnchor(on: screen).x,
                y: PalettePlacement.expandedCenterY(
                    in: screen.visibleFrame, expandedHeight: metrics.size.panelHeight))
            : stored
        return PalettePlacement.restored(
            position,
            graspable: CGSize(width: metrics.size.panelWidth, height: metrics.size.compactHeight),
            visibleFrame: screen.visibleFrame,
            minimumVisible: Theme.Size.paletteMinimumVisible)
    }

    /// 某显示器上未经改动的默认位置；唤起路径与落点参考线共用它。
    private func defaultAnchor(on screen: NSScreen) -> CGPoint {
        PalettePlacement.defaultAnchor(
            in: screen.visibleFrame, width: metrics.size.panelWidth,
            topMarginFraction: Theme.Size.paletteTopMarginFraction)
    }

    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }
}

extension NSScreen {
    /// 重新插拔显示器后仍然稳定；显示器 ID 仅作为会话内的兜底。
    fileprivate var displayKey: String {
        let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        guard let id = number?.uint32Value else { return "primary" }
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
            let string = CFUUIDCreateString(nil, uuid) as String?
        else { return String(id) }
        return string.lowercased()
    }
}
