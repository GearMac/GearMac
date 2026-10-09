// 文件职责：把渲染后的 Markdown 文本以 AppKit 文本视图展示（可选中、可复制），并处理查找锚点与代码块头部。
// 分层：UI（AppKit + SwiftUI 桥接）；只读展示，实际排版由 ChatMarkdownRenderer 完成。
import AppKit
import SwiftUI

/// 每个片段用一个 AppKit 文本视图，因为 SwiftUI 的 `Text` 只能在同一段落内选择。
struct ChatMarkdownText: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.chatTextHighlight) private var highlight
    @Environment(\.chatCitations) private var citations
    @Environment(\.chatFindPath) private var path
    let blocks: [MarkdownBlock]
    var failed = false

    /// 当前查找匹配在这段文本中的位置，便于对话记录滚动到它。
    @State private var currentMatch: CGRect?

    private var holdsCurrentMatch: Bool {
        guard let leaf = highlight?.current?.leaf else { return false }
        return leaf.starts(with: path)
    }

    var body: some View {
        ChatTextRepresentable(
            source: ChatMarkdownSource(
                blocks: blocks, highlight: highlight, citations: citations, prefix: path,
                failed: failed, metrics: metrics)
        ) { rect in
            if rect != currentMatch { currentMatch = rect }
        }
        .overlay(alignment: .topLeading) {
            if holdsCurrentMatch, let rect = currentMatch {
                Color.clear
                    .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                    .offset(x: rect.minX, y: rect.minY)
                    .id(ChatTextHighlight.currentAnchor)
            }
        }
    }
}

/// 把 ChatMarkdownSource 桥接到 ChatSelectableTextView 的 NSViewRepresentable。
private struct ChatTextRepresentable: NSViewRepresentable {
    let source: ChatMarkdownSource
    let onCurrentMatch: (CGRect?) -> Void

    func makeNSView(context: Context) -> ChatSelectableTextView { ChatSelectableTextView() }

    func updateNSView(_ view: ChatSelectableTextView, context: Context) {
        view.onCurrentMatch = onCurrentMatch
        view.show(source)
    }

    /// 宽度开放时请求理想尺寸，与 `Text` 的答案一致：每个段落各占一行。
    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView view: ChatSelectableTextView, context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return view.measure(width: nil) }
        return CGSize(width: width, height: view.measure(width: width).height)
    }
}

/// 只读且无背景；它按自身 frame 换行，滚动交给外层对话记录。
final class ChatSelectableTextView: NSTextView {
    var onCurrentMatch: ((CGRect?) -> Void)?
    private var source: ChatMarkdownSource?
    private var rendered: ChatRenderedText?
    private var headers: [ChatCodeHeader] = []
    private var reportedMatch: CGRect?
    /// 对同一存储再做一套布局，使 SwiftUI 的尺寸探测不会重新换行已绘制的布局。
    private let measurer = NSLayoutManager()
    private let measuringContainer = NSTextContainer(size: .zero)
    private var measured: (width: CGFloat?, size: CGSize)?

