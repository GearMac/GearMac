// 文件职责：渲染聊天会话记录，按消息列出气泡，并处理尾部跟随、查找锚点滚动、来源与使用量展示。
// 分层：UI；只负责展示与滚动交互，不发起网络请求。
import AppKit
import SwiftUI

/// 聊天查找的命中集合与当前要展示的那一处；会话记录据此标记命中并滚动过去。
struct ChatFindHighlight: Equatable {
    let query: String
    let matches: Set<UUID>
    let current: ChatFindOccurrence?
}

/// 会话记录绘制的位置：palette 的滚动样式按它自身的悬浮条尺寸度量。
enum ChatSurface {
    case palette
    case window
}

/// 聊天会话记录视图：按消息渲染气泡，处理尾部跟随、查找锚点滚动与使用量展示。
struct ChatTranscriptView: View {

    @Environment(\.metrics) private var metrics
    let messages: [ChatMessage]
    let status: String?
    let usage: AIUsage?
    let surface: ChatSurface
    /// 最后一条回复完成后提供；没有空间承载它的界面为 nil。
    var onRegenerate: (() -> Void)?
    /// 用最后一条回复的某个候选项作答；为 nil 时不展示候选项。
    var onChoose: ((String) -> Void)?
    var find: ChatFindHighlight?
    /// 读者向上滚动时置为 false，使流式回复不再把视图拖回底部。
    @State private var followsTail = true

    /// 小于该位移的反向移动视为惯性回弹，而非读者主动滚动。
    private static let deliberateScroll: CGFloat = 2

    /// 读者当前的位置以及是否已到底；不断增长的回复会自行把底部向后推移。
    private struct ScrollMark: Equatable {
        var offset: CGFloat
        var atEnd: Bool
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // 不使用懒加载：每次锚点跳转与到底判定都要测量估算高度
                VStack(spacing: metrics.spacing.xl) {
                    ForEach(messages) { message in
                        let isLast = message.id == messages.last?.id
                        ChatMessageView(
                            message: message,
                            status: isLast ? status : nil,
                            onRegenerate: isLast && message.role == .assistant
                                ? onRegenerate : nil,
                            // 只有最新一条回复的候选项仍然有效。
                            onChoose: isLast && message.state == .complete ? onChoose : nil
                        )
                        .equatable()
                        .environment(\.chatTextHighlight, highlight(for: message.id))
                        .id(message.id)
                    }
                    if let total = usage?.totalTokens {
                        Text("\(total.formatted()) tokens")
                            .font(metrics.typography.rowTrailing)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    Color.clear
                        .frame(height: metrics.spacing.xxs)
                        .id("ai-transcript-tail")
                }
                .padding(.horizontal, metrics.spacing.xxl)
                .padding(.top, metrics.spacing.xl)
                .padding(
                    .bottom,
                    surface == .palette ? metrics.spacing.chatTranscriptBottom : metrics.spacing.xl
                )
                .lineSpacing(metrics.spacing.chatLine)
                // 窗口宽度不受限；正文超过该宽度后就不再易读。
                .frame(maxWidth: surface == .window ? Theme.Size.aiChatReadingWidth : nil)
                .frame(maxWidth: .infinity)
            }
            .modifier(TranscriptScrollChrome(surface: surface))
            // 重新打开的聊天从最新消息开始；其它锚点角色会与读者的滚动操作冲突。
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .onScrollGeometryChange(for: ScrollMark.self) { geometry in
                ScrollMark(
                    offset: geometry.contentOffset.y,
                    // 偏移静止在 `-insetTop`，因此底部判定要在偏移基础上加上可视高度与内边距
                    atEnd: geometry.contentOffset.y + geometry.containerSize.height
                        + geometry.contentInsets.top
                        >= geometry.contentSize.height - metrics.spacing.chatFollowTailSlack)
            } action: { old, new in
                // 偏移是各设备都会给出的唯一信号；优先判定到底
                if new.atEnd {
                    followsTail = true
                } else if new.offset < old.offset - Self.deliberateScroll {
                    followsTail = false
                }
            }
            .onChange(of: messages.count) { follow(proxy, always: true) }
            .onChange(of: find?.current) { _, current in
                guard current != nil else { return }
                followsTail = false
                // 下一轮：承载命中项的文本会在同一次更新中带上锚点。
                Task { @MainActor in
                    withAnimation(.easeOut(duration: Theme.Duration.chatFooter)) {
                        proxy.scrollTo(ChatTextHighlight.currentAnchor, anchor: .center)
                    }
                }
            }
            .onChange(of: messages) { follow(proxy, always: false) }
            .onChange(of: usage) { follow(proxy, always: false) }
            .overlay(alignment: .bottom) {
                ResumeFollowingButton {
                    followsTail = true
                    follow(proxy, always: true)
                }
                .padding(.bottom, metrics.spacing.lg)
                .opacity(followsTail ? 0 : 1)
                .allowsHitTesting(!followsTail)
                .animation(.easeOut(duration: Theme.Duration.chatFooter), value: followsTail)
            }
        }
    }

    /// 为带有查找命中的消息构造高亮状态，并标出当前定位项。
    private func highlight(for id: UUID) -> ChatTextHighlight? {
        guard let find, find.matches.contains(id) else { return nil }
        return ChatTextHighlight(
            query: find.query, current: find.current?.messageID == id ? find.current : nil)
    }

    /// 已发送的消息总是滚入视野；正在增长的回复仅当读者位于末尾时才跟随。
    private func follow(_ proxy: ScrollViewProxy, always: Bool) {
        guard always || followsTail else { return }
        proxy.scrollTo("ai-transcript-tail", anchor: .bottom)
    }
}

