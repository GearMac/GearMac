// 文件职责：提供搜索框旁的内联命令参数字段组件，支持自由输入型与菜单选择型两种字段，并显示待补填警示。
// 分层：UI（DesignSystem）；字段值通过外部传入的 `Binding` 工厂读写，组件自身只记录「已访问过」的局部状态。
import SwiftUI

/// 一个内联参数字段。`id` 用于区分焦点与取值，因此两个字段可以共用同一标题。
struct InlineArgument: Equatable {
    let id: String
    let title: String
    /// 非空表示该字段从命令面板的菜单中选择，而不是手动输入。
    var options: [String] = []
    /// 永远不会被标记为待补：留空本身就是一种回答。
    var isOptional = false
}

/// 位于搜索框旁的参数字段栏，该行声明的每个参数对应一个字段。
struct InlineArgumentFields: View {
    @Environment(\.metrics) private var metrics
    let arguments: [InlineArgument]
    /// 该行的图标，用于把整条字段栏锚定到该行；该行已在列表中显示时为 nil。
    let symbol: String?
    /// 按参数 id 生成 `Binding` 的工厂——实际取值存放在 `PaletteState.commandArguments`。
    let value: (String) -> Binding<String>
    @FocusState.Binding var focused: String?
    /// 带选项的字段是选择而非输入，因此改为把菜单交回命令面板处理。
    let openOptions: (String) -> Void
    /// 在字段内按 ↵ 与在该行上按 ↵ 行为一致。
    let onSubmit: () -> Void
    /// 光标已进入并离开过的字段。只有进入过且未填写，才算待补。
    @State private var visited: Set<String> = []

    var body: some View {
        HStack(spacing: metrics.spacing.xs) {
            if let symbol {
                Image(nsImage: IconCache.symbolIcon(named: symbol))
                    .resizable()
                    .frame(width: Self.height(metrics), height: Self.height(metrics))
            }
            ForEach(arguments, id: \.id) { argument in
                let isOwed = !argument.isOptional && visited.contains(argument.id)
                if argument.options.isEmpty {
                    ArgumentField(
                        argument: argument, text: value(argument.id),
                        isFocused: focused == argument.id, isOwed: isOwed, onSubmit: onSubmit
                    )
                    .focused($focused, equals: argument.id)
                } else {
                    ArgumentChoiceField(
                        argument: argument, text: value(argument.id),
                        isFocused: focused == argument.id, isOwed: isOwed,
                        onOpen: { openOptions(argument.id) }
                    )
                    .focused($focused, equals: argument.id)
                }
            }
        }
        // 只有光标进入过并已离开的字段，才会提示仍缺少取值。
        .onChange(of: focused) { previous, _ in
            if let previous, arguments.contains(where: { $0.id == previous }) {
                visited.insert(previous)
            }
        }
    }

    /// 字段高度：按 Interface Size 缩放后的 26pt。
    static func height(_ metrics: InterfaceMetrics) -> CGFloat { metrics.scaled(26) }

    /// 头部会把搜索框收缩到恰好剩余的空间，此处计算字段栏占用的总宽度（含图标与间隙）。
    static func totalWidth(
        for arguments: [InlineArgument], hasIcon: Bool, metrics: InterfaceMetrics
    ) -> CGFloat {
        let fields = arguments.reduce(0) { $0 + fieldWidth(for: $1, metrics: metrics) }
        let gaps = CGFloat(arguments.count + (hasIcon ? 0 : -1)) * metrics.spacing.xs
        return fields + gaps + (hasIcon ? height(metrics) : 0)
    }

    /// 按标题长度估算单个字段的宽度，并限制在缩放后的最小值与最大值之间。
    static func fieldWidth(for argument: InlineArgument, metrics: InterfaceMetrics) -> CGFloat {
        let title = CGFloat(argument.title.count) * metrics.scaled(7)
        return min(max(title + metrics.scaled(34), metrics.scaled(72)), metrics.scaled(160))
    }
}

/// 共用的外观修饰器，让输入型字段与选择型字段看起来是同一个控件。
private struct ArgumentFieldChrome: ViewModifier {
    @Environment(\.metrics) private var metrics
    let argument: InlineArgument
    let isFocused: Bool
    /// 已进入、已离开且仍为空——只有这种状态才会显示警示描边。
    let isOwed: Bool
    @Binding var hovered: Bool

    func body(content: Content) -> some View {
        content
            .frame(width: InlineArgumentFields.fieldWidth(for: argument, metrics: metrics))
            .padding(.horizontal, metrics.spacing.sm)
            .frame(height: InlineArgumentFields.height(metrics))
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
            .onHover { hovered = $0 }
            .help(help)
    }

    private var help: String {
        if isOwed { return "\(argument.title) — required" }
        return argument.isOptional ? "\(argument.title) — optional" : argument.title
    }

    private var fill: Color {
        if isFocused { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return Theme.Colors.cardFill
    }

    /// 聚焦表现为更亮的描边；只有离开后仍未填写的字段才会变红。
    private var stroke: Color {
        if isFocused { return Color.accentColor }
        if isOwed { return Theme.Colors.destructive.opacity(0.55) }
        return Theme.Colors.cardStroke
    }
}

/// 自由输入的参数字段。
private struct ArgumentField: View {

    @Environment(\.metrics) private var metrics
    let argument: InlineArgument
    @Binding var text: String
    let isFocused: Bool
    let isOwed: Bool
    let onSubmit: () -> Void
    @State private var hovered = false

    var body: some View {
        TextField(
            "", text: $text,
            prompt: Text(argument.title).foregroundStyle(Theme.Colors.textTertiary)
        )
        .textFieldStyle(.plain)
        .font(metrics.typography.rowTrailing)
        .tint(Theme.Colors.textPrimary)
        .onSubmit(onSubmit)
        .modifier(
            ArgumentFieldChrome(
                argument: argument, isFocused: isFocused, isOwed: isOwed && text.isEmpty,
                hovered: $hovered))
    }
}

/// 带选项的字段：取值从命令面板自带的菜单中挑选，绝不手动输入。
private struct ArgumentChoiceField: View {
    @Environment(\.metrics) private var metrics
    let argument: InlineArgument
    @Binding var text: String
    let isFocused: Bool
    let isOwed: Bool
    let onOpen: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: metrics.spacing.xxs) {
            Text(text.isEmpty ? argument.title : text)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(
                    text.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.textPrimary
                )
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .modifier(
            ArgumentFieldChrome(
                argument: argument, isFocused: isFocused, isOwed: isOwed && text.isEmpty,
                hovered: $hovered)
        )
        .contentShape(Rectangle())
        .focusable()
        // 外观修饰器已绘制聚焦描边，AppKit 的蓝色光圈会重复，因此这里禁用它。
        .focusEffectDisabled()
        .onTapGesture(perform: onOpen)
        .onKeyPress(keys: [.return, KeyEquivalent("\u{3}")]) { _ in
            onOpen()
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(argument.title))
        .accessibilityValue(Text(text.isEmpty ? "No value" : text))
        .accessibilityHint(Text("Opens a list of choices"))
        .accessibilityAddTraits(.isButton)
    }
}
