// 文件职责：把 Markdown 块渲染成富文本串（NSAttributedString），并产出代码块位置与当前查找匹配。
// 分层：UI/渲染（@MainActor）；依赖 AppKit 排版与 SwiftUI 的主题/度量常量，不持有视图状态。
import AppKit
import SwiftUI

/// 文本绘制所依赖的全部输入；只要其中任一项变化，视图就会重新渲染。
struct ChatMarkdownSource: Equatable {
    let blocks: [MarkdownBlock]
    let highlight: ChatTextHighlight?
    let citations: [String: Int]
    let prefix: [Int]
    let failed: Bool
    let metrics: InterfaceMetrics
}

/// 渲染器的产出：文本、每个代码块的位置，以及当前查找匹配。
struct ChatRenderedText {
    let string: NSAttributedString
    let codeBlocks: [CodeBlock]
    let current: NSRange?

    /// 一个代码块的位置、文本与语言。
    struct CodeBlock {
        let block: NSTextBlock
        let range: NSRange
        let code: String
        let language: String?
    }
}

/// 把 Markdown 转成一个富文本串；每段文本采用 `ChatFindIndex.leaves` 的路径标识以便查找。
@MainActor
struct ChatMarkdownRenderer {
    /// 代码块在代码上方为语言标签与 Copy 按钮留出的条带高度。
    static let codeHeaderHeight: CGFloat = 16
    /// 在构建富文本串时标记当前匹配；后续插入的引用标注会使其位置偏移。
    private static let currentMatch = NSAttributedString.Key("GearMacChatFindCurrent")
    /// 回复是不可信文本，因此 `file:` 或应用 scheme 链接绝不能因点击而打开。
    private static let openableSchemes: Set<String> = ["http", "https", "mailto"]
    /// 公式附件字符所代表的源码，也就是复制它时得到的内容。
    static let mathSource = NSAttributedString.Key("GearMacMathSource")

    private let source: ChatMarkdownSource
    private var typography: InterfaceMetrics.Typography { source.metrics.typography }
    private var spacing: InterfaceMetrics.Spacing { source.metrics.spacing }

    init(_ source: ChatMarkdownSource) {
        self.source = source
    }

    /// 渲染过程中的可变输出：累积的富文本串与已记录的代码块。
    private final class Output {
        let string = NSMutableAttributedString()
        var codeBlocks: [ChatRenderedText.CodeBlock] = []
    }

    /// One engine per text size a render meets, since each loads its three fonts.
    /// 按字号缓存数学排版引擎。
    private final class MathEngines {
        var bySize: [CGFloat: MathLayoutEngine] = [:]
    }

    private let mathEngines = MathEngines()

    /// 记录一个块所处的环境：它周围的文本块（引用、代码、单元格）以及列表缩进。
    private struct Context {
        var textBlocks: [NSTextBlock] = []
        var indent: CGFloat = 0
        var secondary = false
    }

    /// 渲染全部块并返回最终结果（去掉末尾多余换行、定位当前匹配）。
    func render() -> ChatRenderedText {
        let output = Output()
        render(source.blocks, at: source.prefix, in: Context(), into: output)
        // 最后一段自带的换行会在回复下方多画一个空行。
        if output.string.string.hasSuffix("\n") {
            output.string.deleteCharacters(in: NSRange(location: output.string.length - 1, length: 1))
        }
        var current: NSRange?
        output.string.enumerateAttribute(
            Self.currentMatch, in: NSRange(location: 0, length: output.string.length)
        ) { value, range, stop in
            guard value != nil else { return }
            current = range
            stop.pointee = true
        }
        return ChatRenderedText(string: output.string, codeBlocks: output.codeBlocks, current: current)
    }

    private var bodyFont: NSFont { typography.textNSFont(.body) }

    /// 依据失败态与次要层级选择文本颜色。
    private func textColor(_ context: Context) -> NSColor {
        if source.failed { return NSColor(Theme.Colors.destructive) }
        return context.secondary ? NSColor(Theme.Colors.textSecondary) : .labelColor
    }