/// 渐隐与细滚动条按 palette 的悬浮条调校；窗口则使用原生滚动。
private struct TranscriptScrollChrome: ViewModifier {
    let surface: ChatSurface

    func body(content: Content) -> some View {
        switch surface {
        case .palette: content.edgeDissolve().thinScrollbar()
        case .window: content
        }
    }
}

/// 快速回复会超过正滚向它的读者，因此这里只是请求跳到末尾，而非持续追随。
private struct ResumeFollowingButton: View {
    @Environment(\.metrics) private var metrics
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Jump to Latest", systemImage: "arrow.down")
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.horizontal, metrics.spacing.lg)
                .padding(.vertical, metrics.spacing.sm)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.Colors.border))
        }
        .buttonStyle(.plain)
    }
}

/// 遵循 Equatable，使一次刷新只重绘发生变化的回复；闭包只按是否存在来比较。
private struct ChatMessageView: View, @MainActor Equatable {

    @Environment(\.metrics) private var metrics
    let message: ChatMessage
    let status: String?
    let onRegenerate: (() -> Void)?
    let onChoose: ((String) -> Void)?
    @Environment(\.chatTextHighlight) private var highlight

    @State private var hovered = false

    /// 围栏仅用于承载候选项，绝非正文：它不会出现在文本与复制内容中。
    private var parts: (text: String, choices: [String]) {
        message.role == .assistant ? ChatChoices.split(message.text) : (message.text, [])
    }

