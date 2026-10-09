// 文件职责：用固定宽度字体在 NSTextView 中展示文本预览，模拟 QuickLook 的文本预览样式。
// 分层：UI；NSViewRepresentable 包装 NSScrollView 与 NSTextView。
import AppKit
import SwiftUI

/// QuickLook 会显示为图标的文本，按其自身文本预览设置 `.swift` 的方式来排版。
struct PlainTextSurface: NSViewRepresentable {
    let text: String

    /// 实测得到的 QuickLook 文本预览样式：11pt 固定宽度字体，四周 3pt 内边距。
    private static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.userFixedPitchFont(ofSize: 11)
            ?? .monospacedSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor.textColor
    ]
    private static let inset = NSSize(width: 3, height: 3)

    /// 记录上次设置的文本，使重渲染比较 Swift 字符串而不是桥接视图内的内容。
    final class Coordinator {
        var shown: String?
    }

    /// 创建协调器。
    func makeCoordinator() -> Coordinator { Coordinator() }

    /// 构建不可编辑、不可选中的文本视图。
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        // 与 QuickLook 一致地设为不可选中：可选中的视图会抢走搜索框的光标。
        textView.isEditable = false
        textView.isSelectable = false
        textView.textContainerInset = Self.inset
        return scrollView
    }

    /// 文本变化时替换内容并回到顶部。
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard context.coordinator.shown != text,
            let textView = scrollView.documentView as? NSTextView
        else { return }
        context.coordinator.shown = text
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: text, attributes: Self.attributes))
        textView.scroll(.zero)
    }
}
