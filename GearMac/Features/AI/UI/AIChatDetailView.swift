// 文件职责：AI Chat 窗口右侧详情区：会话转录、输入框（附件、联网搜索、模型与推理档位、上下文仪表）以及拖放提示。
// 分层：UI；状态与动作全部经 AIChatCoordinator，视图自身不持有会话数据。
import AppKit
import SwiftUI

/// 窗口右侧：当前打开的会话，及其下方的输入区。
struct AIChatDetailView: View {
    @Environment(AIChatCoordinator.self) private var coordinator
    @Environment(ChatFindState.self) private var find
    @State private var isDropTargeted = false
    @State private var showsContext = false

    private var chat: AIChatState { coordinator.chats.window }

    /// 上一条回复结束后的可选项；开始输入或再次发送即不再显示。
    private var suggestions: [String] {
        guard !chat.isStreaming, let last = chat.session.messages.last, last.role == .assistant,
            last.state == .complete
        else { return [] }
        return ChatChoices.split(last.text).choices
    }

    var body: some View {
        GeometryReader { geometry in
            pane(composerHeight: ChatComposerTextView.maximumHeight(in: geometry.size.height))
        }
        .animation(.easeOut(duration: Theme.Duration.tooltip), value: showsContext)
        .dropDestination(for: URL.self) { files, _ in
            coordinator.attach(files: files, to: chat)
            return true
        } isTargeted: {
            isDropTargeted = $0
        }
        .overlay {
            if isDropTargeted { dropHint }
        }
    }

    /// 详情区主体：转录内容在上、输入区在下，并在需要时叠加上下文卡片。
    private func pane(composerHeight: CGFloat) -> some View {
        // 采用堆叠而非浮层：转录区在输入区开始处结束，绝不会跑到其下方。
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // 叠在转录区自身的坐标系内，使上下文卡片不会跑到窗口之外。
                .overlay(alignment: .bottom) {
                    if showsContext {
                        HStack {
                            Spacer(minLength: 0)
                            ContextCard(report: coordinator.contextReport(for: chat))
                        }
                        .frame(maxWidth: Theme.Size.aiChatReadingWidth)
                        .padding(.horizontal, Theme.Spacing.xxl)
                        .padding(.bottom, Theme.Spacing.sm)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                    }
                }
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if !suggestions.isEmpty, chat.draft.isEmpty {
                    ChatSuggestionChips(choices: suggestions) { coordinator.send($0, in: chat) }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                AIChatComposer(
                    chat: chat, coordinator: coordinator, settings: coordinator.aiSettings,
                    maximumTextHeight: composerHeight, showsContext: $showsContext,
                    isDropTargeted: $isDropTargeted)
            }
            .frame(maxWidth: Theme.Size.aiChatReadingWidth)
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.bottom, Theme.Spacing.xxl)
            .padding(.top, Theme.Spacing.sm)
            .animation(.snappy, value: suggestions)
            .animation(.snappy, value: chat.draft.isEmpty)
        }
    }

    /// 会话为空时显示空状态，否则显示转录视图与查找计数。
    @ViewBuilder private var content: some View {
        if chat.session.messages.isEmpty {
            // 在 body 中读取，使 CLI 登录完成或提供方被启用能立刻反映出来。
            let unavailability = coordinator.availability(for: chat)
            AIEmptyState(
                message: chat.notice ?? unavailability,
                canConfigure: chat.notice != nil || unavailability != nil,
                onConfigure: coordinator.showSettings)
        } else {
            let occurrences = find.occurrences(in: chat.session.messages)
            ChatTranscriptView(
                messages: chat.session.messages, status: chat.liveStatus, usage: chat.usage,
                surface: .window,
                onRegenerate: chat.isStreaming ? nil : { coordinator.regenerate(in: chat) },
                find: find.isSearching
                    ? ChatFindHighlight(
                        query: find.needle, matches: Set(occurrences.map(\.messageID)),
                        current: find.currentOccurrence(in: occurrences))
                    : nil
            )
            // 切换聊天即换一套滚动状态：各自独立跟随尾部，打开时定位到最新一行。
            .id(chat.session.id)
            .overlay(alignment: .topTrailing) {
                if find.isSearching {
                    FindCounter(
                        position: occurrences.isEmpty
                            ? 0 : min(find.current, occurrences.count - 1) + 1,
                        count: occurrences.count,
                        step: { find.step($0, in: chat.session.messages) }
                    )
                    .padding(Theme.Spacing.md)
                }
            }
        }
    }

    /// 拖放文件到窗口时显示的虚线描边提示。
    private var dropHint: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .strokeBorder(
                Theme.Colors.dropTarget,
                style: StrokeStyle(lineWidth: Theme.Size.dropHintStroke, dash: [Theme.Size.dropHintDash])
            )
            .padding(Theme.Spacing.md)
            .allowsHitTesting(false)
    }
}