    /// 搭建两套布局（绘制用与测量用）并配置为只读、可选中、无背景。
    init() {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(
            size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        measuringContainer.lineFragmentPadding = 0
        measurer.addTextContainer(measuringContainer)
        storage.addLayoutManager(measurer)
        super.init(frame: .zero, textContainer: container)
        isEditable = false
        isSelectable = true
        isRichText = true
        drawsBackground = false
        textContainerInset = .zero
        isVerticallyResizable = false
        isHorizontallyResizable = false
        allowsUndo = false
        linkTextAttributes = [.foregroundColor: NSColor.linkColor, .cursor: NSCursor.pointingHand]
    }

    /// AppKit 自身的指定初始化器；`NSTextView(frame:)` 会经由它调用。
    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 仅当来源变化时才重新渲染，使已完成的回复能保留其选中状态。
    func show(_ next: ChatMarkdownSource) {
        guard next != source else { return }
        source = next
        let output = ChatMarkdownRenderer(next).render()
        rendered = output
        measured = nil
        textStorage?.setAttributedString(output.string)
        layoutOverlays()
        needsDisplay = true
    }

    /// `nil` 表示理想宽度。SwiftUI 会反复请求同一宽度，因此缓存上一次的结果。
    func measure(width: CGFloat?) -> CGSize {
        if let measured, measured.width == width { return measured.size }
        measuringContainer.size = CGSize(
            width: width ?? .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        measurer.ensureLayout(for: measuringContainer)
        let used = measurer.usedRect(for: measuringContainer)
        let size = CGSize(width: ceil(used.width), height: ceil(used.height))
        measured = (width, size)
        return size
    }

    /// 公式在被复制、拖拽时以回复写下的 LaTeX 源码形式提供，而不是作为图片。
    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard let storage = textStorage else { return super.writeSelection(to: pboard, types: types) }
        let ranges = selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        let holdsMath = ranges.contains { range in
            var found = false
            storage.enumerateAttribute(ChatMarkdownRenderer.mathSource, in: range) { value, _, stop in
                found = value != nil
                stop.pointee = ObjCBool(found)
            }
            return found
        }
        guard holdsMath else { return super.writeSelection(to: pboard, types: types) }
        let copied = NSMutableAttributedString()
        for (index, range) in ranges.enumerated() {
            if index > 0 { copied.append(NSAttributedString(string: "\n")) }
            copied.append(Self.writingMathSource(storage.attributedSubstring(from: range)))
        }
        pboard.clearContents()
        return pboard.writeObjects([copied])
    }

    /// 把选区里的公式附件替换为其 LaTeX 源码文本，供复制使用。
    private static func writingMathSource(_ text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        let key = ChatMarkdownRenderer.mathSource
        let whole = NSRange(location: 0, length: result.length)
        result.enumerateAttribute(key, in: whole, options: .reverse) { value, range, _ in
            guard let source = value as? String else { return }
            var attributes = result.attributes(at: range.location, effectiveRange: nil)
            attributes[.attachment] = nil
            attributes[key] = nil
            let replacement = String(repeating: source, count: range.length)
            result.replaceCharacters(
                in: range, with: NSAttributedString(string: replacement, attributes: attributes))
        }
        return result
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutOverlays()
    }

    /// 代码块头部与查找锚点都放在已绘制的布局上，该布局会跟随 frame 变化。
    private func layoutOverlays() {
        guard frame.width > 0, let layout = layoutManager, let container = textContainer else {
            return
        }
        layout.ensureLayout(for: container)
        placeHeaders(in: layout)
        let match = rendered?.current.map { range in
            layout.boundingRect(
                forGlyphRange: layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil),
                in: container)
        }
        guard match != reportedMatch else { return }
        reportedMatch = match
        let report = onCurrentMatch
        // 放到这一轮之后：在 SwiftUI 布局过程中设置状态会被丢弃并产生警告。
        Task { @MainActor in report?(match) }
    }

    /// 依据绘制布局把每个代码块的语言/Copy 头部放到对应位置。
    private func placeHeaders(in layout: NSLayoutManager) {
        let blocks = rendered?.codeBlocks ?? []
        while headers.count > blocks.count { headers.removeLast().removeFromSuperview() }
        while headers.count < blocks.count {
            let header = ChatCodeHeader()
            addSubview(header)
            headers.append(header)
        }
        guard let metrics = source?.metrics else { return }
        for (header, block) in zip(headers, blocks) {
            header.show(code: block.code, language: block.language, metrics: metrics)
            let glyphs = layout.glyphRange(forCharacterRange: block.range, actualCharacterRange: nil)
            let box = layout.boundsRect(for: block.block, glyphRange: glyphs)
            let inset = metrics.spacing.xl
            header.frame = CGRect(
                x: box.minX + inset, y: box.minY + metrics.spacing.md,
                width: max(box.width - inset * 2, 0), height: ChatCodeHeader.height)
        }
    }
}

/// 代码块的语言标签与自身的 Copy 按钮，位于文本块在代码上方留出的条带中。
private final class ChatCodeHeader: NSView {
    static var height: CGFloat { ChatMarkdownRenderer.codeHeaderHeight }

    private let label = NSTextField(labelWithString: "")
    private let button = NSButton()
    private var code = ""
    private var reset: Task<Void, Never>?

    /// 配置语言标签与 Copy 按钮，并进入未复制状态。
    init() {
        super.init(frame: .zero)
        label.textColor = NSColor(Theme.Colors.textTertiary)
        label.lineBreakMode = .byTruncatingTail
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = NSColor(Theme.Colors.textSecondary)
        button.target = self
        button.action = #selector(copyCode)
        addSubview(label)
        addSubview(button)
        showIdle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    /// 设置该头部对应的代码与语言。
    func show(code: String, language: String?, metrics: InterfaceMetrics) {
        self.code = code
        label.stringValue = language ?? ""
        label.font = metrics.typography.textNSFont(.caption1)
    }

    override func layout() {
        super.layout()
        let side = Self.height
        button.frame = CGRect(x: bounds.width - side, y: 0, width: side, height: side)
        label.frame = CGRect(x: 0, y: 0, width: max(bounds.width - side * 2, 0), height: side)
    }

    /// 把按钮恢复为未复制的 Copy 图标与无障碍标签。
    private func showIdle() {
        button.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "Copy Code")
        button.setAccessibilityLabel("Copy Code")
    }

    /// 复制代码到剪贴板并显示对勾，稍后自动复位。
    @objc private func copyCode() {
        Paster.copyPlainText(code)
        button.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")
        button.setAccessibilityLabel("Copied")
        reset?.cancel()
        reset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Theme.Duration.copyFeedback))
            guard !Task.isCancelled else { return }
            self?.showIdle()
        }
    }
}
