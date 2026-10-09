// 文件职责：InjectableTextView 的进程内注入实现——把注入文本直接写入 GearMac 自家的 NSTextView。
// 分层：Service（TextInjection）；该层无需辅助功能授权、剪贴板或键盘事件投递，是投递优先级最高的一层。
import AppKit

/// 进程内投递层：写入自家视图无需授权、剪贴板或事件投递。
extension InjectableTextView {
    /// 判断正在输入的关键词落在何处——在 AppKit 把按键交给我们之前返回 `.pending`。
    func keywordReplacementState(
        expectedKeyword: String?, keywordLength: Int
    ) -> TextReplacementPolicy.KeywordState {
        let selection = selectedRange()
        guard keywordLength > 0 else { return .matched(selection) }
        guard let expectedKeyword, expectedKeyword.count == keywordLength else { return .rejected }
        return TextReplacementPolicy.keywordState(
            value: string, selectedRange: selection, keyword: expectedKeyword)
    }

    /// 替换 `range` 并把光标留在文本指定的位置，撤销由视图自身的撤销管理器负责。
    @MainActor
    func inject(_ injected: InjectedText, over range: NSRange) {
        // 参数提示会在展开过程中以模态方式运行，因此写入前先把光标焦点收回。
        if let window, window.firstResponder !== self { window.makeFirstResponder(self) }
        insertText(injected.text, replacementRange: range)
        setSelectedRange(NSRange(location: range.location + injected.caretPrefixLength, length: 0))
        scrollRangeToVisible(selectedRange())
    }
}
