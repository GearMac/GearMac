// 文件职责：调色板的主浮窗（NSPanel），托管 SwiftUI 树并在 sendEvent 中拦截键盘/鼠标事件、统一光标与输入法行为。
// 分层：UI/Service（AppKit + SwiftUI）；无边框、不激活面板，键盘与光标策略集中在此。
import AppKit
import Carbon.HIToolbox
import SwiftUI

/// 承载 SwiftUI 命令调色板的无边框浮窗。
final class PalettePanel: NSPanel {
    /// 头部字段的边界方向，用于行内参数字段的焦点环延续。
    enum HeaderFieldBoundary {
        case leading
        case trailing
    }

    /// 裸退格：字段编辑器会在 `onKeyPress` 看到它之前就吞掉。
    var onBareBackspace: (() -> Bool)?
    /// Escape：预览中的 `AVPlayerView` 会在 `onKeyPress` 看到它之前先回应。
    var onEscape: (() -> Bool)?
    /// 被字段编辑器吞掉的命令组合键，以及主菜单未处理的那些。
    var onCommandShortcut: ((NSEvent) -> Bool)?
    /// 调色板的输入上下文，在每次字段获得焦点时移交。
    var onFieldEditorFocused: ((NSTextInputContext) -> Void)?
    /// 行内参数字段在文本边界处用方向键继续其焦点环。
    var onHeaderFieldBoundaryArrow: ((HeaderFieldBoundary) -> Bool)?
    /// 从 `sendEvent` 武装悬停，这是两条事件流共同经过的唯一位置。
    weak var paletteState: PaletteState? {
        didSet {
            paletteState?.onMenuOpenChanged = { [weak self] open in self?.setSearchCaretHidden(open) }
        }
    }

    /// 字段取得焦点前为 nil；非激活面板只能将输入限定到这里。
    var fieldEditorContext: NSTextInputContext? { fieldEditor?.inputContext }

    /// SwiftUI 的所有文本框都通过窗口共享的这一个字段编辑器编辑。
    private var fieldEditor: NSTextView? { firstResponder as? NSTextView }

    /// 全选字段编辑器中的文本。
    func selectAllFieldEditorText() {
        fieldEditor?.selectAll(nil)
    }

    /// 将字段编辑器的光标移到文本末尾。
    func moveFieldEditorCaretToEnd() {
        fieldEditor?.moveToEndOfDocument(nil)
    }

