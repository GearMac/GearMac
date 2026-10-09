// 文件职责：用 SwiftUI `Grid` 渲染 Markdown 表格，包含表头、分隔线与按对齐方式排布的数据行。
// 分层：UI；只负责展示，不解析表格结构。
import SwiftUI

/// Markdown 表格视图：首行按表头样式渲染，随后是一条分隔线，其余为数据行。
struct MarkdownTableView: View {

    @Environment(\.metrics) private var metrics
    let table: MarkdownBlock.Table

    var body: some View {
        Grid(
            alignment: .leadingFirstTextBaseline, horizontalSpacing: metrics.spacing.xl,
            verticalSpacing: metrics.spacing.sm
        ) {
            GridRow {
                ForEach(Array(table.header.enumerated()), id: \.offset) { column, cell in
                    Text(MarkdownInline.attributed(cell, metrics))
                        .font(metrics.typography.sectionHeader)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .gridColumnAlignment(alignment(at: column))
                }
            }
            GridRow {
                Rectangle()
                    .fill(Theme.Colors.cardStroke)
                    .frame(height: Theme.Size.hairline)
                    .gridCellUnsizedAxes(.horizontal)
                    .gridCellColumns(table.header.count)
            }
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(MarkdownInline.attributed(cell, metrics))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        // 只给定宽度时，Grid 对会换行的行测量高度会比实际绘制少一行。
        .fixedSize(horizontal: false, vertical: true)
        .padding(metrics.spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                .fill(Theme.Colors.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.radius.card, style: .continuous)
                .stroke(Theme.Colors.cardStroke))
    }

    /// 把表格该列的对齐方式映射为 `HorizontalAlignment`。
    private func alignment(at column: Int) -> HorizontalAlignment {
        switch table.alignments[column] {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}
