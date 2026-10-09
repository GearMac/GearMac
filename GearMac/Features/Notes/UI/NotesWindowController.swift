// 文件职责：管理笔记主窗口（面板）的创建、显示隐藏、焦点恢复、尺寸自适应与标题栏红绿灯位置。
// 分层：UI 窗口层；`@MainActor` 限定，负责与 AppKit 窗口系统的交互。
import AppKit
import SwiftUI

/// 笔记主面板的窗口控制器。
@MainActor
final class NotesWindowController: NSObject, NSWindowDelegate {
    private static let frameAutosaveName = "Notes Window"

    private unowned let coordinator: NotesCoordinator
    private var panel: NotesPanel?
    private weak var editor: NoteTextView?
    private var editorObservers: [NotificationToken] = []
    private var fitTask: Task<Void, Never>?
    private var previousApp: NSRunningApplication?
    private weak var previousOwnWindow: NSWindow?

    /// 绑定所属的 NotesCoordinator。
    init(coordinator: NotesCoordinator) {
        self.coordinator = coordinator
    }

    /// 面板当前是否可见。
    var isVisible: Bool { panel?.isVisible ?? false }

    /// 显示面板（必要时先记录焦点目标），并调度尺寸自适应与红绿灯位置修正。
    func show(focusEditor: Bool) {
        let panel = ensurePanel()
        if !panel.isVisible { captureFocusTarget() }
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        scheduleFit()
        seatTrafficLights(in: panel)
        // 在 SwiftUI 中圆角被裁剪，因此阴影必须重新根据已绘制内容生成。
        panel.invalidateShadow()
        if focusEditor { self.focusEditor(in: panel) }
    }

