// 文件职责：渲染扩展命令在 Palette 中的根界面，并按会话状态（启动中/失败/完成）与界面类型（列表/网格/详情/表单）分发到对应视图。
// 分层：UI；只呈现状态，不执行业务逻辑。
import SwiftUI

/// Palette 中的扩展界面：即运行中的命令渲染出的根组件。
struct ExtensionCommandView: View {
    let screen: ExtensionScreen
    let state: ExtensionSessionState
    let selection: Int
    let assetsPath: String?
    let scroll: ScrollIntent
    let onSelect: (Int) -> Void
    let onActivate: (Int) -> Void
    let onActions: (Int) -> Void
    let onFieldChange: (RenderNode, Any) -> Void

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .launching where screen.root == nil:
            EmptyResults(text: "Starting…")
        case .failed(let message):
            ExtensionFailureView(message: message)
        case .finished:
            EmptyResults(text: "Done")
        default:
            switch screen.kind {
            case .list, .grid:
                ExtensionListView(
                    screen: screen, selection: selection, assetsPath: assetsPath,
                    scroll: scroll, onSelect: onSelect, onActivate: onActivate,
                    onActions: onActions)
            case .detail:
                ExtensionDetailBody(
                    markdown: screen.root?.string("markdown"),
                    metadata: screen.root?.node("metadata"),
                    isLoading: screen.isLoading, assetsPath: assetsPath)
            case .form:
                ExtensionFormView(
                    screen: screen, assetsPath: assetsPath, selection: selection, scroll: scroll,
                    onSelect: onSelect, onChange: onFieldChange,
                    onSubmit: { onActivate(selection) })
            case .unsupported(let type):
                if type.isEmpty {
                    // 某次提交渲染为 null；此处若显示“Starting…”会像是卡住。
                    EmptyResults(text: "Nothing to show")
                } else {
                    ExtensionFailureView(
                        message:
                            "This command renders \(type), which GearMac doesn't support yet. See docs/extensions.md."
                    )
                }
            }
        }
    }
}

/// 保留堆栈信息：这是作者能获得的唯一调试线索。
struct ExtensionFailureView: View {
    @Environment(\.metrics) private var metrics
    let message: String

    /// 取消息的第一行作为标题。
    private var headline: String {
        message.split(separator: "\n").first.map(String.init) ?? message
    }
    /// 标题之外的其余行作为详细信息。
    private var detail: String? {
        let lines = message.split(separator: "\n").dropFirst()
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.spacing.md) {
                HStack(spacing: metrics.spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(headline)
                        .font(metrics.typography.rowTitle)
                        .textSelection(.enabled)
                }
                if let detail {
                    Text(detail)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(metrics.spacing.lg)
            .hideNativeScrollers()
        }
        .thinScrollbar()
    }
}

/// 扩展命令的吐司提示条：支持成功/失败/进行中样式与主操作。
struct ExtensionToastPill: View {
    private static let glowOpacity = 0.14
    private static let glowRadius: CGFloat = 150
    private static let rimOpacity = 0.25

    @Environment(\.metrics) private var metrics
    let toast: ExtensionToast
    let onAction: (String) -> Void
    let onDismiss: () -> Void
    @State private var hovered = false
    /// 新的时间戳会重新触发重置，从而第二次复制仍能保持显示“Copied”。
    @State private var copiedAt: Date?