/// 在同一块 Liquid Glass 面板内自上而下排列：暂存文件、文本，以及本聊天的选项与发送按钮。
private struct AIChatComposer: View {
    let chat: AIChatState
    let coordinator: AIChatCoordinator
    let settings: AISettingsStore
    let maximumTextHeight: CGFloat
    @Binding var showsContext: Bool
    @Binding var isDropTargeted: Bool
    @State private var editor = ComposerTextViewHandle()

    /// 草稿非空或已暂存附件时才能发送。
    private var canSend: Bool {
        !chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !chat.pendingAttachments.isEmpty
    }

    var body: some View {
        @Bindable var chat = chat
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if !chat.session.messages.isEmpty, let notice = chat.notice {
                Label(notice, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.sm)
            }
            chips
            ZStack(alignment: .topLeading) {
                if chat.draft.isEmpty {
                    Text("Ask anything…")
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
                ChatComposerTextView(
                    text: $chat.draft, focusKey: chat.session.id,
                    maximumTextHeight: maximumTextHeight, handle: editor,
                    isFileDragTargeted: $isDropTargeted,
                    onDropFiles: { coordinator.attach(files: $0, to: chat) },
                    onInvalidate: { coordinator.dictation.cancel(in: $0) }, onSubmit: submit)
            }
            // 文本的左边缘对齐 + 号字形，后者居中于自己的悬停方块中。
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.top, Theme.Spacing.xs)
            controls
        }
        .padding(Theme.Spacing.md)
        .background {
            Color.clear.glassSurface(
                in: RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous))
        }
        .animation(.snappy, value: settings.webSearchEnabled)
    }

    /// 输入框上方的 chip 区：@ 服务器与暂存附件。
    @ViewBuilder private var chips: some View {
        let addressed = coordinator.addressedServer(in: chat.draft)
        if !chat.pendingAttachments.isEmpty || addressed != nil {
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Spacing.sm) {
                    if let addressed {
                        ComposerChip(symbol: "wrench.and.screwdriver", label: "@\(addressed.slug)")
                    }
                    ForEach(chat.pendingAttachments) { attachment in
                        AttachmentChip(attachment: attachment) {
                            coordinator.removeAttachment(attachment.id, in: chat)
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    /// 在模型名称开始被截断之前，先让搜索按钮放弃文字标签。
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            controlRow(compactSearch: false)
            controlRow(compactSearch: true)
        }
    }

    /// 渲染一行输入区控件。
    private func controlRow(compactSearch: Bool) -> some View {
        let searches = coordinator.capabilities(for: chat).webSearch
        return HStack(spacing: Theme.Spacing.xxs) {
            AIAddMenu(chat: chat, coordinator: coordinator, settings: settings, offersSearch: searches)
            if searches, settings.webSearchEnabled {
                WebSearchPill(settings: settings, isCompact: compactSearch)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            Spacer(minLength: Theme.Spacing.md)
            AIModelPicker(chat: chat, selected: coordinator.model(for: chat), coordinator: coordinator)
                .layoutPriority(-1)
            AIReasoningPicker(chat: chat, coordinator: coordinator)
            ContextGauge(
                report: coordinator.contextReport(for: chat, detailed: false), hovered: $showsContext)
            if coordinator.dictation.isEnabled {
                DictationButton(
                    dictation: coordinator.dictation, editor: editor,
                    onNeedsModel: coordinator.showDictationSettings)
            }
            sendButton.padding(.leading, Theme.Spacing.sm)
        }
    }

    /// 实心圆盘，使发送成为一排安静控件中唯一醒目的记号。
    private var sendButton: some View {
        let enabled = chat.isStreaming || canSend
        return Button(action: submit) {
            Image(systemName: chat.isStreaming ? "stop.fill" : "arrow.up")
                .font(chat.isStreaming ? Theme.Typography.composerStop : Theme.Typography.composerSend)
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(enabled ? Theme.Colors.composerSendInk : Theme.Colors.textTertiary)
                .frame(width: Theme.Size.aiChatComposerControl, height: Theme.Size.aiChatComposerControl)
                .background(
                    Circle().fill(enabled ? Theme.Colors.composerSend : Theme.Colors.controlSurface)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .animation(.easeOut(duration: Theme.Duration.hover), value: enabled)
        .help(chat.isStreaming ? "Stop Response" : "Send  ↵")
        .accessibilityLabel(chat.isStreaming ? "Stop Response" : "Send")
    }

    /// 回车与按钮是同一个动作：发送，回复流式输出时为停止。
    private func submit() {
        if chat.isStreaming {
            coordinator.stopResponse(in: chat)
        } else if coordinator.send(chat.draft, in: chat) {
            chat.draft = ""
        }
    }
}

/// 输入区控件的外观：一个字形槽位、callout 标题，以及菜单的展开箭头。
private struct ComposerControlLabel<Icon: View>: View {
    var title: String?
    var showsChevron = true
    @ViewBuilder let icon: Icon

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if Icon.self != EmptyView.self {
                icon.frame(width: Theme.Size.aiChatComposerGlyph, height: Theme.Size.aiChatComposerGlyph)
            }
            if let title {
                Text(title)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(Theme.Typography.disclosure)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .foregroundStyle(Theme.Colors.textSecondary)
        .padding(.horizontal, title == nil && !showsChevron ? 0 : Theme.Spacing.md)
        .frame(minWidth: Theme.Size.aiChatComposerControl)
        .frame(height: Theme.Size.aiChatComposerControl)
        .contentShape(Rectangle())
        // 合并为一个元素：否则 VoiceOver 会把图标与箭头当作各自的菜单来朗读。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title ?? "")
    }
}

/// 只有标题的标签便捷初始化器。
extension ComposerControlLabel where Icon == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// 统一按 composerSymbol 字号渲染的 SF Symbol 图标。
private struct ComposerSymbol: View {
    let name: String

    var body: some View {
        Image(systemName: name).font(Theme.Typography.composerSymbol)
    }
}

/// 静置时无背景、指针悬停时填充，使这一行在使用前看起来是一条完整的线。
private struct ComposerControlChrome: ViewModifier {
    @State private var hovered = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.barControl, style: .continuous)
        content
            .background(shape.fill(hovered ? Theme.Colors.controlSurface : Color.clear))
            .contentShape(shape)
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: Theme.Duration.hover), value: hovered)
    }
}

