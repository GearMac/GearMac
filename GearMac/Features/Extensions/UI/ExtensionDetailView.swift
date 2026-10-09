// 文件职责：渲染扩展的 `Detail` 界面（Markdown 正文 + 元数据侧栏）与列表的详情面板，并实现元数据行、标签流式布局与 Markdown 块解析渲染。
// 分层：UI；仅负责展示，不执行业务逻辑。
import SwiftUI

/// `Detail` 界面，以及 `List` 在 `isShowingDetail` 开启时显示的详情面板。
struct ExtensionDetailBody: View {
    @Environment(\.metrics) private var metrics
    let markdown: String?
    let metadata: RenderNode?
    let isLoading: Bool
    let assetsPath: String?
    /// 列表的详情面板太窄，无法容纳元数据侧栏。
    var stacksMetadata = false

    private static let stackedInset: CGFloat = 16

    var body: some View {
        HStack(spacing: 0) {
            markdownPane(trailing: stacksMetadata ? metadata : nil)
            if !stacksMetadata, let metadata {
                Rectangle().fill(Theme.Colors.separator).frame(width: 1)
                metadataPane(metadata)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func markdownPane(trailing metadata: RenderNode?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.spacing.md) {
                if isLoading && (markdown ?? "").isEmpty {
                    Text("Loading…").foregroundStyle(.secondary)
                }
                if let markdown, !markdown.isEmpty {
                    ExtensionMarkdownView(markdown: markdown)
                }
                if let metadata {
                    ExtensionMetadataView(metadata: metadata, assetsPath: assetsPath, inline: true)
                        .padding(.top, (markdown ?? "").isEmpty ? 0 : metrics.spacing.xxl)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(
                .horizontal, stacksMetadata ? metrics.scaled(Self.stackedInset) : metrics.spacing.lg
            )
            .padding(.vertical, metrics.spacing.md)
            .hideNativeScrollers()
        }
        .frame(maxWidth: .infinity)
        .edgeDissolve()
        .thinScrollbar()
    }

    /// `Detail.Metadata` 侧栏的固定宽度；Markdown 面板占用剩余空间。
    private static let metadataWidth: CGFloat = 240

    private func metadataPane(_ metadata: RenderNode) -> some View {
        ScrollView {
            ExtensionMetadataView(metadata: metadata, assetsPath: assetsPath)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, metrics.spacing.lg)
                .padding(.vertical, metrics.spacing.md)
                .hideNativeScrollers()
        }
        .frame(width: metrics.scaled(Self.metadataWidth))
        .edgeDissolve()
        .thinScrollbar()
    }
}

/// `Detail.Metadata`——label / link / tag-list / separator 行。
struct ExtensionMetadataView: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.isDarkAppearance) private var isDark
    let metadata: RenderNode
    let assetsPath: String?
    var inline = false

    private static let inlineRowHeight: CGFloat = 28

    /// 斑马纹只能按真实行计数，因此这里去掉分隔行。
    private var visibleChildren: [RenderNode] {
        inline
            ? metadata.children.filter { $0.type != "Detail.Metadata.Separator" }
            : metadata.children
    }

    var body: some View {
        VStack(alignment: .leading, spacing: inline ? 0 : metrics.spacing.lg) {
            ForEach(Array(visibleChildren.enumerated()), id: \.element.id) { index, child in
                switch child.type {
                case "Detail.Metadata.Label":
                    row(title: child.string("title"), index: index) {
                        HStack(spacing: metrics.spacing.xs) {
                            if let icon = child.props["icon"] {
                                ExtensionIconView(
                                    resolved: ExtensionImage.resolve(
                                        icon, assetsPath: assetsPath, isDark: isDark),
                                    size: 14)
                            }
                            Text(labelText(child))
                                .font(metrics.typography.rowTitle)
                                .textSelection(.enabled)
                        }
                    }
                case "Detail.Metadata.Link":
                    row(title: child.string("title"), index: index) {
                        if let target = child.string("target"), let url = URL(string: target) {
                            Link(child.string("text") ?? target, destination: url)
                                .font(metrics.typography.rowTitle)
                        } else {
                            Text(child.string("text") ?? "").font(metrics.typography.rowTitle)
                        }
                    }
                case "Detail.Metadata.TagList":
                    row(title: child.string("title"), index: index) {
                        ExtensionTagListView(tags: child.children, assetsPath: assetsPath)
                    }
                case "Detail.Metadata.Separator":
                    Rectangle().fill(Theme.Colors.separator).frame(height: 1)
                default:
                    EmptyView()
                }
            }
        }
    }

