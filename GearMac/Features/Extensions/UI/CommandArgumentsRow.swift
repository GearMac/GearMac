// 文件职责：渲染搜索框旁的命令参数输入行，并计算其尺寸与 Tab 焦点顺序。
// 分层：UI；只依赖 SwiftUI，参数值由上层 Palette 视图的状态提供。
import SwiftUI

/// 搜索框旁的内联参数输入行；持有自己的 `FocusState`，由 Tab 在此与搜索框间移交焦点。
struct CommandArgumentsRow: View {
    @Environment(\.metrics) private var metrics
    let arguments: [ExtensionCommandArgument]
    /// 当前选中命令的图标，作为前导 chip 绘制，使输入框看起来从属于该命令。
    let icon: EntryIcon?
    /// 以参数名为键的 Binding 工厂——实际值存放在 Palette 视图的状态中。
    let value: (String) -> Binding<String>
    @FocusState.Binding var focused: String?
    /// 在输入框内按 ↵ 会运行命令，与在搜索框内按 ↵ 效果一致。
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: metrics.spacing.xs) {
            if let icon {
                EntryIconView(source: icon)
                    .frame(width: Self.height(metrics), height: Self.height(metrics))
            }
            ForEach(arguments, id: \.name) { argument in
                ArgumentField(
                    argument: argument,
                    text: value(argument.name),
                    isFocused: focused == argument.name,
                    onSubmit: onSubmit
                )
                .focused($focused, equals: argument.name)
            }
        }
    }

    /// 单个参数输入框的高度。
    static func height(_ metrics: InterfaceMetrics) -> CGFloat { metrics.scaled(26) }

    /// 表头会把搜索框收缩到恰好剩余的空间。
    static func totalWidth(
        for arguments: [ExtensionCommandArgument], hasIcon: Bool, metrics: InterfaceMetrics
    ) -> CGFloat {
        let fields = arguments.reduce(0) { $0 + fieldWidth(for: $1, metrics: metrics) }
        let gaps = CGFloat(arguments.count + (hasIcon ? 0 : -1)) * metrics.spacing.xs
        return fields + gaps + (hasIcon ? height(metrics) : 0)
    }

    /// 按占位符文本长度推算单个输入框宽度，并限制在最小/最大宽度之间。
    static func fieldWidth(
        for argument: ExtensionCommandArgument, metrics: InterfaceMetrics
    )
        -> CGFloat
    {
        let placeholder = CGFloat(argument.placeholder.count) * metrics.scaled(7)
        return min(max(placeholder + metrics.scaled(20), metrics.scaled(62)), metrics.scaled(150))
    }

    /// Tab 键的遍历顺序：搜索框（nil）→ 各参数 → 回到搜索框。
    static func next(after current: String?, in arguments: [ExtensionCommandArgument]) -> String? {
        guard let current, let index = arguments.firstIndex(where: { $0.name == current }) else {
            return arguments.first?.name
        }
        let following = arguments.index(after: index)
        return following < arguments.endIndex ? arguments[following].name : nil
    }
}

/// 单个参数的文本输入框，负责焦点/悬停/必填状态下的外观。
private struct ArgumentField: View {

    @Environment(\.metrics) private var metrics
    let argument: ExtensionCommandArgument
    @Binding var text: String
    let isFocused: Bool
    let onSubmit: () -> Void
    @State private var hovered = false

    var body: some View {
        TextField(
            "", text: $text,
            prompt: Text(argument.placeholder).foregroundStyle(Theme.Colors.textTertiary)
        )
        .textFieldStyle(.plain)
        .font(metrics.typography.rowTrailing)
        .tint(.white)
        .onSubmit(onSubmit)
        // 按占位符长度设定尺寸，使带三个参数的命令仍能容纳。
        .frame(width: CommandArgumentsRow.fieldWidth(for: argument, metrics: metrics))
        .padding(.horizontal, metrics.spacing.sm)
        .frame(height: CommandArgumentsRow.height(metrics))
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .strokeBorder(stroke, lineWidth: 1)
        )
        .onHover { hovered = $0 }
        .help(argument.required ? "\(argument.placeholder) — required" : argument.placeholder)
    }

    private var fill: Color {
        if isFocused { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return ExtensionColors.fieldFill
    }

    /// 获得焦点时描边更亮；必填参数未填写时保持琥珀色。
    private var stroke: Color {
        if isFocused { return ExtensionColors.fieldFocusStroke }
        if argument.required && text.isEmpty { return Color.orange.opacity(0.45) }
        return ExtensionColors.fieldStroke
    }
}