    /// 根据提示样式返回对应的主题色。
    private var tint: Color {
        switch toast.style {
        case .success: Theme.Colors.success
        case .failure: Theme.Colors.destructive
        case .animated: Theme.Colors.progress
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            mark.frame(width: metrics.size.menuButton, height: metrics.size.menuButton)
            HStack(spacing: metrics.spacing.md) {
                Text(toast.title).foregroundStyle(Theme.Colors.textPrimary).layoutPriority(1)
                if let message = toast.message, !message.isEmpty {
                    Text(message).foregroundStyle(Theme.Colors.textSecondary)
                }
                if toast.style == .failure {
                    divider
                    button {
                        Paster.copyPlainText(
                            [toast.title, toast.message].compactMap(\.self).joined(separator: "\n"))
                        copiedAt = Date()
                    } label: {
                        // 用较宽的词占住宽度，使该胶囊在复制时不会抖动。
                        ZStack {
                            Text("Copied").hidden()
                            Text(copiedAt == nil ? "Copy" : "Copied")
                        }
                    }
                } else if let action = toast.primaryAction {
                    divider
                    button {
                        onAction(action.token)
                    } label: {
                        Text(action.title)
                    }
                }
            }
            .font(metrics.typography.bar)
            .lineLimit(1)
            .padding(.trailing, metrics.spacing.xl)
        }
        .frame(height: metrics.size.menuButton)
        .background { glow }
        .overlay {
            Capsule().strokeBorder(
                LinearGradient(
                    colors: [tint.opacity(Self.rimOpacity), tint.opacity(0.06), .clear],
                    startPoint: .leading, endPoint: .trailing),
                lineWidth: Theme.Size.hairline)
        }
        .frosted(in: Capsule())
        .contentShape(Capsule())
        .onTapGesture(perform: onDismiss)
        .onHover { isHovered in
            withAnimation(.easeOut(duration: Theme.Duration.hover)) { hovered = isHovered }
        }
        .accessibilityAction(named: "Dismiss", onDismiss)
        .task(id: copiedAt) {
            guard copiedAt != nil else { return }
            try? await Task.sleep(for: .seconds(Theme.Duration.copyFeedback))
            copiedAt = nil
        }
    }

    /// 提示条内的竖向分隔线。
    private var divider: some View {
        Rectangle()
            .fill(Theme.Colors.border)
            .frame(width: Theme.Size.hairline, height: metrics.size.menuIcon * 0.7)
    }

    /// 提示条内的文本按钮（复制或主操作）。
    private func button(
        action: @escaping () -> Void, @ViewBuilder label: () -> some View
    ) -> some View {
        Button(action: action, label: label)
            .fixedSize()
            .buttonStyle(.plain)
            .fontWeight(.semibold)
            .foregroundStyle(Theme.Colors.textPrimary)
    }

    /// 提示条左侧的径向辉光背景。
    private var glow: some View {
        GeometryReader { proxy in
            Capsule().fill(
                RadialGradient(
                    colors: [tint.opacity(Self.glowOpacity), tint.opacity(0.03), .clear],
                    center: UnitPoint(x: metrics.size.menuButton / 2 / proxy.size.width, y: 0.5),
                    startRadius: 0, endRadius: Self.glowRadius))
        }
    }

    /// 提示条左侧图标：悬停时变为关闭按钮。
    private var mark: some View {
        Group {
            if hovered {
                Image(systemName: "xmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                symbol.foregroundStyle(tint)
            }
        }
        .font(metrics.typography.menuIcon)
        .transition(.opacity)
    }

    /// 根据提示样式返回对应的 SF Symbol。
    @ViewBuilder
    private var symbol: some View {
        switch toast.style {
        case .success: Image(systemName: "checkmark")
        case .failure: Image(systemName: "exclamationmark")
        case .animated:
            Image(systemName: "progress.indicator")
                .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing)
        }
    }
}

/// 运行中的命令当前选中项的 ⌘K 面板内容。
@MainActor
enum ExtensionActionsMenu {
    /// 面板所属的对象：选中的行；当选中位置超出范围时则为整个界面。
    static func header(screen: ExtensionScreen, selection: Int) -> String? {
        // 表单的行即其字段，面板作用于整个表单而非单个字段。
        guard screen.kind != .form, screen.items.indices.contains(selection) else {
            return screen.navigationTitle
        }
        return screen.items[selection].node.string("title")
    }

    /// 行携带已解析的 `ExtensionImage`；若每次 ↑/↓ 才解析会在主线程探测符号。
    static func rows(_ actions: [ExtensionAction], assetsPath: String?) -> [ExtensionActionItem] {
        actions.map { action in
            ExtensionActionItem(
                title: action.title,
                icon: ExtensionImage.actionIcon(
                    action.iconValue, assetsPath: assetsPath,
                    // 直接读取而非注入：面板每次打开都会重建。
                    isDark: NSApp.effectiveAppearance.isDark,
                    isDestructive: action.isDestructive),
                shortcut: action.shortcutCaps?.joined(),
                isDestructive: action.isDestructive,
                startsSection: action.startsSection)
        }
    }
}