    /// 仅在回复完成后读取：尚未流式输出完整的链接还不能算来源。
    private var references: [ChatReference] {
        guard message.role == .assistant, message.state != .streaming else { return [] }
        return ChatReferences.extract(from: parts.text)
    }

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: metrics.spacing.xxl) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: metrics.spacing.xxs) {
                content
                if message.state != .streaming { footer }
            }
            .contentShape(Rectangle())
            .onHover { isHovered in
                if isHovered {
                    withAnimation(.easeOut(duration: Theme.Duration.chatFooter)) {
                        hovered = true
                    }
                } else {
                    hovered = false
                }
            }
            if message.role == .assistant { Spacer(minLength: metrics.spacing.xxl) }
        }
    }

    /// 按静止状态完成布局，仅做淡入，因此悬停不会引起会话记录重排。
    private var footer: some View {
        HStack(spacing: metrics.spacing.sm) {
            if message.role == .user { timestamp }
            ChatCopyButton(text: parts.text)
            if let onRegenerate { RegenerateButton(action: onRegenerate) }
            if message.role == .assistant { timestamp }
        }
        .opacity(hovered ? 1 : 0)
        // 回复的页脚与其文本贴合同一 `sm` 边距。
        .padding(.horizontal, message.role == .user ? metrics.spacing.md : metrics.spacing.sm)
    }

    private var timestamp: some View {
        Text(message.sentAt.formatted(date: .omitted, time: .shortened))
            .font(metrics.typography.keyCap)
            .foregroundStyle(Theme.Colors.textTertiary)
    }

    /// 消息主体：空流式消息显示进度指示，否则渲染气泡内容。
    @ViewBuilder private var content: some View {
        if message.text.isEmpty, message.searches.isEmpty, message.toolUses.isEmpty,
            message.reasoning.isEmpty, message.state == .streaming
        {
            HStack(spacing: metrics.spacing.sm) {
                ProgressView().controlSize(.small)
                if let status { Text(status).foregroundStyle(.secondary) }
            }
            .padding(metrics.spacing.md)
        } else {
            bubbleContent
                .font(metrics.typography.rowTitle)
                .foregroundStyle(message.state == .failed ? Theme.Colors.destructive : .primary)
                .textSelection(.enabled)
                // 用户气泡因为有填充色而额外缩进；回复则要避开左侧指示箭头
                .padding(.horizontal, message.role == .user ? metrics.spacing.xl : metrics.spacing.sm)
                .padding(.vertical, metrics.spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                        .fill(message.role == .user ? Theme.Colors.controlSurface : Color.clear)
                )
        }
    }

    /// 气泡内容：依次排布图片、文档与正文、搜索、工具、思考片段。
    private var bubbleContent: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: metrics.spacing.sm) {
            if !message.images.isEmpty {
                // 比堆栈本身的节奏更宽：两块 96pt 图块用 `sm` 间距会糊成一片。
                HStack(spacing: metrics.spacing.xl) {
                    ForEach(message.images, id: \.self) { image in
                        ChatImageThumbnail(image: image, edge: metrics.size.chatImageThumb)
                    }
                }
            }
            if !message.documents.isEmpty {
                HStack(spacing: metrics.spacing.md) {
                    ForEach(message.documents, id: \.self) { document in
                        ChatDocumentChip(document: document)
                    }
                }
            }
            if !message.text.isEmpty || !message.searches.isEmpty || !message.toolUses.isEmpty
                || !message.reasoning.isEmpty
            {
                rendered
            }
        }
    }

    /// 只有回复按 markdown 渲染——用户输入的内容原样回显。
    @ViewBuilder private var rendered: some View {
        if message.role == .assistant {
            let references = references
            let segments = message.segments
            VStack(alignment: .leading, spacing: metrics.spacing.lg) {
                ForEach(Array(segments.enumerated()), id: \.offset) { offset, segment in
                    Group {
                        switch segment {
                        case .text(let text):
                            ChatMarkdownText(
                                blocks: MarkdownBlock.parse(
                                    ChatChoices.split(text).text,
                                    midStream: message.isArriving(segmentAt: offset, of: segments.count)),
                                failed: message.state == .failed)
                        case .search(let search):
                            ChatSearchRow(search: search)
                        case .tools(let uses):
                            ChatToolRun(uses: uses)
                        case .reasoning(let block):
                            ChatReasoningBlock(
                                block: block,
                                isThinking: message.state == .streaming && block.duration == nil)
                        }
                    }
                    .environment(\.chatFindPath, [offset])
                }
                if let onChoose, !parts.choices.isEmpty {
                    ChatSuggestionChips(choices: parts.choices, onChoose: onChoose)
                }
                if !references.isEmpty { ChatSourcesView(references: references) }
            }
            .environment(\.chatCitations, ChatReferences.numbers(for: references))
        } else {
            Text(highlight?.attributed(message.text, leaf: [0]) ?? AttributedString(message.text))
                .findAnchor(highlight, leaf: [0])
        }
    }
}

extension ChatMessageView {
    /// 只比较消息与状态以及闭包是否存在，避免每次刷新都判定为变化。
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.message == rhs.message && lhs.status == rhs.status
            && (lhs.onRegenerate == nil) == (rhs.onRegenerate == nil)
            && (lhs.onChoose == nil) == (rhs.onChoose == nil)
    }
}

