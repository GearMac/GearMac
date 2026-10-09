// 文件职责：基于 TextKit 的笔记文本视图，处理键盘快捷键、块级格式编辑、链接与任务框点击以及焦点/外观变化。
// 分层：UI 视图层；`@MainActor` 限定，通过 `editing` 回调将事件交给上层的渲染器与协调器。
import AppKit

/// 笔记编辑器使用的 NSTextView 子类，把编辑操作转换成 `NoteEditPlan` 并处理鼠标交互。
@MainActor
final class NoteTextView: NSTextView, InjectableTextView {
    var editorUndoManager: UndoManager?
    /// 文本为空时绘制的占位提示文字，由外部按当前界面语言注入。
    var placeholder = ""
    weak var editing: NoteTextViewEditing?
    /// 在 `mouseDown` 的拖选循环期间为 true；拖拽中显示标记会导致指针下的文本移动。
    private(set) var isDragSelecting = false

    /// 在此自行跟踪，因为窗口在放弃首响应者时仍会先把它列为 first responder。
    private var isFirstResponder = false
    private var keyObservers: [NotificationToken] = []

    private static let checkboxSlop: CGFloat = 3

    override var undoManager: UndoManager? { editorUndoManager }

    var isFocused: Bool { isFirstResponder && window?.isKeyWindow == true }

    private var rendersMarkdown: Bool { editing?.rendersMarkdown == true }

    /// 执行一次可撤销的替换，且会触发 `textDidChange`，使自动保存与重新样式化都能感知。
    @discardableResult
    func performEdit(_ plan: NoteEditPlan) -> Bool {
        breakUndoCoalescing()
        guard let textStorage, shouldChangeText(in: plan.range, replacementString: plan.replacement)
        else { return false }
        textStorage.replaceCharacters(in: plan.range, with: plan.replacement)
        didChangeText()
        setSelectedRange(plan.selection)
        breakUndoCoalescing()
        return true
    }

    /// 仅当文本未变且选区与给定范围一致时，才用指定文本替换选区。
    func replaceUnchangedSelection(
        with text: String, source: String, range: NSRange
    ) -> Bool {
        guard isEditable, range.length > 0, string == source, selectedRange() == range else {
            return false
        }
        return performEdit(
            NoteEditPlan(
                range: range, replacement: text,
                selection: NSRange(location: range.location + (text as NSString).length, length: 0)))
    }

    /// 格式栏的入口：与对应快捷键走同一套计划、同一道门控与同一个撤销步骤。
    func format(_ action: NoteEditAction) {
        perform(action)
    }

    /// 将查找操作转发给文本查找器。
    func find(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        performTextFinderAction(item)
    }

    /// 视图 frame 永远不会比裁剪视图短，因此只有布局知道文本实际高度。
    func textHeight() -> CGFloat {
        guard let textLayoutManager else { return frame.height }
        var bottom: CGFloat = 0
        textLayoutManager.enumerateTextLayoutFragments(
            from: textLayoutManager.documentRange.endLocation, options: [.reverse, .ensuresLayout]
        ) { fragment in
            bottom = fragment.layoutFragmentFrame.maxY
            return false
        }
        return bottom + textContainerInset.height * 2
    }