    /// 当选择仍可正常折叠，或光标不在边界时为 nil。
    private func headerFieldBoundary(for event: NSEvent) -> HeaderFieldBoundary? {
        guard event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]),
            let editor = fieldEditor, editor.selectedRange().length == 0
        else { return nil }
        switch Int(event.keyCode) {
        case kVK_LeftArrow where editor.selectedRange().location == 0: return .leading
        case kVK_RightArrow where editor.selectedRange().location == (editor.string as NSString).length:
            return .trailing
        default: return nil
        }
    }

    /// 镜像字段编辑器的标记文本（marked text）。docs/features/palette.md#ime-composition
    private var compositionObserver: NotificationToken?

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        // 播放控件的按钮也是普通 first responder，但搜索框优先级更高。
        if let view = responder as? NSView, view.refusesKeyboardFocus { return false }
        guard super.makeFirstResponder(responder) else { return false }
        fieldEditor?.insertionPointColor = Self.caretColor
        trackComposition()
        if let context = fieldEditorContext { onFieldEditorFocused?(context) }
        return true
    }

    /// 选择变化是标记文本变更的唯一通知；`didChange` 要等提交后才发。
    func trackComposition() {
        guard let editor = fieldEditor else {
            compositionObserver = nil
            paletteState?.isComposing = false
            return
        }
        paletteState?.isComposing = editor.hasMarkedText()
        let center = NotificationCenter.default
        let token = center.addObserver(
            forName: NSTextView.didChangeSelectionNotification, object: editor, queue: .main
        ) { [weak self, weak editor] _ in
            MainActor.assumeIsolated {
                self?.paletteState?.isComposing = editor?.hasMarkedText() ?? false
            }
        }
        compositionObserver = NotificationToken(token, center: center)
    }

    /// 驱动已打开菜单的按键；即使编辑被冻结，它们也能到达 `onKeyPress`。
    private static let menuNavKeys: Set<Int> = [
        kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow, kVK_RightArrow,
        kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape, kVK_Tab
    ]

    /// 将 ⌃N/⌃P/⌃F/⌃B 改写为对应的方向键，使方向键处理器同时服务于两种写法。
    private static func emacsArrow(for event: NSEvent) -> NSEvent? {
        guard event.modifierFlags.intersection([.command, .option, .control, .shift]) == .control
        else { return nil }
        let arrow: (key: KeyEquivalent, code: Int)
        // 走 ASCII 键盘布局：输入法不得把 ⌃N 从它的物理键上移走。
        switch ASCIIKeyboardLayout.character(for: event)?.lowercased()
            ?? event.charactersIgnoringModifiers?.lowercased()
        {
        case "n": arrow = (.downArrow, kVK_DownArrow)
        case "p": arrow = (.upArrow, kVK_UpArrow)
        case "f": arrow = (.rightArrow, kVK_RightArrow)
        case "b": arrow = (.leftArrow, kVK_LeftArrow)
        default: return nil
        }
        let characters = String(arrow.key.character)
        return NSEvent.keyEvent(
            with: .keyDown,
            location: event.locationInWindow,
            modifierFlags: [.function, .numericPad],
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: event.isARepeat,
            keyCode: UInt16(arrow.code))
    }

    private static let caretColor = NSColor(Theme.Colors.textPrimary)

    /// 在 SwiftUI 自己的字段编辑器上隐藏光标。docs/features/palette.md#menu-open-input-freeze
    private func setSearchCaretHidden(_ hidden: Bool) {
        guard let editor = fieldEditor else { return }
        editor.insertionPointColor = hidden ? .clear : Self.caretColor
        // 强制重绘，使光标立即翻转，而不必等闪烁计时器结束。
        editor.updateInsertionPointStateAndRestartTimer(!hidden)
    }

    /// 两种机制都会为其设置光标的事件，使任何一方都无法独占决定权。
    private static let cursorEvents: Set<NSEvent.EventType> = [
        .mouseMoved, .mouseEntered, .mouseExited, .cursorUpdate,
        .leftMouseDown, .leftMouseUp, .leftMouseDragged
    ]

    /// 裁剪视图与字段编辑器都会认领光标，因此面板在 `super` 之后统一裁定。
    private func applyCursorPolicy(for event: NSEvent) {
        guard Self.cursorEvents.contains(event.type) else { return }
        // 向外扩：AppKit 安装的字段编辑器比它服务的字段高出一个点。
        let text = searchFieldRect.insetBy(dx: -Self.fieldEditorSlack, dy: -Self.fieldEditorSlack)
        let cursor: NSCursor =
            text.contains(convertPoint(fromScreen: NSEvent.mouseLocation)) ? .iBeam : .arrow
        guard NSCursor.current !== cursor else { return }
        cursor.set()
    }

    /// docs/features/palette.md：24pt 编辑器装在 23pt 字段里，因此其 I-beam 会外溢。
    private static let fieldEditorSlack: CGFloat = 2

    /// SwiftUI 报告的字段左上角向下为正向；AppKit 读窗口左下角向上为正向。
    private var searchFieldRect: CGRect {
        guard let frame = paletteState?.searchFieldFrame, !frame.isEmpty,
            let height = contentView?.bounds.height
        else { return .zero }
        return CGRect(
            x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved: paletteState?.notePointerMoved(to: NSEvent.mouseLocation)
        // 按键与滚动都会让行从指针下滑过，而指针并未选择其中任何一行。
        case .keyDown, .scrollWheel:
            paletteState?.disarmHoverHighlight(pointerAt: NSEvent.mouseLocation)
        case .flagsChanged:
            paletteState?.noteCommandHeld(event.modifierFlags.contains(.command))
        default: break
        }
        defer { applyCursorPolicy(for: event) }
        // 先于所有其它规则，使方向键自身的策略也适用于这些组合键。
        if event.type == .keyDown, let arrow = Self.emacsArrow(for: event) {
            sendEvent(arrow)
            return
        }
        // 调色板菜单拥有键盘。参见 docs/features/palette.md#menu-open-input-freeze。
        if event.type == .keyDown,
            paletteState?.menuOpen == true,
            event.modifierFlags.isDisjoint(with: [.command, .control]),
            !Self.menuNavKeys.contains(Int(event.keyCode))
        {
            return
        }
        if event.type == .keyDown,
            Int(event.keyCode) == kVK_Escape,
            event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]),
            onEscape?() == true
        {
            return
        }
        if event.type == .keyDown,
            Int(event.keyCode) == kVK_Delete,
            event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]),
            fieldEditor?.hasMarkedText() != true,
            onBareBackspace?() == true
        {
            return
        }
        if event.type == .keyDown, let boundary = headerFieldBoundary(for: event),
            onHeaderFieldBoundaryArrow?(boundary) == true
        {
            return
        }
        // 控制器拥有那些字段编辑器或缺失的主菜单会吞掉的组合键。
        if event.type == .keyDown,
            event.modifierFlags.contains(.command),
            onCommandShortcut?(event) == true
        {
            return
        }
        super.sendEvent(event)
    }
    /// 以给定 SwiftUI 根视图初始化面板，并配置为无边框、全尺寸内容的浮窗。
    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(
                x: 0, y: 0, width: Theme.Size.panelWidth, height: Theme.Size.panelHeight),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        acceptsMouseMovedEvents = true
        level = .palette
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: rootView)
        hosting.wantsLayer = true
        // 帧由控制器拥有；不设此选项，顶边会在切换时漂移。
        hosting.sizingOptions = []
        contentView = hosting
    }

    /// 失去键盘是面板获得的最后一次修饰键消息；重新显示时可能跳过 `prepare`。
    override func resignKey() {
        super.resignKey()
        paletteState?.noteCommandHeld(false)
    }

    override var canBecomeKey: Bool { true }
    // 菜单作为 key 时父级仍保持 main，以使其 Liquid Glass 保持活跃。
    override var canBecomeMain: Bool { true }
}
