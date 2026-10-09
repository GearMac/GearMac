// 文件职责：渲染 Quick Action 结果面板的 SwiftUI 视图，包含可滚动内容、顶部标题栏、底部操作栏与差异高亮。
// 分层：UI；纯展示视图，状态由 QuickActionPanelState 提供，交互通过回调上抛。
import SwiftUI

/// Quick Action 结果面板的 SwiftUI 视图。
struct QuickActionResultView: View {

    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    let state: QuickActionPanelState
    let languages: [Locale.Language]
    let onReplace: () -> Void
    let onCopy: () -> Void
    let onCancel: () -> Void
    let onRetranslate: (Locale.Language) -> Void
    let onOpenLanguageSettings: () -> Void
    let onHeight: (CGFloat) -> Void

    @State private var contentHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0

    /// 显式使用 overlay 而非 `safeAreaBar`：后者会把条栏叠在内容之上而非为其留出内边距。
    var body: some View {
        ScrollView {
            body(for: state.phase)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, metrics.spacing.xxl)
                // `ScrollView` 没有理想高度，因此下方设置的是确定高度而非仅仅上限。
                .fixedSize(horizontal: false, vertical: true)
                // 在内边距之前测量，因此 `isScrollable` 不会依赖自身的结果。
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    contentHeight = $0
                }
                .padding(.top, inset(headerHeight))
                .padding(.bottom, inset(footerHeight))
        }
        .scrollBounceBehavior(.basedOnSize)
        .mask(scrollFade)
        .overlay(alignment: .top) { measured(header) { headerHeight = $0 } }
        .overlay(alignment: .bottom) { measured(footer) { footerHeight = $0 } }
        .frame(width: metrics.size.quickActionPanel, height: panelHeight)
        .background(Theme.Colors.panelScrim)
        .background(GlassEffectView())
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius.dialog, style: .continuous))
        .panelEntrance()
        // 这里是上报而非测量：上方的高度由本视图决定，回读会形成自我反馈。
        .onChange(of: panelHeight, initial: true) { onHeight(panelHeight) }
    }

    /// 通过几何变化回调上报指定条栏的高度。
    private func measured(_ bar: some View, action: @escaping (CGFloat) -> Void) -> some View {
        bar.onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: action)
    }

    /// 为条栏及其渐变留出高度，使首行在滚入渐变区之前保持不透明。
    private func inset(_ bar: CGFloat) -> CGFloat {
        bar + (isScrollable ? metrics.size.quickActionScrollFade : 0)
    }

    /// 使用 mask 而非 `scrollEdgeEffectStyle`：后者的材质在此毛玻璃效果上合成后不可见。
    @ViewBuilder
    private var scrollFade: some View {
        if isScrollable {
            VStack(spacing: 0) {
                // 每个条栏背后完全透明，否则文字会从标题与按钮周围透出。
                Color.clear.frame(height: headerHeight)
                ramp(from: .clear, to: .black)
                Color.black
                ramp(from: .black, to: .clear)
                Color.clear.frame(height: footerHeight)
            }
        } else {
            // 对已经完整显示的结果做淡出只会无谓地使其变暗。
            Color.black
        }
    }

    /// 生成一段从起始色过渡到结束色的线性渐变。
    private func ramp(from start: Color, to end: Color) -> some View {
        LinearGradient(colors: [start, end], startPoint: .top, endPoint: .bottom)
            .frame(height: metrics.size.quickActionScrollFade)
    }

    /// 内容是否超出面板体区高度而需要滚动。
    private var isScrollable: Bool { contentHeight > metrics.size.quickActionPanelBody }

    /// 面板总高度：内容加上条栏高度，并约束在最小与最大体区之间。
    private var panelHeight: CGFloat {
        let chrome = headerHeight + footerHeight
        return min(
            max(contentHeight + chrome, chrome + metrics.size.quickActionPanelMinBody),
            chrome + metrics.size.quickActionPanelBody)
    }

    /// 顶部条栏：动作图标与标题，翻译动作额外显示语言菜单。
    private var header: some View {
        HStack(spacing: metrics.spacing.md) {
            // 只有标题区域可拖动：拖拽把手是覆盖层，会吞掉菜单的点击。
            HStack(spacing: metrics.spacing.sm) {
                SymbolImage(name: state.action.symbol, size: metrics.size.quickActionHeaderIcon)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(state.action.localizedTitle(settings.language))
                    .font(metrics.typography.panelTitle)
                Spacer(minLength: metrics.spacing.md)
            }
            .windowDraggable(true)
            if state.action == .translate, !languages.isEmpty { languageMenu }
        }
        .padding(.horizontal, metrics.spacing.xxl)
        .padding(.top, metrics.spacing.xl)
        .padding(.bottom, metrics.spacing.lg)
    }

    /// 按当前阶段渲染面板主体内容。
    @ViewBuilder
    private func body(for phase: QuickActionPanelState.Phase) -> some View {
        switch phase {
        case .running where state.output.isEmpty:
            HStack(spacing: metrics.spacing.md) {
                ProgressView().controlSize(.small)
                Text(settings.text(QuickActionsKey.panelWorking))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .font(metrics.typography.rowTitle)
        case .running, .finished:
            if phase == .finished, let decisions = state.decisions {
                DecisionsAnswerList(decisions: decisions)
            } else {
                output
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(metrics.typography.rowTitle)
                .foregroundStyle(Theme.Colors.textSecondary)
        case .needsLanguageDownload:
            downloadPrompt
        }
    }

    /// 结果输出：优先展示差异高亮，摘要动作走 Markdown 渲染，其余按纯文本展示。
    @ViewBuilder
    private var output: some View {
        let chunks = state.diff
        if !chunks.isEmpty {
            // 每个片段单独一个 `Text` 会破坏换行，因此在同一字符串内部设定样式。
            prose(Text(attributed(chunks)))
        } else if state.action == .summarize {
            ChatMarkdownText(blocks: MarkdownBlock.parse(state.output, midStream: state.isRunning))
        } else {
            prose(Text(state.output))
        }
    }

    /// 结果是供阅读的段落而非行标签，因此按段落的行距呈现。
    private func prose(_ text: Text) -> some View {
        text
            .font(metrics.typography.rowTitle)
            .lineSpacing(metrics.spacing.xs)
            .textSelection(.enabled)
    }

    /// 将文本差异分块组装为带颜色的 AttributedString（新增为绿色、删除为红色删除线）。
    private func attributed(_ chunks: [TextDiffEngine.Chunk]) -> AttributedString {
        chunks.reduce(into: AttributedString()) { result, chunk in
            switch chunk {
            case .equal(let text):
                result.append(AttributedString(text))
            case .inserted(let text):
                var run = AttributedString(text)
                run.foregroundColor = Theme.Colors.success
                result.append(run)
            case .deleted(let text):
                var run = AttributedString(text)
                run.foregroundColor = Theme.Colors.destructive
                run.strikethroughStyle = .single
                result.append(run)
            }
        }
    }

    /// 引导到系统设置，而非调用 `prepareTranslation`：后者的弹层不会出现在本面板之上。
    private var downloadPrompt: some View {
        let language = TextTranslator.displayName(of: state.targetLanguage)
        return VStack(alignment: .leading, spacing: metrics.spacing.lg) {
            VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                Text(
                    String(
                        format: settings.text(QuickActionsKey.panelNotDownloaded), language)
                )
                .font(metrics.typography.rowTitle)
                .foregroundStyle(Theme.Colors.textSecondary)
                Text(LocalizedStringKey(settings.text(QuickActionsKey.panelDownloadHint)))
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            Button(settings.text(QuickActionsKey.panelOpenLanguageRegion), action: onOpenLanguageSettings)
                .buttonStyle(.modalAction(.standard, fillsWidth: false))
        }
    }

    /// 目标语言切换菜单。
    private var languageMenu: some View {
        Menu(TextTranslator.displayName(of: state.targetLanguage)) {
            ForEach(languages, id: \.minimalIdentifier) { language in
                Button(TextTranslator.displayName(of: language)) { onRetranslate(language) }
            }
        }
        .menuStyle(.button)
        .buttonStyle(.accessoryBar)
        .fixedSize()
    }

    /// 底部操作栏：关闭、复制与替换按钮，后两者在结果可用前禁用；判定结果没有可替换的文本，不提供替换。
    private var footer: some View {
        HStack(spacing: metrics.spacing.md) {
            Spacer(minLength: metrics.spacing.md)
            Button(settings.text(QuickActionsKey.panelDismiss), action: onCancel)
                .buttonStyle(.modalAction(.cancel, fillsWidth: false))
            Button(settings.text(QuickActionsKey.panelCopy), action: onCopy)
                .buttonStyle(.modalAction(.standard, fillsWidth: false))
                .disabled(!state.canCopy)
            if state.decisions == nil {
                Button(settings.text(QuickActionsKey.panelReplace), action: onReplace)
                    .buttonStyle(.modalAction(.primary, fillsWidth: false))
                    .disabled(!state.canReplace)
            }
        }
        .padding(.horizontal, metrics.spacing.xxl)
        .padding(.vertical, metrics.spacing.xl)
    }
}

/// Decide 的结果列表：每个答案一张行卡，按答案类型展示结论、概率条与分布。
private struct DecisionsAnswerList: View {
    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    let decisions: QuickActionDecisionsOutcome

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.lg) {
            ForEach(Array(decisions.answers.enumerated()), id: \.offset) { _, answer in
                DecisionsAnswerRow(answer: answer)
            }
            if let usage = decisions.usage {
                Text(
                    String(
                        format: settings.text(AIKey.decisionsCopyTokens),
                        usage.inputTokens ?? 0, usage.outputTokens ?? 0))
                    .font(metrics.typography.cardMeta)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }
}

/// 单个判定答案的行卡：名称与类型符号在首行，结论与概率分布在下方。
private struct DecisionsAnswerRow: View {
    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    let answer: DecisionsAnswer

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            HStack(spacing: metrics.spacing.sm) {
                Image(systemName: symbol)
                    .font(metrics.typography.cardMeta)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Text(answer.name ?? "—")
                    .font(metrics.typography.rowTitle.weight(.medium))
                Spacer(minLength: metrics.spacing.sm)
                headline
            }
            switch answer.type {
            case .predicate:
                bar(answer.probability ?? 0)
            case .choice, .score:
                distribution
            case .refusal:
                EmptyView()
            }
        }
    }

    /// 行首的类型符号，与设置里的问题列表一致。
    private var symbol: String {
        switch answer.type.questionKind {
        case .predicate: return "questionmark.bubble"
        case .choice: return "list.bullet"
        case .score: return "chart.bar"
        case nil: return "exclamationmark.bubble"
        }
    }

    /// 结论行：命题是与否，选择题是被选中的值，评分是就近档位，拒答给出一枚胶囊。
    @ViewBuilder
    private var headline: some View {
        switch answer.type {
        case .predicate:
            Text(
                "\(verdict) \(Int(((answer.probability ?? 0) * 100).rounded()))%"
            )
            .font(metrics.typography.rowTrailing.weight(.medium))
            .foregroundStyle(Theme.Colors.textSecondary)
        case .choice:
            VStack(alignment: .trailing, spacing: 0) {
                Text(answer.choice ?? "—")
                    .font(metrics.typography.rowTrailing.weight(.medium))
                if let confidence = answer.confidence {
                    Text(
                        String(
                            format: settings.text(AIKey.decisionsConfidence),
                            Int((confidence * 100).rounded())))
                        .font(metrics.typography.cardMeta)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        case .score:
            Text(scoreLabel)
                .font(metrics.typography.rowTrailing.weight(.medium))
                .foregroundStyle(Theme.Colors.textSecondary)
        case .refusal:
            Text(settings.text(AIKey.decisionsRefusedChip))
                .font(metrics.typography.cardMeta)
                .padding(.horizontal, metrics.spacing.sm)
                .padding(.vertical, metrics.spacing.xxs)
                .background(Theme.Colors.controlSurface, in: Capsule())
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    /// 命题结论的本地化措辞。
    private var verdict: String {
        let key: AIKey =
            (answer.probability ?? 0) >= 0.5 ? .decisionsVerdictYes : .decisionsVerdictNo
        return settings.text(key)
    }

    /// 评分结论：就近档位的名称，找不到时退回首个分布项。
    private var scoreLabel: String {
        if let index = answer.nearestLevelIndex,
            answer.probabilities.indices.contains(index),
            let label = answer.probabilities[index].label
        {
            return label
        }
        return answer.probabilities.first?.label ?? "—"
    }

    /// 选项/档位的完整分布：名称 + 百分比 + 细概率条。
    private var distribution: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            ForEach(Array(answer.probabilities.enumerated()), id: \.offset) { _, item in
                HStack(spacing: metrics.spacing.md) {
                    Text(item.label ?? item.value ?? "—")
                        .font(metrics.typography.cardMeta)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(minWidth: 64, alignment: .leading)
                    bar(item.probability)
                    Text("\(Int((item.probability * 100).rounded()))%")
                        .font(metrics.typography.cardMeta.monospacedDigit())
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .frame(minWidth: 40, alignment: .trailing)
                }
            }
        }
    }

    /// 细概率条：胶囊轨道 + 按概率填充。
    private func bar(_ value: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.controlSurface)
                Capsule()
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: proxy.size.width * CGFloat(min(max(value, 0), 1)))
            }
        }
        .frame(height: 4)
    }
}