    /// `text` 可以是字符串或 `{value, color}`；Label 也可以只带有图标。
    private func labelText(_ node: RenderNode) -> String {
        ExtensionAccessoriesView.label(node.props["text"])
            ?? node.date("text").map { $0.formatted(date: .abbreviated, time: .shortened) }
            ?? ""
    }

    @ViewBuilder
    private func row<Content: View>(
        title: String?, index: Int, @ViewBuilder content: () -> Content
    ) -> some View {
        if inline {
            HStack(alignment: .firstTextBaseline, spacing: metrics.spacing.xl) {
                Text(title ?? "")
                    .font(metrics.typography.rowTitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                content()
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, metrics.spacing.md)
            .padding(.vertical, metrics.spacing.xs)
            .frame(minHeight: metrics.scaled(Self.inlineRowHeight))
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.menu, style: .continuous)
                    .fill(index.isMultiple(of: 2) ? ExtensionColors.detailCardFill : .clear))
        } else {
            VStack(alignment: .leading, spacing: 2) {
                if let title, !title.isEmpty {
                    Text(title)
                        .font(metrics.typography.sectionHeader)
                        .foregroundStyle(.secondary)
                }
                content()
            }
        }
    }
}

private struct ExtensionTagListView: View {

    @Environment(\.metrics) private var metrics
    @Environment(\.isDarkAppearance) private var isDark
    let tags: [RenderNode]
    let assetsPath: String?

    var body: some View {
        // 这里必须换行：元数据标签列表常常比面板还宽。
        FlowLayout(spacing: metrics.spacing.xs) {
            ForEach(tags) { tag in
                let color =
                    ExtensionImage.color(tag.props["color"], isDark: isDark) ?? Theme.Colors.textSecondary
                HStack(spacing: 3) {
                    if let icon = tag.props["icon"] {
                        ExtensionIconView(
                            resolved: ExtensionImage.resolve(icon, assetsPath: assetsPath, isDark: isDark),
                            size: 12)
                    }
                    Text(tag.string("text") ?? "")
                        .font(metrics.typography.rowTrailing)
                }
                .foregroundStyle(color)
                .padding(.horizontal, metrics.spacing.xs)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(color.opacity(0.16))
                )
            }
        }
    }
}

/// 从左到右的换行布局。SwiftUI 没有内置换行，而标签列表需要。
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    /// 计算换行布局在给定宽度下所需的尺寸。
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var total = CGSize(width: 0, height: 0)
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > width {
                total.width = max(total.width, rowWidth)
                total.height += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        total.width = max(total.width, rowWidth)
        total.height += rowHeight
        return total
    }

    /// 将子视图按行依次放置到给定区域内。
    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// 行内样式由 `AttributedString` 处理；块级结构在此布局。
struct ExtensionMarkdownView: View {
    @Environment(\.metrics) private var metrics
    let markdown: String