extension View {
    /// 为控件套上统一的悬停背景与命中区域。
    fileprivate func composerControl() -> some View {
        modifier(ComposerControlChrome())
    }

    /// 套用 GearMac 外观的系统菜单，使其悬停效果与尺寸与本行其他控件一致。
    fileprivate func composerMenu() -> some View {
        menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .composerControl()
    }
}

/// 文件、联网搜索与工具都是偶发设置，因此用一个 + 统一收纳。
private struct AIAddMenu: View {
    let chat: AIChatState
    let coordinator: AIChatCoordinator
    let settings: AISettingsStore
    let offersSearch: Bool

    var body: some View {
        @Bindable var settings = settings
        Menu {
            Button("Attach Files…", systemImage: "paperclip") { coordinator.chooseFiles(for: chat) }
                .help(attachHelp)
            Divider()
            if offersSearch {
                Toggle("Web Search", systemImage: "globe", isOn: $settings.webSearchEnabled)
            }
            AIToolsMenu(chat: chat, coordinator: coordinator)
        } label: {
            ComposerControlLabel(showsChevron: false) { ComposerSymbol(name: "plus") }
        }
        .composerMenu()
        .help("Attach files, search the web, choose tools")
        .accessibilityLabel("Add")
    }

    /// 每个类别都有入口；帮助文案反映本聊天所用模型能读取的类型。
    private var attachHelp: String {
        let can = coordinator.capabilities(for: chat)
        switch (can.images, can.documents) {
        case (true, true): return "Attach images, PDFs or text files"
        case (true, false): return "Attach images or text files"
        case (false, true): return "Attach PDFs or text files"
        case (false, false): return "Attach text files"
        }
    }
}

