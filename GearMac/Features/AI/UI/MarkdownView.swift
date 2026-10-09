// 文件职责：渲染已解析的 Markdown 文档，按块类型分发到标题、段落、列表、代码、引用、表格、数学公式与分隔线的具体视图。
// 分层：UI；只负责展示，不解析 Markdown 源文本。
import SwiftUI

/// 渲染已解析的 Markdown；body 被类型擦除，避免嵌套列表让 `Body` 递归成环。
struct MarkdownView: View {
    @Environment(\.metrics) private var metrics
    let blocks: [MarkdownBlock]
    var spacing: CGFloat?

    var body: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: spacing ?? metrics.spacing.lg) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { offset, block in
                    MarkdownBlockView(block: block)
                        .padding(.top, offset > 0 && block.isHeading ? metrics.spacing.sm : 0)
                }
            })
    }
}

extension MarkdownBlock {
    /// 标题开启一个章节，因此它上方留白比两个段落之间需要得更多。
    fileprivate var isHeading: Bool {
        if case .heading = self { return true }
        return false
    }
}

/// 按块类型分发到对应的 Markdown 渲染视图。
private struct MarkdownBlockView: View {
    @Environment(\.metrics) private var metrics
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(MarkdownInline.attributed(text, metrics))
                .font(MarkdownInline.headingFont(level, metrics))
                .fixedSize(horizontal: false, vertical: true)
        case .paragraph(let text):
            Text(MarkdownInline.attributed(text, metrics))
                .fixedSize(horizontal: false, vertical: true)
        case .bulletList(let items):
            MarkdownListView(items: items, start: nil)
        case .numberedList(let start, let items):
            MarkdownListView(items: items, start: start)
        case .code(let language, let text):
            MarkdownCodeView(language: language, text: text)
        case .quote(let blocks):
            MarkdownQuoteView(blocks: blocks)
        case .table(let table):
            MarkdownTableView(table: table)
        case .math(let formula):
            Text(formula.source)
        case .pendingMath:
            EmptyView()
        case .rule:
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(height: Theme.Size.hairline)
        }
    }
}

/// 无序、有序与任务列表视图，标记与内容按首行文本基线对齐。
private struct MarkdownListView: View {

    @Environment(\.metrics) private var metrics
    let items: [MarkdownBlock.Item]
    /// 无序列表为 nil；否则为首项开始的编号。
    let start: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                HStack(alignment: .firstTextBaseline, spacing: metrics.spacing.sm) {
                    marker(at: offset, checked: item.checked)
                        .frame(minWidth: metrics.size.markdownListMarker, alignment: .trailing)
                    MarkdownView(blocks: item.blocks, spacing: metrics.spacing.xs)
                }
            }
        }
    }

    /// 返回该项的列表标记：任务框、有序编号或圆点。
    @ViewBuilder private func marker(at offset: Int, checked: Bool?) -> some View {
        if let checked {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .foregroundStyle(checked ? Theme.Colors.success : Theme.Colors.textTertiary)
        } else if start != nil {
            // 按列表中最宽编号留白，避免标记在数字中间折行。
            Text(orderedMarker(at: offset))
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: true, vertical: false)
        } else {
            Text("•").foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    /// 用空格在列表内右对齐；等宽数字宽度一致，因此可直接计算。
    private func orderedMarker(at offset: Int) -> String {
        guard let start else { return "" }
        let widest = String(start + max(items.count - 1, 0)).count
        let number = String(start + offset)
        return String(repeating: " ", count: max(0, widest - number.count)) + number + "."
    }
}

/// 引用块视图：左侧一条竖线，内容以次级文本颜色渲染。
private struct MarkdownQuoteView: View {

    @Environment(\.metrics) private var metrics
    let blocks: [MarkdownBlock]

    var body: some View {
        HStack(alignment: .top, spacing: metrics.spacing.lg) {
            RoundedRectangle(cornerRadius: metrics.radius.keyCap, style: .continuous)
                .fill(Theme.Colors.border)
                .frame(width: metrics.size.markdownQuoteBar)
            MarkdownView(blocks: blocks)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