    /// Markdown 的块级元素类型。
    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet(String)
        case numbered(index: Int, text: String)
        case quote(String)
        case code(String)
        case rule
        case image(URL)
        case table([[String]])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            // 用位置作为 id，使动态图片在下一帧解码期间保留上一帧。
            ForEach(Array(Self.parse(markdown).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text):
                    Text(inline(text))
                        .font(.system(size: headingSize(level), weight: .semibold))
                        .padding(.top, metrics.spacing.xs)
                case .paragraph(let text):
                    Text(inline(text))
                        .font(metrics.typography.rowTitle)
                        .textSelection(.enabled)
                case .bullet(let text):
                    HStack(alignment: .top, spacing: metrics.spacing.sm) {
                        Text("•").foregroundStyle(.secondary)
                        Text(inline(text)).font(metrics.typography.rowTitle)
                    }
                case .numbered(let index, let text):
                    HStack(alignment: .top, spacing: metrics.spacing.sm) {
                        Text("\(index).").foregroundStyle(.secondary).monospacedDigit()
                        Text(inline(text)).font(metrics.typography.rowTitle)
                    }
                case .quote(let text):
                    HStack(spacing: metrics.spacing.sm) {
                        Rectangle().fill(Theme.Colors.separator).frame(width: 2)
                        Text(inline(text))
                            .font(metrics.typography.rowTitle)
                            .foregroundStyle(.secondary)
                    }
                case .code(let text):
                    ScrollView(.horizontal) {
                        Text(text)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(metrics.spacing.sm)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: metrics.radius.menu, style: .continuous)
                            .fill(ExtensionColors.detailCardFill)
                    )
                    .hideNativeScrollers()
                case .rule:
                    Rectangle().fill(Theme.Colors.separator).frame(height: 1)
                case .image(let url):
                    ExtensionMarkdownImage(url: url)
                case .table(let rows):
                    Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                        ForEach(rows.indices, id: \.self) { r in
                            GridRow {
                                ForEach(rows[r].indices, id: \.self) { c in
                                    Text(inline(rows[r][c])).fontWeight(r == 0 ? .semibold : nil)
                                        .padding(.vertical, metrics.spacing.lg)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background(r == 0 ? ExtensionColors.detailCardFill : .clear)
                                        .border(Theme.Colors.separator, width: 0.5)
                                }
                            }
                        }
                    }
                    .font(metrics.typography.rowTitle).monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 按标题层级返回字号。
    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 20
        case 2: return 17
        case 3: return 15
        default: return 14
        }
    }

    /// 把行内 Markdown 文本解析为 AttributedString（仅行内语法，保留空白）。
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    /// 把 Markdown 源码解析为块级元素数组（标题、段落、列表、引用、代码、分隔线、图片、表格）。
    private static func parse(_ source: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var fence: [String]?
        var numberedIndex = 0
        var table: [[String]] = []

        /// 提交累积的段落/表格块。
        func flushParagraph() {
            if !table.isEmpty { blocks.append(.table(table)); table.removeAll() }
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }

        for rawLine in source.replacingOccurrences(of: "\r\n", with: "\n").split(
            separator: "\n", omittingEmptySubsequences: false)
        {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if let body = fence {
                    blocks.append(.code(body.joined(separator: "\n")))
                    fence = nil
                } else {
                    flushParagraph()
                    fence = []
                }
                continue
            }
            if fence != nil {
                fence?.append(line)
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
                numberedIndex = 0
                continue
            }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.rule)
                continue
            }
            if trimmed.hasPrefix("|") {
                if !paragraph.isEmpty { flushParagraph() }
                let row = trimmed.replacingOccurrences(
                    of: #"(?<!\\)((?:\\\\)*)\\\|"#, with: "$1\u{0}", options: .regularExpression)
                let cells = row.split(separator: "|", omittingEmptySubsequences: false).dropFirst()
                    .dropLast(row.hasSuffix("|") ? 1 : 0)
                    .map {
                        $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\u{0}", with: "|")
                    }
                if cells.allSatisfy({ $0.contains("-") && $0.allSatisfy(":-".contains) }) { continue }
                table.append(cells)
                continue
            }
            // 独立成行的图片是 AttributedString 无法内联展示的唯一块。
            if let url = standaloneImageURL(trimmed) {
                flushParagraph()
                blocks.append(.image(url))
                continue
            }
            if trimmed.hasPrefix("#") {
                flushParagraph()
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let text = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: min(level, 4), text: text))
                continue
            }
            if trimmed.hasPrefix("> ") {
                flushParagraph()
                blocks.append(.quote(String(trimmed.dropFirst(2))))
                continue
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flushParagraph()
                blocks.append(.bullet(String(trimmed.dropFirst(2))))
                continue
            }
            if let match = trimmed.firstMatch(ofNumberedList: ()) {
                flushParagraph()
                numberedIndex += 1
                blocks.append(.numbered(index: numberedIndex, text: match))
                continue
            }
            paragraph.append(trimmed)
        }
        if let body = fence { blocks.append(.code(body.joined(separator: "\n"))) }
        flushParagraph()
        return blocks
    }

    /// 识别独立成行的图片（`![](url)` 或 `<img src>`），仅接受 http/https 或 data scheme，否则返回 nil。
    private static func standaloneImageURL(_ line: String) -> URL? {
        let target: String
        if line.hasPrefix("<img"),
            let tag = line.wholeMatch(of: #/<img(?:\s[^>]*?)?\ssrc=["']([^"']+)["'][^>]*>/#)
        {
            target = String(tag.1)
        } else {
            guard line.hasPrefix("!["), let open = line.lastIndex(of: "("), line.hasSuffix(")") else {
                return nil
            }
            let inner = line[line.index(after: open)..<line.index(before: line.endIndex)]
            target = inner.split(separator: " ").first.map(String.init) ?? String(inner)
        }
        guard let url = URL(string: target), let scheme = url.scheme,
            scheme.hasPrefix("http") || scheme == "data"
        else { return nil }
        return url
    }
}