/// 仅在听写开启时出现：点击开始向此输入框听写，再次点击插入文本。
private struct DictationButton: View {
    let dictation: DictationCoordinator
    let editor: ComposerTextViewHandle
    let onNeedsModel: () -> Void

    var body: some View {
        let field = dictation.field
        let session = field?.editor == editor.textView.map(ObjectIdentifier.init) ? field : nil
        Button {
            guard dictation.hasModel else { return onNeedsModel() }
            if let textView = editor.textView { dictation.toggle(into: textView) }
        } label: {
            Group {
                if session?.isTranscribing == true {
                    ProgressView().controlSize(.small)
                } else if session != nil {
                    ComposerSymbol(name: "waveform")
                        .symbolEffect(.variableColor.iterative)
                        .foregroundStyle(Color.accentColor)
                } else {
                    ComposerSymbol(name: "mic")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .frame(width: Theme.Size.aiChatComposerControl, height: Theme.Size.aiChatComposerControl)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .composerControl()
        .disabled(session?.isTranscribing == true)
        .help(help(session))
        .accessibilityLabel(session == nil ? "Dictate" : "Stop Dictating")
    }

    /// 按钮提示文案：依听写模型是否就绪与当前会话状态而定。
    private func help(_ session: DictationField?) -> String {
        guard dictation.hasModel else { return "Download a dictation model in Settings" }
        guard let session else { return "Dictate" }
        return session.isTranscribing ? "Transcribing…" : "Stop and insert the text  ↵"
    }
}

/// 联网搜索开启时显示在 + 旁边；点击关闭，通过 + 菜单可重新开启。
private struct WebSearchPill: View {
    let settings: AISettingsStore
    let isCompact: Bool

    var body: some View {
        Button {
            settings.webSearchEnabled = false
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                ComposerSymbol(name: "globe")
                    .frame(width: Theme.Size.aiChatComposerGlyph, height: Theme.Size.aiChatComposerGlyph)
                if !isCompact { Text("Search").font(.callout) }
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, isCompact ? 0 : Theme.Spacing.md)
            .frame(minWidth: Theme.Size.aiChatComposerControl)
            .frame(height: Theme.Size.aiChatComposerControl)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .composerControl()
        .help("Web search is on; click to turn it off")
        .accessibilityLabel("Web search is on")
    }
}

/// 所有已配置的模型，按运行位置分组；所选模型属于本聊天。
private struct AIModelPicker: View {
    let chat: AIChatState
    /// 由外部传入而不从 `chat` 读取：每次流式刷新都会重写 session。
    let selected: AIModelSelection?
    let coordinator: AIChatCoordinator

    var body: some View {
        let groups = coordinator.modelGroups
        Menu {
            if coordinator.isModelCatalogLoading {
                Text("Loading models…")
            }
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.options) { option in
                        Toggle(
                            isOn: Binding(
                                get: { selected.map(option.matches) ?? false },
                                set: { if $0 { coordinator.selectModel(option, in: chat) } })
                        ) {
                            Label {
                                Text(option.title)
                            } icon: {
                                MenuIconImage(icon: option.menuIcon)
                            }
                        }
                    }
                }
            }
            if groups.isEmpty, !coordinator.isModelCatalogLoading {
                Button("Configure AI…", action: coordinator.showSettings)
            }
        } label: {
            ComposerControlLabel(
                title: coordinator.modelTitle(of: selected, among: groups.flatMap(\.options))
            ) {
                MenuIconImage(icon: coordinator.modelIcon(of: selected), edge: Theme.Size.menuBrandIcon)
                    .font(Theme.Typography.composerSymbol)
            }
        }
        .composerMenu()
        .help("Switch this chat's model")
    }
}

/// 推理档位选择器；仅在当前模型支持推理档位时可用。
private struct AIReasoningPicker: View {
    let chat: AIChatState
    let coordinator: AIChatCoordinator

