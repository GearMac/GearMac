// 文件职责：定义 Notes 使用的无边框浮层面板 NSPanel 子类，统一处理快捷键、Escape 与鼠标事件。
// 分层：UI 窗口层；供编辑器与切换器共用的非激活面板基础类。
import AppKit
import Carbon.HIToolbox

/// 编辑器与切换器仅在 style mask 与快捷键上不同，因此共用一个面板。
final class NotesPanel: NSPanel {
    var onEscape: (() -> Void)?
    /// ⌘⌫ 单独用 key code 判定：只有按键码能在所有键盘布局下保持一致。
    var onDeleteChord: (() -> Bool)?
    /// 本窗口声明的 ⌘-字母快捷键，以字符小写为键。
    var commandChords: [String: () -> Void] = [:]
    /// 同上，但用于 ⌥⌘-字母快捷键。
    var optionCommandChords: [String: () -> Void] = [:]
    /// 标题菜单为 false，使下方编辑器保留其插入点、显隐与快捷键。
    var acceptsKey = true
    var onMouseDown: (() -> Void)?

    private let acceptsMain: Bool

    /// 使用内容视图、尺寸、样式掩码与是否可成为主窗口初始化面板。
    init(content: NSView, size: CGSize, styleMask: NSWindow.StyleMask, acceptsMain: Bool) {
        self.acceptsMain = acceptsMain
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: styleMask.union([.fullSizeContentView, .nonactivatingPanel]),
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        isRestorable = false
        contentView = content
    }

    /// 主菜单先获得快捷键处理机会，因此这里是非激活面板的兜底实现。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        guard !event.isARepeat else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if modifiers == [.command, .option] {
            guard let key, let chord = optionCommandChords[key] else { return false }
            chord()
            return true
        }
        guard modifiers == .command else { return false }
        if Int(event.keyCode) == kVK_Delete { return onDeleteChord?() == true }
        guard let key, let chord = commandChords[key] else { return false }
        chord()
        return true
    }

    /// 处理鼠标按下回调，并将未消费的 Escape 转为 `onEscape` 回调。
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown { onMouseDown?() }
        // 搜索与重命名输入框在编辑时自行拥有 Escape。
        guard event.type == .keyDown, Int(event.keyCode) == kVK_Escape, !event.isARepeat,
            (firstResponder as? NSTextView)?.isFieldEditor != true
        else {
            super.sendEvent(event)
            return
        }
        onEscape?()
    }

    /// 系统取消操作（Escape）时触发关闭回调。
    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    /// 是否允许成为 key 窗口，由 `acceptsKey` 决定。
    override var canBecomeKey: Bool { acceptsKey }
    /// 是否允许成为主窗口，由构造时的 `acceptsMain` 决定。
    override var canBecomeMain: Bool { acceptsMain }
}
