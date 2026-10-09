// 文件职责：渲染词典页面，将词条区块（词头、词性、义项、注记、章节等）排版为可滚动的释义视图。
// 分层：UI；只负责展示与文本样式，不发起查询、不访问磁盘。
import SwiftUI

/// 一页辞典：先词头，再是挂在统一栏位上的编号义项，最后是各个章节。
struct DictionaryEntryView: View {
    @Environment(\.metrics) private var metrics
    let entry: DictionaryEntry

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: metrics.spacing.md) {
                ForEach(entry.blocks.indices, id: \.self) { index in
                    DictionaryBlockView(block: entry.blocks[index], leadsPage: index == 0)
                }
            }
            .textSelection(.enabled)
            .padding(.horizontal, metrics.spacing.xxl)
            .padding(.top, metrics.spacing.md)
            .padding(.bottom, metrics.spacing.xxl)
            .hideNativeScrollers()
        }
        .edgeDissolve()
        .thinScrollbar()
        // 新词条从词头开始，而不是停留在上一个词的滚动位置。
        .id(entry.term)
    }
}

/// 单个区块的渲染：按区块类型选择对应布局与字体。
private struct DictionaryBlockView: View {
    @Environment(\.metrics) private var metrics
    let block: DictionaryEntry.Block
    let leadsPage: Bool

    /// 义项编号悬挂在该栏位内，使每条定义、项目和注记都在同一列起始。
    private var gutter: CGFloat { metrics.spacing.xxl }
    /// 正文列的起始位置，在编号栏位之后。
    private var textColumn: CGFloat { gutter + metrics.spacing.sm }

    var body: some View {
        switch block {
        case .headword(let word, let homograph, let pronunciation):
            HStack(alignment: .firstTextBaseline, spacing: metrics.spacing.md) {
                HStack(alignment: .firstTextBaseline, spacing: metrics.spacing.xxs) {
                    Text(word)
                        .font(metrics.typography.calcResult.weight(.bold))
                    if let homograph {
                        Text(homograph)
                            .font(metrics.typography.keyCap)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .baselineOffset(metrics.spacing.md)
                    }
                }
                if let pronunciation {
                    Text("| \(pronunciation) |")
                        .font(metrics.typography.rowTitle)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            // 同形异义词的页面接在前一页之后，因此需要划出与词条开头相同的间距。
            .padding(.top, leadsPage ? 0 : metrics.spacing.xxxl)
        case .partOfSpeech(let runs):
            Text(runs.attributed(base: Theme.Colors.textSecondary))
                .font(metrics.typography.rowTrailing)
                .padding(.top, metrics.spacing.xs)
        case .sense(let number, let runs):
            HStack(alignment: .firstTextBaseline, spacing: metrics.spacing.sm) {
                Text(number ?? "")
                    .font(metrics.typography.rowTitle.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: gutter, alignment: .trailing)
                Text(runs.attributed())
                    .font(metrics.typography.rowTitle)
            }
        case .subsense(let runs):
            HStack(alignment: .firstTextBaseline, spacing: metrics.spacing.sm) {
                Text("•")
                    .foregroundStyle(Theme.Colors.textTertiary)
                Text(runs.attributed())
            }
            .font(metrics.typography.rowTitle)
            .padding(.leading, textColumn)
        case .note(let runs):
            Text(runs.attributed(base: Theme.Colors.textSecondary))
                .font(metrics.typography.rowTrailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, metrics.spacing.xl)
                .padding(.vertical, metrics.spacing.md)
                .background(noteShape.fill(Theme.Colors.cardFill))
                .overlay(noteShape.strokeBorder(Theme.Colors.cardStroke))
                .padding(.leading, textColumn)
        case .section(let title):
            VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                Text(title)
                    .font(metrics.typography.sectionHeader)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(height: 1)
            }
            .padding(.top, metrics.spacing.xl)
        case .phrase(let runs):
            Text(runs.attributed())
                .font(metrics.typography.rowTitle)
                .padding(.top, metrics.spacing.xs)
        case .paragraph(let runs):
            Text(runs.attributed())
                .font(metrics.typography.rowTitle)
                .padding(.leading, textColumn)
        }
    }

    /// 注记卡片的圆角形状。
    private var noteShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
    }
}

extension [DictionaryEntry.Run] {
    /// 按语义而非字体来设置样式，让每段保留其所在区块设定的字号。
    fileprivate func attributed(base: Color = Theme.Colors.textPrimary) -> AttributedString {
        reduce(into: AttributedString()) { result, run in
            var piece = AttributedString(run.text)
            piece.foregroundColor = base
            switch run.style {
            case .plain: break
            case .example:
                piece.inlinePresentationIntent = .emphasized
                piece.foregroundColor = Theme.Colors.textSecondary
            case .label: piece.foregroundColor = Theme.Colors.textSecondary
            case .strong:
                piece.inlinePresentationIntent = .stronglyEmphasized
                piece.foregroundColor = Theme.Colors.textPrimary
            case .italic: piece.inlinePresentationIntent = .emphasized
            }
            result.append(piece)
        }
    }
}
