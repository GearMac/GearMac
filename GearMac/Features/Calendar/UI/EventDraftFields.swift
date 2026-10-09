// 文件职责：新建事件对话框的表单字段与草稿状态容器（标题、开始时间、时长）。
// 分层：UI（SwiftUI）；表单通过引用语义的 EventDraftState 双向绑定，调用方可在对话框关闭后读回结果。
import SwiftUI

/// 新建事件对话框所编辑的草稿；使用引用语义，调用方才能把编辑结果读回。
@MainActor
@Observable
final class EventDraftState {
    var draft = EventDraft()
}

/// 新建事件的表单字段：标题输入框，以及开始时间与时长两组互斥选项。
struct EventDraftFields: View {
    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    @Bindable var state: EventDraftState

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xl) {
            TextField(
                "", text: $state.draft.title,
                prompt: Text(settings.text(CalendarKey.draftEventTitle))
            )
            .dialogTextField()
            ChoiceRow(
                label: settings.text(CalendarKey.draftStarts), values: EventDraft.startOffsets,
                title: { EventDraft.localizedLabel(startOffset: $0, language: settings.language) },
                selection: $state.draft.startOffsetMinutes)
            ChoiceRow(
                label: settings.text(CalendarKey.draftFor), values: EventDraft.durations,
                title: { EventDraft.localizedLabel(duration: $0, language: settings.language) },
                selection: $state.draft.durationMinutes)
        }
    }
}

/// 一行互斥选项按钮，用于开始时间与时长这类单值选择。
private struct ChoiceRow: View {
    @Environment(\.metrics) private var metrics
    let label: String
    let values: [Int]
    let title: (Int) -> String
    @Binding var selection: Int
    @State private var hoveredValue: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            Text(label)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize()

            HStack(spacing: 0) {
                ForEach(values, id: \.self) { value in
                    Button {
                        selection = value
                    } label: {
                        Text(title(value))
                            .font(metrics.typography.rowTrailing)
                            .foregroundStyle(
                                selection == value
                                    ? Theme.Colors.textPrimary : Theme.Colors.textSecondary
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: metrics.size.dialogButtonHeight)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(
                                    cornerRadius: metrics.radius.row, style: .continuous
                                )
                                .fill(fill(for: value)))
                    }
                    .buttonStyle(.plain)
                    .onHover { hoveredValue = $0 ? value : nil }
                    .accessibilityLabel(title(value))
                    .accessibilityAddTraits(
                        selection == value ? [.isButton, .isSelected] : .isButton)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                    .fill(Theme.Colors.controlSurface))
        }
    }

    /// 根据选中/悬停状态返回按钮填充色。
    private func fill(for value: Int) -> Color {
        if selection == value { return Theme.Colors.selection }
        if hoveredValue == value { return Theme.Colors.rowHover }
        return .clear
    }
}
