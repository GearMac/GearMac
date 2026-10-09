// 文件职责：读取插入点前后的文本，构造文本格式化所需的上下文。
// 分层：Service/@MainActor；内置输入框走 NSTextView，外部应用走 Accessibility。
import AppKit
@preconcurrency import ApplicationServices

/// 从输入框或外部应用的可访问元素读取光标处上下文的工具。
@MainActor
enum DictationInsertionContext {
    /// 读取目标插入点的上下文；无法获取时返回 nil。
    static func read(in target: InjectionTarget?) -> DictationTextFormatter.Context? {
        if let editor = target?.ownEditor {
            return context(editor.string, range: editor.selectedRange())
        }
        guard let app = target?.externalApp else { return nil }
        guard let element = AccessibilityText.focusedElement(in: app) else { return nil }
        var value: CFTypeRef?
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
            let text = value as? String,
            AXUIElementCopyAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, &selected) == .success,
            let selected, CFGetTypeID(selected) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(unsafeDowncast(selected, to: AXValue.self), .cfRange, &range)
        else { return nil }
        return context(text, range: NSRange(location: range.location, length: range.length))
    }

    /// 由整段文本与选中范围截取光标前后片段构造 Context。
    private static func context(_ text: String, range: NSRange) -> DictationTextFormatter.Context? {
        guard let selected = Range(range, in: text) else { return nil }
        return .init(
            before: text[..<selected.lowerBound],
            after: text[selected.upperBound...])
    }
}