/// 回复中链接到的页面，像带引用的回答列出出处那样汇总在其下方。
private struct ChatSourcesView: View {
    @Environment(\.metrics) private var metrics
    let references: [ChatReference]

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            Text("Sources")
                .font(metrics.typography.rowTrailing.weight(.semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
            ChatFlowLayout(spacing: metrics.spacing.sm) {
                ForEach(Array(references.enumerated()), id: \.element) { index, reference in
                    ChatSourceChip(index: index + 1, reference: reference)
                }
            }
        }
        .padding(.top, metrics.spacing.xs)
    }
}

/// 单条来源的胶囊按钮，点击用系统默认应用打开该 URL。
private struct ChatSourceChip: View {
    @Environment(\.metrics) private var metrics
    let index: Int
    let reference: ChatReference

    var body: some View {
        Button {
            NSWorkspace.shared.open(reference.url)
        } label: {
            HStack(spacing: metrics.spacing.xs) {
                Text("\(index)")
                    .font(metrics.typography.keyCap)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textTertiary)
                Text(reference.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: Theme.Size.chatSourceTitle, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                if reference.title != reference.host {
                    Text(reference.host)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
            .font(metrics.typography.rowTrailing)
            .padding(.horizontal, metrics.spacing.xs)
        }
        .glassButtonStyle()
        .help(reference.url.absoluteString)
        .accessibilityLabel("Source \(index): \(reference.title), \(reference.host)")
    }
}

/// 「重新生成」按钮。
private struct RegenerateButton: View {
    @Environment(\.metrics) private var metrics
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(metrics.typography.keyCap)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: metrics.size.chatMessageAction, height: metrics.size.chatMessageAction)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Regenerate Response")
        .accessibilityLabel("Regenerate Response")
    }
}

/// 一段思考过程：默认折叠、一次点击即可展开，并且会被查找展开。
private struct ChatReasoningBlock: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.chatTextHighlight) private var highlight
    @Environment(\.chatFindPath) private var path
    let block: ChatReasoning
    let isThinking: Bool
    @State private var expanded = false

    /// 折叠标题：思考中、未记录时长或已思考的秒数。
    private var title: String {
        if isThinking { return "Thinking…" }
        guard let duration = block.duration else { return "Thoughts" }
        return "Thought for \(max(1, Int(duration.rounded())))s"
    }

    /// 折叠块内的命中会被找到却不可见，因此查找会将其展开。
    private var isOpen: Bool {
        expanded
            || highlight.map {
                block.text.range(of: $0.query, options: [.caseInsensitive, .diacriticInsensitive])
                    != nil
            } == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            Button {
                withAnimation(.easeOut(duration: Theme.Duration.chatFooter)) { expanded.toggle() }
            } label: {
                HStack(spacing: metrics.spacing.xs) {
                    if isThinking {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "brain")
                            .symbolRenderingMode(.hierarchical)
                    }
                    Text(title)
                    Image(systemName: "chevron.right")
                        .font(metrics.typography.keyCap)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isOpen ? "Hide reasoning" : "Show reasoning")
            if isOpen {
                Text(highlight?.attributed(block.text, leaf: path) ?? AttributedString(block.text))
                    .findAnchor(highlight, leaf: path)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, metrics.spacing.md)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Theme.Colors.border)
                            .frame(width: metrics.size.markdownQuoteBar)
                    }
                    .transition(.opacity)
            }
        }
    }
}

/// 已发送的文档只显示名称：其字节发送给了模型，并未写入会话记录正文。
private struct ChatDocumentChip: View {
    @Environment(\.metrics) private var metrics
    let document: AIDocument

    private var isPDF: Bool { document.mimeType == AIAttachmentPolicy.pdfMIMEType }