    /// 绘制内容；当文本为空时额外绘制占位提示文字。
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard textStorage?.length == 0, !placeholder.isEmpty else { return }
        NSAttributedString(
            string: placeholder,
            attributes: [
                .font: NoteMarkdownTypography.body,
                .foregroundColor: NSColor(Theme.Colors.textTertiary)
            ]
        ).draw(at: textContainerOrigin)
    }

    // MARK: - Keys

    /// 回车：先尝试 Markdown 编辑规则，未处理则回退到默认换行。
    override func insertNewline(_ sender: Any?) {
        guard !perform(.newline) else { return }
        super.insertNewline(sender)
    }

    /// 退格：先尝试 Markdown 编辑规则，未处理则回退到默认删除。
    override func deleteBackward(_ sender: Any?) {
        guard !perform(.deleteBackward) else { return }
        super.deleteBackward(sender)
    }

    /// `[] ` 输入规则；计划会自行写入空格，因此丢弃用户键入的那个空格。
    override func insertText(_ string: Any, replacementRange: NSRange) {
        let caret = selectedRange()
        if string as? String == " ", caret.length == 0,
            replacementRange.location == NSNotFound || replacementRange == caret,
            perform(.typedSpace)
        {
            return
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    /// Tab：先尝试 Markdown 缩进规则，未处理则回退到默认制表。
    override func insertTab(_ sender: Any?) {
        guard !perform(.indent) else { return }
        super.insertTab(sender)
    }

    /// Shift+Tab：先尝试 Markdown 反缩进规则，未处理则回退到默认行为。
    override func insertBacktab(_ sender: Any?) {
        guard !perform(.outdent) else { return }
        super.insertBacktab(sender)
    }

    /// 优先处理本编辑器的撤销/重做与 Markdown 快捷键，未匹配则交给默认实现。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if event.charactersIgnoringModifiers?.lowercased() == "z",
            modifiers == .command || modifiers == [.command, .shift]
        {
            guard !event.isARepeat else { return true }
            breakUndoCoalescing()
            if modifiers == .command {
                editorUndoManager?.undo()
            } else {
                editorUndoManager?.redo()
            }
            return true
        }
        guard rendersMarkdown, let action = Self.chord(for: event) else {
            return super.performKeyEquivalent(with: event)
        }
        if !event.isARepeat { perform(action) }
        return true
    }

    /// 粘贴：优先尝试把选中的 URL 转换为链接。
    override func paste(_ sender: Any?) {
        guard !pasteLink(from: .general) else { return }
        super.paste(sender)
    }

    /// 在选中文本上粘贴单独的 URL 会生成链接；其余内容按纯文本粘贴。
    func pasteLink(from pasteboard: NSPasteboard) -> Bool {
        guard let string = pasteboard.string(forType: .string) else { return false }
        return perform(.pasteURL(string))
    }

    /// 根据当前源文本与选区计算编辑计划并执行；渲染关闭或存在 marked text 时不做处理。
    @discardableResult
    private func perform(_ action: NoteEditAction) -> Bool {
        guard let editing, editing.rendersMarkdown, !hasMarkedText() else { return false }
        let plan = NoteMarkdownEditing.plan(
            action, source: string, selection: selectedRange(), markdown: editing.markdown)
        guard let plan else { return false }
        performEdit(plan)
        return true
    }

    /// 数字键的按键码，在此声明使本地快捷键无需依赖 Carbon。
    private enum DigitKey {
        static let zero: UInt16 = 0x1D
        static let one: UInt16 = 0x12
        static let two: UInt16 = 0x13
        static let three: UInt16 = 0x14
        static let seven: UInt16 = 0x1A
        static let eight: UInt16 = 0x1C
        static let nine: UInt16 = 0x19
    }

    /// 数字使用按键码匹配，因为带 Shift/Option 的数字在不同键盘布局下会产生不同字符。
    private static func chord(for event: NSEvent) -> NoteEditAction? {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased()
        switch modifiers {
        case [.command]:
            switch key {
            case "b": return .toggleInline(.bold)
            case "i": return .toggleInline(.italic)
            case "e": return .toggleInline(.code)
            case "k": return .toggleLink
            default: return nil
            }
        case [.command, .shift]:
            if key == "x" { return .toggleInline(.strikethrough) }
            if key == "b" { return .toggleQuote }
            switch event.keyCode {
            case DigitKey.seven: return .toggleList(.ordered)
            case DigitKey.eight: return .toggleList(.bullet)
            case DigitKey.nine: return .toggleList(.task)
            default: return nil
            }
        case [.command, .option]:
            if key == "c" { return .toggleCodeBlock }
            switch event.keyCode {
            case DigitKey.one: return .setHeading(level: 1)
            case DigitKey.two: return .setHeading(level: 2)
            case DigitKey.three: return .setHeading(level: 3)
            case DigitKey.zero: return .setHeading(level: 0)
            default: return nil
            }
        default:
            return nil
        }
    }

    // MARK: - Mouse

    /// 鼠标按下：优先判定是否点击了任务复选框，否则进入拖选流程。
    override func mouseDown(with event: NSEvent) {
        guard rendersMarkdown else { return super.mouseDown(with: event) }
        guard !toggleTask(atContainerPoint: containerPoint(for: event)) else { return }
        isDragSelecting = true
        super.mouseDown(with: event)
        isDragSelecting = false
        editing?.dragSelectionEnded()
    }

    /// 鼠标移动时，若悬停在任务复选框上则显示普通箭头光标。
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard rendersMarkdown, checkboxLine(atContainerPoint: containerPoint(for: event)) != nil else {
            return
        }
        NSCursor.arrow.set()
    }

    /// 切换绘制出的方框位于该点下的任务项，并保持光标位置不变。
    func toggleTask(atContainerPoint point: CGPoint) -> Bool {
        guard let lineIndex = checkboxLine(atContainerPoint: point) else { return false }
        return perform(.toggleTask(lineIndex: lineIndex))
    }

    /// 返回点击落在链接边缘时对应的源文本偏移；仅当落在字形外恻 30% 范围内才算边缘。
    func linkEdge(ofLinkAt characterIndex: Int, clickedAt point: CGPoint) -> Int? {
        guard let storage = textStorage, characterIndex < storage.length else { return nil }
        var link = NSRange()
        let whole = NSRange(location: 0, length: storage.length)
        guard storage.attribute(.link, at: characterIndex, longestEffectiveRange: &link, in: whole) != nil,
            link.length > 0
        else { return nil }
        let edgeFraction: CGFloat = 0.3
        if let first = glyphFrame(at: link.location), first.minY <= point.y, point.y <= first.maxY,
            point.x <= first.minX + first.width * edgeFraction
        {
            return link.location
        }
        if let last = glyphFrame(at: NSMaxRange(link) - 1), last.minY <= point.y, point.y <= last.maxY,
            point.x >= last.maxX - last.width * edgeFraction
        {
            return NSMaxRange(link)
        }
        return nil
    }

    /// 将窗口坐标的鼠标事件位置转换为容器坐标。
    func containerPoint(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
    }

    /// 返回该点下方任务复选框所在的行索引，无则返回 nil。
    private func checkboxLine(atContainerPoint point: CGPoint) -> Int? {
        guard let editing, let content = textContentStorage,
            let fragment = textLayoutManager?.textLayoutFragment(for: point) as? NoteBlockLayoutFragment,
            case .task(let level, _) = fragment.decoration.shape
        else { return nil }
        let firstLine = fragment.textLineFragments.first?.typographicBounds ?? .zero
        let box = NoteCheckboxGeometry.rect(
            level: level, firstLineHeight: firstLine.height,
            bodyPointSize: fragment.decoration.bodyPointSize
        ).offsetBy(dx: 0, dy: fragment.layoutFragmentFrame.minY + firstLine.minY)
        guard box.insetBy(dx: -Self.checkboxSlop, dy: -Self.checkboxSlop).contains(point) else { return nil }
        let start = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        return editing.markdown.lineIndex(at: start)
    }

    /// 返回指定字符位置的字形边界矩形。
    private func glyphFrame(at characterIndex: Int) -> CGRect? {
        guard let layout = textLayoutManager, let content = textContentStorage,
            let start = content.location(content.documentRange.location, offsetBy: characterIndex),
            let end = content.location(start, offsetBy: 1),
            let range = NSTextRange(location: start, end: end)
        else { return nil }
        var frame: CGRect?
        layout.enumerateTextSegments(in: range, type: .standard, options: []) { _, segment, _, _ in
            frame = segment
            return false
        }
        return frame
    }

    // MARK: - Focus and appearance

    /// 成为首响应者时更新焦点状态。
    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        isFirstResponder = true
        editing?.focusChanged()
        return true
    }

    /// 放弃首响应者时更新焦点状态。
    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        isFirstResponder = false
        editing?.focusChanged()
        return true
    }

    /// 面板在其他应用活跃时仍保有首响应者，因此窗口的 key 状态也属于焦点判断的一部分。
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        keyObservers = []
        guard let window else { return }
        let center = NotificationCenter.default
        keyObservers = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification].map { name in
            let token = center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.editing?.focusChanged() }
            }
            return NotificationToken(token, center: center)
        }
    }

    /// 外观（如暗/亮模式）变化时通知编辑器重新样式化。
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        editing?.appearanceChanged()
    }
}
