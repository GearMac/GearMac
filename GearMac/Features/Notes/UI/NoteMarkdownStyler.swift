// 文件职责：将解析后的 Markdown 行转换为 NSAttributedString 属性（字体、颜色、段落样式与块级装饰）。
// 分层：UI 样式层；`@MainActor` 限定，只计算属性，不修改文本内容。
import AppKit
import SwiftUI

/// 将解析后的行转换为属性；即使光标显示了语法，无序列表也保留其圆点。
@MainActor
enum NoteMarkdownStyler {
    /// 属性字典的简写别名。
    typealias Attributes = [NSAttributedString.Key: Any]

    /// 单行的样式：基础属性与叠加其上的局部区间属性。
    struct LineStyle {
        /// 覆盖整行的属性，用于替换该行原有的属性。
        let base: Attributes
        /// 按顺序叠加在 `base` 之上，使内层区间可以覆盖外层。
        let runs: [(range: NSRange, attributes: Attributes)]
    }

    /// 纯文本编辑器的属性，也是每条渲染行属性的起点。
    static let literal: Attributes = [
        .font: NoteMarkdownTypography.body,
        .foregroundColor: NSColor(Theme.Colors.noteText)
    ]

    private static let hidden: Attributes = [
        .font: NoteMarkdownTypography.hidden,
        .foregroundColor: NSColor.clear
    ]
    private static let hiddenEmptyListMarker: Attributes = [
        .font: NoteMarkdownTypography.body,
        .foregroundColor: NSColor.clear
    ]

    private static let listSlot = NoteCheckboxGeometry.slot(
        bodyPointSize: NoteMarkdownTypography.body.pointSize)
    private static let quoteStep = Theme.Size.markdownQuoteBar + Theme.Spacing.lg
    private static let codeInset = Theme.Spacing.lg
    /// 每个列表项后的间距；显示标记时仍然保留，使移动光标不会引起行位置跳动。
    private static let listItemSpacing = Theme.Spacing.md
    /// 只有这些协议会获得 `.link` 属性，也只有它们在被点击时会被打开。
    static let openableSchemes: Set<String> = ["http", "https", "mailto"]

    /// 片段绘制用的颜色在此时解析，且使用调用方的绘制外观。
    static func style(
        at index: Int, in markdown: NoteMarkdown, text: NSString, isRevealed: Bool
    ) -> LineStyle {
        let line = markdown.lines[index]
        var base = literal
        var runs: [(range: NSRange, attributes: Attributes)] = []
        let markerLook = isRevealed ? revealedMarker : hidden

        switch line.kind {
        case .blank, .paragraph:
            break
        case .heading(let level):
            base[.font] = NoteMarkdownTypography.heading(level)
            base[.paragraphStyle] = paragraph {
                $0.paragraphSpacingBefore =
                    index == 0 ? 0 : level <= 2 ? Theme.Spacing.xl : Theme.Spacing.md
                $0.paragraphSpacing = Theme.Spacing.xs
            }
            if let marker = line.markerRange { runs.append((marker, markerLook)) }
        case .bullet, .ordered, .task:
            let revealsMarker = isRevealed && line.kind != .bullet
            let isEmpty = line.contentRange.length == 0
            if let marker = line.markerRange {
                let listMarkerLook: Attributes =
                    revealsMarker
                    ? [.foregroundColor: color(Theme.Colors.textSecondary)]
                    : (isEmpty ? hiddenEmptyListMarker : hidden)
                runs.append((marker, listMarkerLook))
            }
            if case .task(checked: true) = line.kind {
                runs.append((line.contentRange, checkedTask))
            }
            let contentIndent = CGFloat(line.level + 1) * listSlot
            base[.paragraphStyle] =
                revealsMarker || isEmpty
                ? hanging(
                    line.markerRange, in: text, contentIndent: contentIndent, spacingAfter: listItemSpacing)
                : indented(by: contentIndent, spacingAfter: listItemSpacing)
            if !revealsMarker { base[.noteBlockDecoration] = listDecoration(line, text: text) }
        case .quote(let depth):
            if let marker = line.markerRange { runs.append((marker, markerLook)) }
            runs.append((line.contentRange, [.foregroundColor: color(Theme.Colors.textSecondary)]))
            guard !isRevealed else {
                base[.paragraphStyle] = hanging(
                    line.markerRange, in: text, contentIndent: CGFloat(depth) * quoteStep)
                break
            }
            base[.paragraphStyle] = indented(by: CGFloat(depth) * quoteStep)
            base[.noteBlockDecoration] = decoration(
                .quote(depth: depth), fill: Theme.Colors.border, ink: Theme.Colors.border)
        case .rule:
            guard !isRevealed else {
                base[.foregroundColor] = color(Theme.Colors.textTertiary)
                break
            }
            base[.foregroundColor] = NSColor.clear
            base[.noteBlockDecoration] = decoration(
                .rule, fill: Theme.Colors.separator, ink: Theme.Colors.separator)
        case .table:
            base[.font] = NoteMarkdownTypography.codeBlock
            base[.paragraphStyle] = tableRow
        case .fenceOpen, .fenceClose, .code:
            base[.font] = NoteMarkdownTypography.codeBlock
            base[.paragraphStyle] = codeParagraph
            if line.kind != .code {
                base[.foregroundColor] = isRevealed ? color(Theme.Colors.textTertiary) : NSColor.clear
            }
            base[.noteBlockDecoration] = decoration(
                .code(codeRow(index, markdown), language: language(line.kind)),
                fill: Theme.Colors.cardFill, ink: Theme.Colors.textTertiary)
        }

        let lineFont = base[.font] as? NSFont ?? NoteMarkdownTypography.body
        runs += inlineRuns(markdown.inlines(of: line), lineFont: lineFont, text: text, isRevealed: isRevealed)
        return LineStyle(base: base, runs: runs)
    }