    var body: some View {
        HStack(spacing: metrics.spacing.xs) {
            Image(systemName: isPDF ? "doc.richtext" : "doc.plaintext")
                .font(metrics.typography.chip)
                .symbolRenderingMode(.hierarchical)
            Text(document.name)
                .font(metrics.typography.chip)
                .lineLimit(1)
        }
        .foregroundStyle(Theme.Colors.textSecondary)
        .padding(.horizontal, metrics.spacing.sm)
        .padding(.vertical, metrics.spacing.xxs)
        .background(Capsule().fill(Theme.Colors.controlSurface))
        .accessibilityLabel("Attached file \(document.name)")
    }
}

/// 每张图片只在渲染路径之外解码一次；流式会话记录每次刷新都会重绘。
struct ChatImageThumbnail: View {
    @Environment(\.metrics) private var metrics
    let image: AIImage
    let edge: CGFloat
    @State private var decoded: NSImage?

    var body: some View {
        Group {
            if let decoded {
                Image(nsImage: decoded)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.clear
            }
        }
        .frame(width: edge, height: edge)
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous))
        .task(id: image) { decoded = NSImage(data: image.data) }
    }
}

/// 连续无间隔的调用：进行中时显示当前一个，完成后显示一个可展开查看每次调用的计数。
private struct ChatToolRun: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let uses: [ChatToolUse]
    @State private var isExpanded = false

    var body: some View {
        if uses.count == 1, let use = uses.first {
            ChatToolRow(use: use)
        } else {
            VStack(alignment: .leading, spacing: metrics.spacing.sm) {
                if let running = uses.runningCall {
                    ChatToolRow(use: running)
                } else {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        HStack(spacing: metrics.spacing.sm) {
                            Image(
                                systemName: uses.failedCount > 0
                                    ? "exclamationmark.triangle" : "wrench.and.screwdriver"
                            )
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(
                                uses.failedCount > 0
                                    ? Theme.Colors.destructive : Theme.Colors.textSecondary)
                            Text(uses.completedLabel)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(metrics.typography.disclosure)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                                .animation(
                                    reduceMotion ? nil : Theme.MenuMotion.chevronAnimation,
                                    value: isExpanded)
                        }
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(uses.completedLabel)
                    .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                    if isExpanded {
                        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
                            ForEach(uses, id: \.callID) { use in
                                ChatToolRow(use: use)
                            }
                        }
                        .padding(.leading, metrics.spacing.xxl)
                    }
                }
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: Theme.Duration.chatFooter), value: uses
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: Theme.Duration.chatFooter), value: isExpanded)
        }
    }
}

/// 回复中的一次工具调用；沿用搜索行的排版语法，只是图标不同。
private struct ChatToolRow: View {
    @Environment(\.metrics) private var metrics
    let use: ChatToolUse

    var body: some View {
        HStack(spacing: metrics.spacing.sm) {
            switch use.state {
            case .running:
                ProgressView().controlSize(.small)
            case .completed:
                glyph("wrench.and.screwdriver")
            case .failed:
                glyph("exclamationmark.triangle")
                    .foregroundStyle(Theme.Colors.destructive)
            }
            Text(use.label)
                .font(metrics.typography.rowTrailing)
                .lineLimit(1)
        }
        .foregroundStyle(Theme.Colors.textSecondary)
        .animation(.easeOut(duration: Theme.Duration.chatFooter), value: use.state)
    }

    /// 按其所在行的字体设定尺寸，与旁边的搜索行一致，而非用符号点数。
    private func glyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(metrics.typography.rowTrailing)
            .symbolRenderingMode(.hierarchical)
    }
}

/// 回复中的一次网页搜索：进行中时实时展示，完成后成为查询记录。
private struct ChatSearchRow: View {
    @Environment(\.metrics) private var metrics
    let search: ChatSearch

    var body: some View {
        HStack(spacing: metrics.spacing.sm) {
            if search.isComplete {
                Image(systemName: "globe")
                    .font(metrics.typography.rowTrailing)
                    .symbolRenderingMode(.hierarchical)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(search.isComplete ? "Searched web" : "Searching web")
                .font(metrics.typography.rowTrailing)
            if let query = search.query, !query.isEmpty {
                Text("· \(query)")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(Theme.Colors.textSecondary)
        .animation(.easeOut(duration: Theme.Duration.chatFooter), value: search.isComplete)
    }
}