extension String {
    /// `1. text` → `text`，用于识别有序列表。
    fileprivate func firstMatch(ofNumberedList: Void) -> String? {
        let digits = prefix(while: \.isNumber)
        guard !digits.isEmpty else { return nil }
        let rest = dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return String(rest.dropFirst(2))
    }
}

/// Detail Markdown 中的图片，按自身尺寸或 URL 指定的尺寸显示。
private struct ExtensionMarkdownImage: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.isDarkAppearance) private var isDark
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Group {
                    if image.isAnimated {
                        AnimatedImageView(image: image)
                    } else {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    }
                }
                .frame(
                    maxWidth: maxWidth ?? (size == nil ? image.size.width : .infinity), maxHeight: maxHeight
                )
                .clipShape(RoundedRectangle(cornerRadius: metrics.radius.menu, style: .continuous))
                .frame(maxWidth: .infinity)
            } else {
                RoundedRectangle(cornerRadius: metrics.radius.menu, style: .continuous)
                    .fill(ExtensionColors.detailCardFill)
                    .frame(height: 120)
            }
        }
        // 以外观模式作为键：内联 SVG 的配色在解码时解析，而非由 URL 决定。
        .task(id: ExtensionImage.LoadKey(source: source, isDark: isDark)) {
            // 远端加载较慢时，期间不得显示上一行的图片。
            if url.scheme != "data" { image = nil }
            let loaded =
                url.scheme == "data"
                ? await ExtensionIconCache.loadInlineAsync(
                    url, palette: ExtensionImage.svgPalette(isDark: isDark))
                : await ExtensionIconCache.loadRemoteAsync(url, asIcon: false)
            if !Task.isCancelled { image = loaded }
        }
    }

    /// 图片来源：内联 data URL 或远端 URL。
    private var source: ExtensionImage.Source {
        url.scheme == "data" ? .inline(url) : .remote(url)
    }

    /// 从 URL 片段解析出的目标尺寸。
    private var size: ExtensionImageSize? { ExtensionImageSize(url: url) }

    /// 目标宽度上限（若 URL 指定）。
    private var maxWidth: CGFloat? { size?.width.map { CGFloat($0) } }

    /// 目标高度上限，未指定则为无限。
    private var maxHeight: CGFloat { size?.height.map { CGFloat($0) } ?? .infinity }
}
