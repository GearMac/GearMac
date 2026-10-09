// 文件职责：把发布说明文本按块渲染为窗口中的标题、列表项与段落。
// 分层：UI（SwiftUI）；解析逻辑在 ReleaseNotes，本视图只负责排版。
import SwiftUI

/// `AttributedString` 只能做行内样式，因此标题与列表项由本视图排版。
struct ReleaseNotesView: View {
    let text: String

    private var blocks: [ReleaseNotes.Block] { ReleaseNotes.blocks(from: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                view(for: block)
                    .padding(.top, isHeading(block) && index > 0 ? Theme.Spacing.md : 0)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: ReleaseNotes.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(level <= 2 ? .headline : .subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text("•").foregroundStyle(Theme.Colors.textSecondary)
                Text(markdown(text))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .paragraph(let text):
            Text(markdown(text))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func isHeading(_ block: ReleaseNotes.Block) -> Bool {
        if case .heading = block { return true }
        return false
    }

    /// GitHub 发布说明正文是 Markdown；解析失败的内容作为纯文本仍然可读。
    private func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
