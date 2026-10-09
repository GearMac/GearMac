// 文件职责：把单个 Markdown 块的行内标记（行内代码、删除线等）转换为带样式的 AttributedString，并给出标题字号映射。
// 分层：UI；纯转换，无状态。
import SwiftUI

/// 单个块的行内 Markdown：`Text` 自身能渲染强调，但不会渲染行内代码与删除线。
enum MarkdownInline {
    /// 解析行内 Markdown 并补齐 `Text` 未处理的样式：行内代码用等宽字体加底色，删除线显式设置。
    static func attributed(_ source: String, _ metrics: InterfaceMetrics) -> AttributedString {
        var text = MarkdownBlock.inline(source)
        let intents = text.runs.compactMap { run in run.inlinePresentationIntent.map { ($0, run.range) } }
        for (intent, range) in intents {
            if intent.contains(.code) {
                text[range].font = metrics.typography.inlineCode
                text[range].backgroundColor = Theme.Colors.controlSurface
            }
            if intent.contains(.strikethrough) { text[range].strikethroughStyle = .single }
        }
        return text
    }

    /// 按标题层级（1、2、3 及以上）返回对应字号。
    static func headingFont(_ level: Int, _ metrics: InterfaceMetrics) -> Font {
        switch level {
        case 1: metrics.typography.markdownHeading1
        case 2: metrics.typography.markdownHeading2
        default: metrics.typography.markdownHeading3
        }
    }
}
