// 文件职责：维护笔记文本的 Markdown 解析与「标记显隐」状态，仅对发生变化的部分重新应用样式。
// 分层：UI 渲染层；`@MainActor` 限定，属性写入不进入撤销栈且不修改文本内容。
import AppKit

/// 使笔记的解析结果与显隐状态同其文本视图保持同步，只对真正变化的部分重新样式化。
@MainActor
final class NoteMarkdownRenderer: NSObject, @MainActor NSTextStorageDelegate {
    /// 当前源文本的解析结果。
    private(set) var markdown = NoteMarkdown.empty
    /// 当前处于「已显示标记」状态的行索引集合。
    private(set) var revealed = IndexSet()
    /// Render Markdown 设置；切换后在下一次 `reset()` 时生效。
    var isEnabled: Bool
    /// 绑定的文本视图；设置时自动成为其 textStorage 的 delegate。
    weak var textView: NoteTextView? {
        didSet { textView?.textStorage?.delegate = self }
    }

    /// 尚未解析的编辑：它在 `markdown` 中覆盖的范围与当前覆盖的范围。
    private var pendingEdit: (old: NSRange, new: NSRange)?
    private var isStyling = false

    /// 使用 Markdown 渲染开关初始化。
    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
        super.init()
    }

    /// 完整解析并重新样式化，用于安装输入、切换设置或外观变化之后。
    func reset() {
        guard let textView, let storage = textView.textStorage else { return }
        NoteMarkdownStyler.invalidateColors()
        pendingEdit = nil
        guard isEnabled else {
            markdown = .empty
            revealed = []
            restyle(NSRange(location: 0, length: storage.length)) {
                storage.setAttributes(NoteMarkdownStyler.literal, range: $0)
            }
            textView.typingAttributes = NoteMarkdownStyler.literal
            return
        }
        markdown = NoteMarkdownParser.parse(units: Self.units(of: storage))
        revealed = nextRevealed()
        apply(IndexSet(integersIn: markdown.lines.indices))
        textView.typingAttributes = NoteMarkdownStyler.literal
    }

    /// 无论编辑以何种方式到达都先接收之，再根据选区重新隐藏与显示对应行。
    func sourceDidChange() {
        syncSource()
        selectionDidChange()
    }

    /// 选区变化时重新计算显隐行，并只对变化的行应用样式。
    func selectionDidChange() {
        guard isEnabled, !isStyling, let textView else { return }
        syncSource()
        guard !textView.isDragSelecting else { return }
        let next = nextRevealed()
        let changed = revealed.symmetricDifference(next)
        revealed = next
        if !changed.isEmpty { apply(changed) }
        textView.typingAttributes = NoteMarkdownStyler.literal
    }

    /// 返回源文本当前的解析结果，供不得基于陈旧解析执行的编辑计划使用。
    func syncedMarkdown() -> NoteMarkdown {
        syncSource()
        return markdown
    }

    // MARK: - Edits

    /// 撤销与 marked text 会绕过 `textDidChange` 直接改动存储，因此每个回调都在此处校验。
    private func syncSource() {
        guard isEnabled, !isStyling, let edit = pendingEdit, let storage = textView?.textStorage
        else { return }
        pendingEdit = nil
        let old = markdown
        markdown = NoteMarkdownParser.parse(units: Self.units(of: storage))

        let oldLines = old.lineIndexes(intersecting: edit.old)
        let newLines = markdown.lineIndexes(intersecting: edit.new)
        revealed = NoteRevealPolicy.shifted(revealed, editedOldLines: oldLines, editedNewLines: newLines)
        apply(restyleScope(old: old, oldLines: oldLines, newLines: newLines))
    }

    /// 返回编辑行及其前后各一行，并扩展到后续那些类型或层级发生变化的行。
    private func restyleScope(old: NoteMarkdown, oldLines: Range<Int>, newLines: Range<Int>) -> IndexSet {
        let lines = markdown.lines
        guard !lines.isEmpty else { return [] }
        let lower = max(0, newLines.lowerBound - 1)
        let upper = min(lines.count, max(newLines.upperBound, newLines.lowerBound + 1) + 1)
        var scope = IndexSet(integersIn: lower..<upper)
        let delta = newLines.count - oldLines.count

        let shiftedBlocks = old.fenceBlocks.map { block -> ClosedRange<Int> in
            guard block.lowerBound >= oldLines.upperBound else { return block }
            return (block.lowerBound + delta)...(block.upperBound + delta)
        }
        if shiftedBlocks != markdown.fenceBlocks {
            scope.insert(integersIn: lower..<lines.count)
            return scope
        }

        var index = upper
        while index < lines.count {
            let oldIndex = index - delta
            let unchanged =
                old.lines.indices.contains(oldIndex) && old.lines[oldIndex].kind == lines[index].kind
                && old.lines[oldIndex].level == lines[index].level
            if !unchanged {
                scope.insert(index)
            } else if !(lines[index].kind.isList || lines[index].kind == .blank) {
                break
            }
            index += 1
        }
        return scope
    }

    /// 存储的每次变更都会回调到这里（包括撤销与 marked text）；样式化本身则不会。
    func textStorage(
        _ textStorage: NSTextStorage, didProcessEditing edited: NSTextStorageEditActions,
        range: NSRange, changeInLength delta: Int
    ) {
        guard edited.contains(.editedCharacters) else { return }
        let before = NSRange(location: range.location, length: range.length - delta)
        guard let pending = pendingEdit else {
            pendingEdit = (old: before, new: range)
            return
        }
        let lower = min(pending.old.location, before.location)
        let upper = max(NSMaxRange(pending.new), NSMaxRange(before))
        let shift = pending.new.length - pending.old.length
        pendingEdit = (old: NSRange(lower..<(upper - shift)), new: NSRange(lower..<(upper + delta)))
    }

    /// 将 `NSTextStorage` 的内容以 UTF-16 码元数组形式取出。
    private static func units(of storage: NSTextStorage) -> [UInt16] {
        let string = storage.mutableString
        return [UInt16](unsafeUninitializedCapacity: string.length) { buffer, count in
            if let base = buffer.baseAddress {
                string.getCharacters(base, range: NSRange(location: 0, length: string.length))
            }
            count = string.length
        }
    }

    // MARK: - Styling

    /// 根据当前选区与焦点状态计算应显示标记的行集合。
    private func nextRevealed() -> IndexSet {
        guard let textView else { return [] }
        return NoteRevealPolicy.revealedLines(
            selection: textView.selectedRange(), markdown: markdown, isFocused: textView.isFocused)
    }

    /// 对指定行集合逐行计算并写入样式。
    private func apply(_ indexes: IndexSet) {
        guard let textView, let text = textView.textStorage?.mutableString else { return }
        for range in indexes.rangeView where range.lowerBound < markdown.lines.count {
            let lines = range.clamped(to: markdown.lines.indices)
            let span = NSUnionRange(
                markdown.lines[lines.lowerBound].range, markdown.lines[lines.upperBound - 1].range)
            restyle(span) { _ in
                for index in lines {
                    let style = NoteMarkdownStyler.style(
                        at: index, in: markdown, text: text, isRevealed: revealed.contains(index))
                    textView.textStorage?.setAttributes(style.base, range: markdown.lines[index].range)
                    for run in style.runs {
                        textView.textStorage?.addAttributes(run.attributes, range: run.range)
                    }
                }
            }
        }
    }

    /// 属性写入会跳过 `shouldChangeText`，这正是样式化不会进入撤销栈的原因。
    private func restyle(_ range: NSRange, _ write: (NSRange) -> Void) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        guard range.length > 0 else { return }
        isStyling = true
        textView.effectiveAppearance.performAsCurrentDrawingAppearance {
            storage.beginEditing()
            write(range)
            storage.endEditing()
        }
        isStyling = false
        invalidateLayout(range)
    }

    /// 若不调用此方法，段落会继续保留其装饰变化之前被提供的片段。
    private func invalidateLayout(_ range: NSRange) {
        guard let textView, let content = textView.textContentStorage,
            let start = content.location(content.documentRange.location, offsetBy: range.location),
            let end = content.location(start, offsetBy: range.length),
            let textRange = NSTextRange(location: start, end: end)
        else { return }
        textView.textLayoutManager?.invalidateLayout(for: textRange)
    }
}