    /// 即使模型没有可选的推理档位也显示，使这一行的形状不会在使用者眼前变化。
    var body: some View {
        let efforts = coordinator.reasoningEfforts(for: chat)
        let selected = coordinator.model(for: chat)?.effort
        Menu {
            ForEach(efforts, id: \.id) { effort in
                Toggle(
                    effort.title,
                    isOn: Binding(
                        get: { selected == effort.id },
                        set: { if $0 { coordinator.selectReasoningEffort(effort, in: chat) } }))
            }
        } label: {
            // 用文字而非图标：紧挨模型名称时，它已经自然地读作该模型的设置。
            ComposerControlLabel(
                title: efforts.isEmpty ? "Reasoning" : coordinator.selectedReasoningTitle(for: chat))
        }
        .composerMenu()
        .disabled(efforts.isEmpty)
        .help(efforts.isEmpty ? "This model has no reasoning setting" : "Change reasoning effort")
    }
}

/// 本聊天的 MCP 服务器：可全开、部分开或全关；模型必须是会调用工具的那类。
private struct AIToolsMenu: View {
    let chat: AIChatState
    let coordinator: AIChatCoordinator

    var body: some View {
        let servers = coordinator.mcpServers
        let scope = chat.toolScope
        let takesTools = coordinator.capabilities(for: chat).tools
        let active = servers.filter { scope.allows($0.slug) }.count
        Menu {
            if servers.isEmpty {
                Text("No MCP servers are connected")
            } else {
                Toggle(
                    "Use Tools",
                    isOn: Binding(
                        get: { scope.isEnabled },
                        set: { coordinator.setToolsEnabled($0, in: chat) }))
                Section("Servers") {
                    ForEach(servers) { server in
                        Toggle(
                            server.name.isEmpty ? server.slug : server.name,
                            isOn: Binding(
                                get: { scope.allows(server.slug) },
                                set: { _ in coordinator.toggleToolServer(server.slug, in: chat) })
                        )
                        .disabled(!scope.isEnabled)
                    }
                }
            }
            Divider()
            Button("MCP Settings…", action: coordinator.showMCPSettings)
        } label: {
            Label(
                !takesTools
                    ? "Tools · Not with this model"
                    : servers.isEmpty || !scope.isEnabled
                        ? "Tools · Off" : "Tools · \(active) of \(servers.count)",
                systemImage: "wrench.and.screwdriver")
        }
        .disabled(!takesTools)
    }
}

/// 显示当前聊天中查找的位置，并提供与 ⌘G、⇧⌘G 相同的步进按钮。
private struct FindCounter: View {
    let position: Int
    let count: Int
    let step: (Int) -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(count == 0 ? "No matches" : "\(position) of \(count)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button {
                step(-1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .help("Previous Match  ⇧⌘G")
            .disabled(count == 0)
            Button {
                step(1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .help("Next Match  ⌘G")
            .disabled(count == 0)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .glassSurface(in: Capsule())
    }
}

/// 表示上下文占用比例的圆环；悬停时抬起输入区的上下文卡片。
private struct ContextGauge: View {
    @Environment(AIChatCoordinator.self) private var coordinator
    let report: ChatContextReport
    @Binding var hovered: Bool

    var body: some View {
        ContextRing(fill: min(max(report.fill, 0), 1), tint: report.tint)
            .frame(width: Theme.Size.aiChatComposerControl, height: Theme.Size.aiChatComposerControl)
            .composerControl()
            .onHover { hovered = $0 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(report.accessibilitySummary(coordinator.language))
    }
}

/// 上下文占用环：底环加一段按比例裁剪并着色的弧。
private struct ContextRing: View {
    let fill: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(Theme.Colors.border, lineWidth: Theme.Size.contextRingStroke)
            Circle()
                .trim(from: 0, to: fill)
                .stroke(tint, style: StrokeStyle(lineWidth: Theme.Size.contextRingStroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: Theme.Size.chatContextGauge, height: Theme.Size.chatContextGauge)
    }
}

/// GearMac 自绘的卡片而非 popover：先显示聊天已占用的 token，再显示下一轮将发送的内容。
private struct ContextCard: View {
    let report: ChatContextReport

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Context").font(.headline)
                Spacer(minLength: Theme.Spacing.xxl)
                Text(report.fill.formatted(.percent.precision(.fractionLength(0))))
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(report.tint)
            }
            ProgressView(value: min(report.fill, 1))
                .tint(report.tint)
            if report.historyBytes > report.budget {
                Text("The oldest messages no longer fit and are left out.")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.destructive)
            }
            Grid(
                alignment: .leading, horizontalSpacing: Theme.Spacing.xl,
                verticalSpacing: Theme.Spacing.xs
            ) {
                section("Tokens")
                if let usage = report.usage, let context = usage.contextTokens {
                    row("In context", tokens(context, of: usage.contextWindow))
                    row("Input", input(usage))
                    row("Output", output(usage))
                    if let cost = usage.costUSD {
                        row(
                            "Cost",
                            cost.formatted(
                                .currency(code: "USD").precision(.significantDigits(2))))
                    }
                } else {
                    row("Last reply", "Not reported yet")
                }
                section("Next message")
                row("Model", report.modelTitle)
                row("History", "\(bytes(report.historyBytes)) of \(bytes(report.budget))")
                row("Messages", "\(report.sentMessages) of \(report.totalMessages)")
                if report.stagedFiles > 0 {
                    row("Attached", "\(report.stagedFiles) · \(bytes(report.stagedBytes))")
                }
                row("System prompt", report.systemPrompt ? "On" : "Off")
                row("Web search", report.webSearch ? "On" : "Off")
                row(
                    "MCP servers",
                    report.toolServers == 0 ? "None" : "\(report.toolServers) in reach")
            }
            .font(.callout)
        }
        .padding(Theme.Spacing.xl)
        .frame(width: Theme.Size.chatContextCard, alignment: .leading)
        .glassSurface(in: shape)
        // 在玻璃效果之下再加一层实底：卡片浮在转录区之上，其下方文字不应透出。
        .background { shape.fill(Theme.Colors.windowSurface) }
        .shadow(color: Theme.Colors.tooltipShadow, radius: Theme.Spacing.xl, y: Theme.Spacing.xs)
    }

