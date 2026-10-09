// 文件职责：为扩展表单控件提供统一的边框/填充/焦点外观（ViewModifier），以及 disclosure chevron 与 picker 行视图。
// 分层：UI；外观集中于此以保证表单各行一致。
import SwiftUI

/// 表单绘制的统一控件表面，放在此处而非 `DesignSystem`。
struct ExtensionFieldChrome: ViewModifier {
    private var form: ExtensionFormMetrics { ExtensionFormMetrics(scale: metrics.scale) }
    @Environment(\.metrics) private var metrics
    var focused: Bool
    /// 打开 popover 的控件，在 popover 持有键盘时仍保持焦点描边。
    var open = false
    /// 指针下高亮，使可点击的控件在被点击前就表明可点。
    var hovered = false
    /// 单行控件的文本居中；文本域从顶部开始向下增长。
    var multiline = false

    /// 控件高度：单行控件与文本域不同。
    private var height: CGFloat {
        multiline ? form.textAreaHeight : form.controlHeight
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, form.textInset)
            // 两个方向使用同一内边距，使文本域首行与输入框对齐。
            .padding(.vertical, form.verticalInset)
            .frame(
                width: form.controlWidth, height: height,
                alignment: multiline ? .topLeading : .leading
            )
            .background(
                RoundedRectangle(
                    cornerRadius: metrics.radius.row, style: .continuous
                )
                .fill(fill)
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: metrics.radius.row, style: .continuous
                )
                .strokeBorder(stroke, lineWidth: 1)
            )
            // 表单自行绘制焦点描边，因此 AppKit 的蓝色聚焦环会是多余的第二层。
            .focusEffectDisabled()
    }

    /// 按焦点与悬停状态决定填充色。
    private var fill: Color {
        hovered && !focused ? ExtensionColors.fieldHoverFill : ExtensionColors.fieldFill
    }

    /// 按焦点、弹层开启与悬停状态决定描边色。
    private var stroke: Color {
        if focused || open { return ExtensionColors.fieldFocusStroke }
        return hovered ? ExtensionColors.fieldHoverStroke : ExtensionColors.fieldStroke
    }
}

extension View {
    /// 统一的控件表面，使表单每一行对齐并看起来属于同一类。
    func extensionFieldChrome(
        focused: Bool, open: Bool = false, hovered: Bool = false, multiline: Bool = false
    ) -> some View {
        modifier(
            ExtensionFieldChrome(
                focused: focused, open: open, hovered: hovered, multiline: multiline))
    }
}

/// 打开 popover 的控件所带的 chevron，指向其展开方向。
struct ExtensionDisclosureChevron: View {
    @Environment(\.metrics) private var metrics
    let open: Bool
    var flipped = false

    var body: some View {
        // 收起时始终朝下；展开时朝上，指回它弹出的列表。
        Image(systemName: pointsUp ? "chevron.up" : "chevron.down")
            .font(metrics.typography.disclosure)
            .foregroundStyle(Theme.Colors.textSecondary)
    }

    /// 展开时 chevron 朝上（除非被 flipped 反转）。
    private var pointsUp: Bool { open && !flipped }
}

/// picker popover 中的一行：可选图标、标题与末尾详情。
struct ExtensionPickerRow: View {
    private var form: ExtensionFormMetrics { ExtensionFormMetrics(scale: metrics.scale) }
    @Environment(\.metrics) private var metrics
    let title: String
    var detail: String?
    var icon: ExtensionImage.Resolved?
    /// 多选 picker 会标记已选项。
    var checked = false
    let selected: Bool
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: metrics.spacing.md) {
                if let icon {
                    ExtensionIconView(
                        resolved: icon, size: metrics.size.menuIcon, usesMenuSymbolStyle: true)
                }
                Text(title)
                    .font(metrics.typography.menuRow)
                    .lineLimit(1)
                Spacer(minLength: metrics.spacing.sm)
                if let detail {
                    Text(detail)
                        .font(metrics.typography.menuShortcut)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if checked {
                    Image(systemName: "checkmark")
                        .font(metrics.typography.disclosure)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .padding(.horizontal, metrics.spacing.md)
            // 固定高度而非用 padding：高度计算按行计数，因此每行必须是精确的单一高度。
            .frame(
                maxWidth: .infinity, minHeight: form.popoverRowHeight,
                maxHeight: form.popoverRowHeight, alignment: .leading
            )
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.menuRow, style: .continuous)
                    .fill(selected ? Theme.Colors.menuHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