    // MARK: - Inlines

    /// 计算行内区间（强调、删除线、行内代码、链接等）的属性。
    private static func inlineRuns(
        _ inlines: [NoteMarkdown.Inline], lineFont: NSFont, text: NSString, isRevealed: Bool
    ) -> [(range: NSRange, attributes: Attributes)] {
        var runs: [(range: NSRange, attributes: Attributes)] = []
        for (position, inline) in inlines.enumerated() {
            let font = spanFont(inlines[...position], lineFont: lineFont)
            var markerLook = isRevealed ? revealedMarker.merging([.font: font]) { $1 } : hidden
            switch inline.kind {
            case .strong, .emphasis, .strongEmphasis:
                runs.append((inline.contentRange, [.font: font]))
            case .strikethrough:
                runs.append((inline.contentRange, [.strikethroughStyle: NSUnderlineStyle.single.rawValue]))
            case .code:
                let codeFont = NoteMarkdownTypography.inlineCode(matching: font)
                if isRevealed { markerLook[.font] = codeFont }
                let background = color(Theme.Colors.controlSurface)
                runs.append((inline.contentRange, [.font: codeFont, .backgroundColor: background]))
            case .link(let destination):
                runs.append((inline.contentRange, linkLook(URL(string: destination), isRevealed: isRevealed)))
            case .autolink:
                let url = URL(string: text.substring(with: inline.range))
                runs.append((inline.range, linkLook(url, isRevealed: isRevealed)))
            }
            runs += inline.markerRanges.map { ($0, markerLook) }
        }
        return runs
    }

    /// 返回该区间的字体：行字体加上所有包围它的强调区间所带特征。
    private static func spanFont(_ spans: ArraySlice<NoteMarkdown.Inline>, lineFont: NSFont) -> NSFont {
        guard let span = spans.last else { return lineFont }
        var traits: NSFontDescriptor.SymbolicTraits = []
        for outer in spans where NSIntersectionRange(outer.range, span.range) == span.range {
            switch outer.kind {
            case .strong: traits.insert(.bold)
            case .emphasis: traits.insert(.italic)
            case .strongEmphasis: traits.formUnion([.bold, .italic])
            default: break
            }
        }
        return traits.isEmpty ? lineFont : NoteMarkdownTypography.adding(traits, to: lineFont)
    }

    /// 已显示标记的链接只是普通彩色文本，因此点击时把光标放到链接上以便编辑其 URL。
    private static func linkLook(_ url: URL?, isRevealed: Bool) -> Attributes {
        guard !isRevealed else { return [.foregroundColor: NSColor.linkColor] }
        guard let url, let scheme = url.scheme?.lowercased(), openableSchemes.contains(scheme) else {
            return [:]
        }
        return [.link: url]
    }

    // MARK: - Blocks

    /// 已显示标记的标记颜色。
    private static var revealedMarker: Attributes {
        [.foregroundColor: color(Theme.Colors.textTertiary)]
    }

    /// 已勾选任务项的文字样式（次要色加删除线）。
    private static var checkedTask: Attributes {
        [
            .foregroundColor: color(Theme.Colors.textSecondary),
            .strikethroughStyle: NSUnderlineStyle.single.rawValue
        ]
    }