    /// 卡片内的分组标题行。
    private func section(_ title: String) -> some View {
        GridRow {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .gridCellColumns(2)
                .padding(.top, Theme.Spacing.xs)
        }
    }

    /// 卡片内的一行标签与取值。
    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit().lineLimit(1).truncationMode(.middle)
        }
    }

    /// 按文件大小格式（如 KB/MB）显示字节数。
    private func bytes(_ count: Int) -> String {
        count.formatted(.byteCount(style: .file))
    }

    /// 把 token 数与窗口上限组合成一行文案；不知道上限时只显示数值。
    private func tokens(_ count: Int, of window: Int?) -> String {
        guard let window else { return count.formatted() }
        return "\(count.formatted()) of \(window.formatted(.number.notation(.compactName)))"
    }

    /// 输入 token 数与缓存命中数。
    private func input(_ usage: AIUsage) -> String {
        let prompt = (usage.inputTokens ?? 0) + (usage.cachedInputTokens ?? 0)
        guard let cached = usage.cachedInputTokens, cached > 0 else { return prompt.formatted() }
        return "\(prompt.formatted()) · \(cached.formatted()) cached"
    }

    /// 输出 token 数与其中用于思考的 token 数。
    private func output(_ usage: AIUsage) -> String {
        let output = usage.outputTokens ?? 0
        guard let thinking = usage.reasoningTokens, thinking > 0 else { return output.formatted() }
        return "\(output.formatted()) · \(thinking.formatted()) thinking"
    }
}

/// 依据占用比例选择环与进度条的颜色。
extension ChatContextReport {
    fileprivate var tint: Color {
        if fill >= 1 { return Theme.Colors.destructive }
        return fill >= 0.8 ? Theme.Colors.warning : Theme.Colors.textSecondary
    }
}

/// 菜单会按自己的尺寸绘制图片，因此品牌标记需按符号的尺寸重绘。
private struct MenuIconImage: View {
    let icon: PopoverMenuIcon
    var edge: CGFloat = 16

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
        case .asset(let name):
            if let image = Self.sized(name, edge: edge) {
                Image(nsImage: image)
            } else {
                Image(systemName: "sparkles")
            }
        case .file, .thumbnail, .blank, .dot:
            Image(systemName: "sparkles")
        }
    }

    /// 把品牌图片重绘到指定边长，并标记为 template 以跟随文本颜色。
    private static func sized(_ name: String, edge: CGFloat) -> NSImage? {
        guard let source = NSImage(named: name) else { return nil }
        let size = NSSize(width: edge, height: edge)
        let image = NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }
}