    /// 隐藏面板，可选择恢复焦点到先前窗口或应用。
    func hide(restoreFocus: Bool) {
        let restore = restoreFocus && !userMovedOn
        panel?.orderOut(nil)
        guard restore else { return }
        if let previousOwnWindow, previousOwnWindow.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            previousOwnWindow.makeKeyAndOrderFront(nil)
        } else {
            previousApp?.activate()
        }
    }

    /// 文本视图就绪时记录引用、开始监听布局并调度尺寸自适应。
    func editorReady(_ textView: NoteTextView) {
        editor = textView
        observeLayout(of: textView)
        scheduleFit()
        guard let panel, panel.isVisible else { return }
        focusEditor(in: panel)
    }

    /// 将输入焦点移回编辑器。
    func focusEditor() {
        guard let panel, panel.isVisible else { return }
        focusEditor(in: panel)
    }

    /// 带动画地将窗口移动到屏幕右上角。
    func moveToTopRight() {
        guard let panel, let visible = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        let inset: CGFloat = 40
        let destination = NoteWindowPlacement.topRight(panel.frame, in: visible, inset: inset)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.Duration.enter
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(destination, display: false)
        }
    }

    /// 格式栏按钮从不获取焦点，但编辑器仍会被重新设为响应者以防其他控件抢走它。
    func format(_ action: NoteEditAction) {
        guard let panel, panel.isVisible, let editor else { return }
        if panel.firstResponder !== editor { panel.makeFirstResponder(editor) }
        editor.format(action)
    }

    /// 在面板上方展示标题菜单。
    func presentHeadingMenu(_ menu: NoteHeadingMenuWindowController) {
        guard let panel, panel.isVisible else { return }
        menu.show(above: panel)
    }

    /// 只有本控制器知道宿主窗口，因此把它交给切换器仍是本控制器的职责。
    func presentSwitcher(_ switcher: NoteSwitcherWindowController) {
        guard let panel, panel.isVisible else { return }
        switcher.show(under: panel)
    }

    // MARK: - NSWindowDelegate

    /// 红色关闭按钮与 ⌘W 都汇入此处，使关闭只有一条路径且永不销毁状态。
    func windowWillClose(_ notification: Notification) {
        coordinator.hide()
    }

    /// 窗口失去 key 状态时关闭标题菜单。
    func windowDidResignKey(_ notification: Notification) {
        coordinator.closeHeadingMenu()
    }

    /// 仅设 `contentMinSize` 仍会泄漏小于该值的 frame；AppKit 会原样采纳本方法返回值。
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        NSSize(
            width: max(frameSize.width, Theme.Size.noteWindow.width),
            height: max(frameSize.height, Theme.Size.noteWindow.height))
    }

    /// 窗口尺寸变化后重新落位红绿灯按钮。
    func windowDidResize(_ notification: Notification) {
        guard let panel else { return }
        seatTrafficLights(in: panel)
    }

    /// 窗口更新后重新落位红绿灯按钮。
    func windowDidUpdate(_ notification: Notification) {
        guard let panel else { return }
        seatTrafficLights(in: panel)
    }

    // MARK: - Private

    /// 输入需要在 frame 绘制前完成适配，否则光标会先滚动、文本随后弹回。
    private func observeLayout(of textView: NoteTextView) {
        guard let storage = textView.textStorage, let clipView = textView.enclosingScrollView?.contentView
        else { return }
        editorObservers = [
            observe(NSText.didChangeNotification, from: textView) { $0.fitToEditor() },
            observe(NSTextStorage.didProcessEditingNotification, from: storage) { $0.scheduleFit() },
            observe(NSView.frameDidChangeNotification, from: clipView) { $0.scheduleFit() }
        ]
    }

    /// 订阅指定对象的通知，并把回调包装为在主线程执行的闭包。
    private func observe(
        _ name: Notification.Name, from object: AnyObject,
        perform: @escaping @MainActor (NotesWindowController) -> Void
    ) -> NotificationToken {
        let center = NotificationCenter.default
        return NotificationToken(
            center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    perform(self)
                }
            },
            center: center)
    }

    /// 撤销、切换笔记与格式栏都会在编辑过程中改变布局，因此等编辑完成后再适配。
    private func scheduleFit() {
        guard fitTask == nil else { return }
        fitTask = Task { [weak self] in
            guard let self else { return }
            fitTask = nil
            fitToEditor()
        }
    }

    /// 根据编辑器文本高度调整窗口高度（在允许区间与屏幕可见范围内）。
    private func fitToEditor() {
        guard let panel, panel.isVisible, !panel.inLiveResize,
            let editor, let clipView = editor.enclosingScrollView?.contentView,
            let visibleFrame = (panel.screen ?? NSScreen.main)?.visibleFrame
        else { return }
        let frame = NoteWindowPlacement.fitting(
            panel.frame,
            toHeight: panel.frame.height - clipView.bounds.height + editor.textHeight(),
            within: Theme.Size.noteWindow.height...Theme.Size.noteWindowMaxHeight,
            in: visibleFrame)
        guard frame != panel.frame else { return }
        panel.setFrame(frame, display: true)
    }

    /// 若面板尚未创建则惰性创建，并配置快捷键、自动保存与红绿灯监听。
    private func ensurePanel() -> NotesPanel {
        if let panel { return panel }
        let root = NotesView().environment(coordinator).environment(coordinator.settings)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        let panel = NotesPanel(
            content: hosting,
            size: Theme.Size.noteWindow,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            acceptsMain: true)
        // 标题栏附属视图会使 AppKit 退出居中标题布局，因此改由 `NotesView` 自行绘制。
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        // `.automatic` 会在编辑器滚动到栏下方时立即画出一条发丝线。
        panel.titlebarSeparatorStyle = .none
        panel.contentMinSize = Theme.Size.noteWindow
        panel.delegate = self
        panel.onEscape = { [weak self, weak coordinator] in
            if self?.editor?.enclosingScrollView?.isFindBarVisible == true {
                self?.editor?.find(.hideFindInterface)
            } else {
                coordinator?.handleEscape()
            }
        }
        panel.onMouseDown = { [weak coordinator] in coordinator?.noteWindowMouseDown() }
        panel.onDeleteChord = { [weak coordinator] in coordinator?.handleDeleteShortcut() ?? false }
        panel.commandChords = [
            "n": { [weak coordinator] in coordinator?.createNote() },
            "p": { [weak coordinator] in coordinator?.searchNotes() },
            "o": { [weak coordinator] in coordinator?.openNotesFolder() },
            "f": { [weak self] in self?.editor?.find(.showFindInterface) },
            "w": { [weak panel] in panel?.performClose(nil) }
        ]
        panel.optionCommandChords = [
            "t": { [weak coordinator] in coordinator?.toggleFormattingBar() }
        ]
        panel.setFrameAutosaveName(Self.frameAutosaveName)
        if !panel.setFrameUsingName(Self.frameAutosaveName) { panel.center() }
        // 自动保存的 frame 可能位于下限之下，因此在恢复时进行钳制。
        panel.setContentSize(
            CGSize(
                width: max(panel.frame.width, Theme.Size.noteWindow.width),
                height: max(panel.frame.height, Theme.Size.noteWindow.height)))
        if let close = panel.standardWindowButton(.closeButton) {
            close.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(trafficLightFrameDidChange),
                name: NSView.frameDidChangeNotification, object: close)
        }
        self.panel = panel
        observeTitle()
        return panel
    }

    /// 幂等：因为 AppKit 会在缩放时和每次设置标题时重新落位红绿灯按钮。
    private func seatTrafficLights(in window: NSWindow) {
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap(window.standardWindowButton)
        guard let leading = buttons.first, let band = leading.superview?.bounds.height else {
            return
        }
        // 对齐到绘制出的标题栏带高（而非 AppKit 更短的那个），并做钳制以免被裁剪。
        let size = leading.frame.height
        let y = max(0, band - size - (Theme.Size.noteTitlebar - size) / 2)
        let shift = Theme.Size.noteTrafficLightInset - leading.frame.minX
        guard shift != 0 || leading.frame.origin.y != y else { return }
        for button in buttons {
            button.frame.origin.x += shift
            button.frame.origin.y = y
        }
    }

    @objc private func trafficLightFrameDidChange(_ notification: Notification) {
        // AppKit 可能在发出 frame 变化通知之后才完成红绿灯按钮的布局。
        Task { @MainActor [weak self] in
            guard let self, let panel else { return }
            seatTrafficLights(in: panel)
        }
    }

    /// 每次读取后重新挂接，使重命名不需等到下次显示就能作用到标题。
    private func observeTitle() {
        withObservationTracking {
            panel?.title =
                coordinator.hasActiveNote
                ? coordinator.activeTitle
                : coordinator.settings.text(NotesKey.windowTitle)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeTitle()
                if let panel = self.panel { self.seatTrafficLights(in: panel) }
            }
        }
    }

    /// 用户是否已切换到其他应用（用于判断是否需要恢复焦点）。
    private var userMovedOn: Bool {
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return frontmost != NSRunningApplication.current.processIdentifier
            && frontmost != previousApp?.processIdentifier
    }

    /// 记录显示前的焦点目标（先前应用或本应用的其他窗口），供隐藏时恢复。
    private func captureFocusTarget() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier == NSRunningApplication.current.processIdentifier {
            previousApp = nil
            if let keyWindow = NSApp.keyWindow, keyWindow !== panel {
                previousOwnWindow = keyWindow
            }
        } else {
            previousApp = frontmost
            previousOwnWindow = nil
        }
    }

    /// 将指定面板的首响应者设为编辑器（延后一拍以确保面板已激活）。
    private func focusEditor(in panel: NotesPanel) {
        guard let editor else { return }
        panel.makeFirstResponder(editor)
        Task { @MainActor [weak panel, weak editor] in
            await Task.yield()
            guard let panel, panel.isVisible, let editor else { return }
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(editor)
        }
    }
}