    /// 换行的表格行悬挂在其首行之下，使每一行仍能读作一体。
    private static let tableRow: NSParagraphStyle = paragraph { $0.headIndent = Theme.Spacing.lg }

    /// 代码块段落的段落样式：左右两侧留出内缩。
    private static let codeParagraph: NSParagraphStyle = paragraph {
        $0.firstLineHeadIndent = codeInset
        $0.headIndent = codeInset
        $0.tailIndent = -codeInset
    }

    /// 返回内容整体内缩的段落样式。
    private static func indented(by indent: CGFloat, spacingAfter: CGFloat = 0) -> NSParagraphStyle {
        paragraph {
            $0.firstLineHeadIndent = indent
            $0.headIndent = indent
            $0.paragraphSpacing = spacingAfter
        }
    }

    /// 已显示标记的标记悬挂在内容左侧，因此正文位置与渲染行保持一致。
    private static func hanging(
        _ marker: NSRange?, in text: NSString, contentIndent: CGFloat, spacingAfter: CGFloat = 0
    ) -> NSParagraphStyle {
        let markerText = marker.map { text.substring(with: $0) as NSString }
        let width = markerText?.size(withAttributes: [.font: NoteMarkdownTypography.body]).width ?? 0
        return paragraph {
            $0.firstLineHeadIndent = max(0, contentIndent - width)
            $0.headIndent = contentIndent
            $0.paragraphSpacing = spacingAfter
        }
    }

    /// 便捷构建 `NSParagraphStyle` 的辅助方法。
    private static func paragraph(_ configure: (NSMutableParagraphStyle) -> Void) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        configure(style)
        return style
    }

    /// 根据列表行类型生成对应的块级装饰（任务框、有序编号或圆点）。
    private static func listDecoration(_ line: NoteMarkdown.Line, text: NSString) -> NoteBlockDecoration {
        let shape: NoteBlockDecoration.Shape
        switch line.kind {
        case .task(let checked):
            shape = .task(level: line.level, checked: checked)
        case .ordered:
            let label = text.substring(with: line.markerRange ?? line.contentRange)
                .trimmingCharacters(in: .whitespaces)
            shape = .ordered(level: line.level, label: label)
        default:
            shape = .bullet(level: line.level)
        }
        return decoration(shape, fill: Theme.Colors.textSecondary, ink: Theme.Colors.textSecondary)
    }

    /// 二分查找给定行所属的代码块，并返回其行位置（首/中/末/单行）。
    private static func codeRow(_ index: Int, _ markdown: NoteMarkdown) -> NoteBlockDecoration.Shape.CodeRow {
        let blocks = markdown.fenceBlocks
        var low = 0
        var high = blocks.count
        while low < high {
            let middle = (low + high) / 2
            if blocks[middle].upperBound < index { low = middle + 1 } else { high = middle }
        }
        guard low < blocks.count, blocks[low].contains(index) else { return .middle }
        let block = blocks[low]
        switch index {
        case block.lowerBound where block.lowerBound == block.upperBound: return .single
        case block.lowerBound: return .top
        case block.upperBound: return .bottom
        default: return .middle
        }
    }

    /// 若行是代码块起始行则返回其语言标识，否则返回 nil。
    private static func language(_ kind: NoteMarkdown.Line.Kind) -> String? {
        guard case .fenceOpen(let language) = kind else { return nil }
        return language
    }

    /// 使用当前正文字号构建块级装饰对象。
    private static func decoration(
        _ shape: NoteBlockDecoration.Shape, fill: Color, ink: Color
    ) -> NoteBlockDecoration {
        NoteBlockDecoration(
            shape: shape, fill: color(fill), ink: color(ink),
            bodyPointSize: NoteMarkdownTypography.body.pointSize)
    }

    /// 把动态颜色 token 固定到当前绘制外观；绘制片段无法自行解析这类颜色。
    private static func color(_ token: Color) -> NSColor {
        if let resolved = resolved[token] { return resolved }
        let pinned = NSColor(cgColor: NSColor(token).cgColor) ?? NSColor(token)
        resolved[token] = pinned
        return pinned
    }

    /// 固定的颜色属于某一种外观，因此外观变化时必须丢弃它们。
    static func invalidateColors() {
        resolved.removeAll(keepingCapacity: true)
    }

    private static var resolved: [Color: NSColor] = [:]
}