    /// 当列表项逐个渲染其后续块时，`first` 用于给这些块编号。
    private func render(
        _ blocks: [MarkdownBlock], at path: [Int], in context: Context, into output: Output,
        first: Int = 0, spacingAfter: CGFloat? = nil
    ) {
        for (offset, block) in blocks.enumerated() {
            let position = first + offset
            let leaf = path + [position]
            let after = spacingAfter ?? spacing.lg
            switch block {
            case .heading(let level, let text):
                inline(text, font: headingFont(level), leaf: leaf, in: context, into: output) { style in
                    style.paragraphSpacingBefore = position > 0 ? spacing.sm : 0
                    style.paragraphSpacing = after
                }
            case .paragraph(let text):
                inline(text, font: bodyFont, leaf: leaf, in: context, into: output) { style in
                    style.paragraphSpacing = after
                }
            case .bulletList(let items):
                list(items, start: nil, at: leaf, in: context, into: output, after: after)
            case .numberedList(let start, let items):
                list(items, start: start, at: leaf, in: context, into: output, after: after)
            case .code(let language, let text):
                code(language: language, text: text, leaf: leaf, in: context, into: output, after: after)
            case .quote(let inner):
                let bar = Self.fullWidthBlock()
                bar.setWidth(Theme.Size.markdownQuoteBar, type: .absoluteValueType, for: .border, edge: .minX)
                bar.setBorderColor(NSColor(Theme.Colors.border), for: .minX)
                bar.setWidth(spacing.lg, type: .absoluteValueType, for: .padding, edge: .minX)
                bar.setWidth(context.indent, type: .absoluteValueType, for: .margin, edge: .minX)
                bar.setWidth(after, type: .absoluteValueType, for: .margin, edge: .maxY)
                var inside = context
                inside.textBlocks.append(bar)
                inside.indent = 0
                inside.secondary = true
                render(inner, at: leaf, in: inside, into: output, spacingAfter: spacing.sm)
            case .table(let table):
                self.table(table, at: leaf, in: context, into: output, after: after)
            case .math(let formula):
                let line = NSMutableAttributedString(
                    attributedString: self.formula(
                        formula, font: bodyFont, attributes: [.foregroundColor: textColor(context)]))
                centred(line, in: context, into: output, after: after)
            case .pendingMath:
                // 占在公式最终落点的位置，使公式完成时就地替换而不是整段跳动。
                let dots = NSMutableAttributedString(
                    string: "…",
                    attributes: [.font: bodyFont, .foregroundColor: NSColor(Theme.Colors.textTertiary)])
                centred(dots, in: context, into: output, after: after)
            case .rule:
                let line = Self.fullWidthBlock()
                line.setWidth(Theme.Size.hairline, type: .absoluteValueType, for: .border, edge: .maxY)
                line.setBorderColor(NSColor(Theme.Colors.separator), for: .maxY)
                line.setWidth(context.indent, type: .absoluteValueType, for: .margin, edge: .minX)
                line.setWidth(after, type: .absoluteValueType, for: .margin, edge: .maxY)
                output.string.append(
                    NSAttributedString(
                        string: "\n",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 1),
                            .paragraphStyle: paragraphStyle(in: context, extra: [line])
                        ]))
            }
        }
    }

    /// 把一行居中追加到输出，并设置段后间距。
    private func centred(
        _ line: NSMutableAttributedString, in context: Context, into output: Output, after: CGFloat
    ) {
        line.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont]))
        let style = paragraphStyle(in: context)
        style.alignment = .center
        style.paragraphSpacing = after
        line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))
        output.string.append(line)
    }

    /// 宽度未设置的块在布局时不会画出自身的盒子：无填充、无边框、无边界。
    private static func fullWidthBlock() -> NSTextBlock {
        let block = NSTextBlock()
        block.setValue(100, type: .percentageValueType, for: .width)
        return block
    }

    private func headingFont(_ level: Int) -> NSFont {
        switch level {
        case 1: typography.textNSFont(.title2, weight: .semibold)
        case 2: typography.textNSFont(.title3, weight: .semibold)
        default: typography.textNSFont(.headline)
        }
    }

    /// 构造段落样式：行距、文本块、缩进与首行缩进。
    private func paragraphStyle(in context: Context, extra: [NSTextBlock] = []) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = spacing.chatLine
        style.textBlocks = context.textBlocks + extra
        style.firstLineHeadIndent = context.indent
        style.headIndent = context.indent
        return style
    }

    /// 一段绘制文本即一个段落：行内 Markdown、查找高亮，然后插入引用标注。
    private func inline(
        _ text: String, font: NSFont, leaf: [Int], in context: Context, into output: Output,
        marker: String? = nil, extraBlocks: [NSTextBlock] = [], alignment: NSTextAlignment = .natural,
        style configure: (NSMutableParagraphStyle) -> Void = { _ in }
    ) {
        let parsed = MarkdownBlock.inline(text)
        let drawn = attributed(parsed, font: font, color: textColor(context))
        mark(drawn, leaf: leaf)
        insertCitations(into: drawn, from: parsed)
        let style = paragraphStyle(in: context, extra: extraBlocks)
        style.alignment = alignment
        configure(style)
        let line = NSMutableAttributedString()
        if let marker {
            line.append(
                NSAttributedString(
                    string: marker,
                    attributes: [.font: bodyFont, .foregroundColor: NSColor(Theme.Colors.textSecondary)]))
        }
        line.append(drawn)
        line.append(NSAttributedString(string: "\n", attributes: [.font: font]))
        line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))
        output.string.append(line)
    }

    /// 基于 Foundation 的行内解析结果应用强调、加粗、行内代码、删除线与链接。
    private func attributed(
        _ parsed: AttributedString, font: NSFont, color: NSColor
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        for run in parsed.runs {
            var runFont = font
            var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: color]
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.stronglyEmphasized) {
                    runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .boldFontMask)
                }
                if intent.contains(.emphasized) {
                    runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .italicFontMask)
                }
                if intent.contains(.code) {
                    runFont = typography.textNSFont(.body, monospaced: true)
                    attributes[.backgroundColor] = NSColor(Theme.Colors.controlSurface)
                }
                if intent.contains(.strikethrough) {
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
            }
            if let link = run.link, let scheme = link.scheme?.lowercased(),
                Self.openableSchemes.contains(scheme)
            {
                attributes[.link] = link
            }
            attributes[.font] = runFont
            let text = String(parsed[run.range].characters)
            guard let formula = run[MathFormula.Attribute.self] else {
                result.append(NSAttributedString(string: text, attributes: attributes))
                continue
            }
            // 两个相同公式相邻时会共用一个 run，因此每个字符各对应一个公式。
            for _ in text {
                result.append(self.formula(formula, font: runFont, attributes: attributes))
            }
        }
        return result
    }

    /// 按需创建并缓存某字号的数学排版引擎。
    private func mathEngine(for font: NSFont) -> MathLayoutEngine? {
        if let engine = mathEngines.bySize[font.pointSize] { return engine }
        let engine = MathLayoutEngine(size: MathFont.size(matchingXHeightOf: font))
        mathEngines.bySize[font.pointSize] = engine
        return engine
    }

    /// 生成一个附件字符，其尺寸使数学符号的 x-height 与周围文本匹配。
    private func formula(
        _ formula: MathFormula, font: NSFont, attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let color = attributes[.foregroundColor] as? NSColor ?? textColor(Context())
        let box =
            mathEngine(for: font)?.layout(formula) ?? MathBox(text: formula.source, font: font as CTFont)
        let attachment = NSTextAttachment()
        attachment.attachmentCell = MathAttachmentCell(box: box, color: color, label: formula.source)
        let string = NSMutableAttributedString(attachment: attachment)
        var styled = attributes
        styled[.font] = font
        styled[Self.mathSource] = formula.source
        string.addAttributes(styled, range: NSRange(location: 0, length: string.length))
        return string
    }

    /// 每个匹配都涂上查找色；当前匹配用实色标记，并打上稍后查找用的标签。
    private func mark(_ text: NSMutableAttributedString, leaf: [Int]) {
        guard let highlight = source.highlight else { return }
        let plain = text.string
        for (index, range) in ChatFindIndex.ranges(of: highlight.query, in: plain).enumerated() {
            let span = NSRange(range, in: plain)
            let isCurrent = highlight.current?.leaf == leaf && highlight.current?.index == index
            let tint = isCurrent ? Theme.Colors.findCurrent : Theme.Colors.findMatch
            text.addAttribute(.backgroundColor, value: NSColor(tint), range: span)
            guard isCurrent else { continue }
            text.addAttribute(.foregroundColor, value: NSColor(Theme.Colors.findCurrentInk), range: span)
            text.addAttribute(Self.currentMatch, value: true, range: span)
        }
    }

    /// 排在查找之后：查找按回复原始文本（不含编号）统计匹配。
    private func insertCitations(into text: NSMutableAttributedString, from parsed: AttributedString) {
        let plain = String(parsed.characters)
        for anchor in ChatCitations.anchors(in: parsed, numbers: source.citations).reversed() {
            let index = plain.index(plain.startIndex, offsetBy: anchor.offset)
            let marker = NSAttributedString(
                string: "[\(anchor.number)]",
                attributes: [
                    .font: typography.textNSFont(.caption1), .baselineOffset: spacing.xs,
                    .link: anchor.url
                ])
            text.insert(marker, at: NSRange(index..<index, in: plain).location)
        }
    }

    /// 渲染有序/无序/待办列表，标记符号按编号或勾选状态给出。
    private func list(
        _ items: [MarkdownBlock.Item], start: Int?, at path: [Int], in context: Context,
        into output: Output, after: CGFloat
    ) {
        // 宽度足以容纳列表中最长的编号，使每一项的正文起始位置对齐在同一列。
        let digits = start.map { String($0 + max(items.count - 1, 0)).count + 1 } ?? 1
        let width = ceil(bodyFont.pointSize * 0.62 * CGFloat(digits)) + spacing.md
        for (offset, item) in items.enumerated() {
            var inside = context
            inside.indent = context.indent + width
            let marker: String
            if let checked = item.checked {
                marker = checked ? "☑" : "☐"
            } else if let start {
                marker = "\(start + offset)."
            } else {
                marker = "•"
            }
            let itemPath = path + [offset]
            for (index, block) in item.blocks.enumerated() {
                let isEnd = offset == items.count - 1 && index == item.blocks.count - 1
                let blockAfter = isEnd ? after : spacing.xs
                guard index == 0, case .paragraph(let text) = block else {
                    render(
                        [block], at: itemPath, in: inside, into: output, first: index,
                        spacingAfter: blockAfter)
                    continue
                }
                inline(
                    text, font: bodyFont, leaf: itemPath + [0], in: inside, into: output,
                    marker: "\(marker)\t"
                ) { style in
                    style.firstLineHeadIndent = context.indent
                    style.tabStops = [NSTextTab(textAlignment: .natural, location: inside.indent)]
                    style.paragraphSpacing = blockAfter
                }
            }
        }
    }

    /// 渲染代码块：带背景与边框的盒子、等宽字体、语言头部与底部间距。
    private func code(
        language: String?, text: String, leaf: [Int], in context: Context, into output: Output,
        after: CGFloat
    ) {
        let box = Self.fullWidthBlock()
        box.backgroundColor = NSColor(Theme.Colors.cardFill)
        box.setBorderColor(NSColor(Theme.Colors.cardStroke))
        box.setWidth(Theme.Size.hairline, type: .absoluteValueType, for: .border)
        box.setWidth(spacing.xl, type: .absoluteValueType, for: .padding, edge: .minX)
        box.setWidth(spacing.xl, type: .absoluteValueType, for: .padding, edge: .maxX)
        // 代码上方的头部条带用于放置语言标签与 Copy 按钮。
        box.setWidth(
            spacing.md + Self.codeHeaderHeight + spacing.sm, type: .absoluteValueType, for: .padding,
            edge: .minY)
        box.setWidth(spacing.lg, type: .absoluteValueType, for: .padding, edge: .maxY)
        box.setWidth(context.indent, type: .absoluteValueType, for: .margin, edge: .minX)
        let font = typography.textNSFont(.callout, monospaced: true)
        let style = paragraphStyle(in: context, extra: [box])
        style.firstLineHeadIndent = 0
        style.headIndent = 0
        let body = NSMutableAttributedString(
            string: text, attributes: [.font: font, .foregroundColor: textColor(context)])
        mark(body, leaf: leaf)
        let start = output.string.length
        body.append(NSAttributedString(string: "\n", attributes: [.font: font]))
        body.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: body.length))
        output.string.append(body)
        output.codeBlocks.append(
            ChatRenderedText.CodeBlock(
                block: box, range: NSRange(location: start, length: body.length), code: text,
                language: language))
        spacer(after, in: context, into: output)
    }

    /// 块的底部外边距会被其填充色绘制，因此代码块下方的空隙实际是一整行。
    private func spacer(_ height: CGFloat, in context: Context, into output: Output) {
        let style = paragraphStyle(in: context)
        style.lineSpacing = 0
        style.minimumLineHeight = height
        style.maximumLineHeight = height
        output.string.append(
            NSAttributedString(
                string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 1), .paragraphStyle: style]))
    }

    /// 渲染表格：按列对齐，首行为表头（有底色）。
    private func table(
        _ table: MarkdownBlock.Table, at path: [Int], in context: Context, into output: Output,
        after: CGFloat
    ) {
        let grid = NSTextTable()
        grid.numberOfColumns = max(table.header.count, 1)
        grid.layoutAlgorithm = .automaticLayoutAlgorithm
        grid.collapsesBorders = true
        grid.hidesEmptyCells = false
        grid.setWidth(context.indent, type: .absoluteValueType, for: .margin, edge: .minX)
        grid.setWidth(after, type: .absoluteValueType, for: .margin, edge: .maxY)
        let rows = [table.header] + table.rows
        for (row, cells) in rows.enumerated() {
            for column in 0..<grid.numberOfColumns {
                let cell = NSTextTableBlock(
                    table: grid, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
                cell.setWidth(spacing.sm, type: .absoluteValueType, for: .padding)
                cell.setWidth(spacing.lg, type: .absoluteValueType, for: .padding, edge: .minX)
                cell.setWidth(spacing.lg, type: .absoluteValueType, for: .padding, edge: .maxX)
                if row > 0 {
                    cell.setWidth(Theme.Size.hairline, type: .absoluteValueType, for: .border, edge: .minY)
                    cell.setBorderColor(NSColor(Theme.Colors.cardStroke), for: .minY)
                }
                if row == 0 { cell.backgroundColor = NSColor(Theme.Colors.cardFill) }
                var inside = context
                inside.secondary = context.secondary || row == 0
                inside.indent = 0
                inline(
                    column < cells.count ? cells[column] : "",
                    font: row == 0 ? typography.textNSFont(.subheadline, weight: .medium) : bodyFont,
                    leaf: path + [row, column], in: inside, into: output, extraBlocks: [cell],
                    alignment: alignment(table, column))
            }
        }
    }

    /// 把表格列的 Markdown 对齐方式映射为 NSTextAlignment。
    private func alignment(_ table: MarkdownBlock.Table, _ column: Int) -> NSTextAlignment {
        guard column < table.alignments.count else { return .natural }
        switch table.alignments[column] {
        case .leading: return .natural
        case .center: return .center
        case .trailing: return .right
        }
    }
}
