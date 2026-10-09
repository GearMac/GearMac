// 文件职责：作为 NSTextLayoutManagerDelegate，为带有块级装饰属性的段落返回自定义绘制片段。
// 分层：UI 支持层；不持有编辑器状态，仅根据段落属性选择片段类型。
import AppKit

/// 为每个首字符带块级装饰属性的段落提供绘制片段。
final class NoteLayoutFragmentProvider: NSObject, NSTextLayoutManagerDelegate {
    /// 若段落首字符带块级装饰则返回 `NoteBlockLayoutFragment`，否则使用默认片段。
    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        let paragraph = (textElement as? NSTextParagraph)?.attributedString
        guard let paragraph, paragraph.length > 0,
            let decoration = paragraph.attribute(.noteBlockDecoration, at: 0, effectiveRange: nil)
                as? NoteBlockDecoration
        else {
            return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }
        return NoteBlockLayoutFragment(
            textElement: textElement, range: textElement.elementRange, decoration: decoration)
    }
}
