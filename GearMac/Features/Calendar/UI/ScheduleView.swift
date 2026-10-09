// 文件职责：My Schedule 的日程列表视图：按天分组渲染日期标题与会议行，并处理选中/悬停/滚动跟随。
// 分层：UI（SwiftUI）；仅负责展示与回调，行的具体动作由 ScheduleScreen 提供。
import SwiftUI

/// My Schedule 列表，按天分组。
struct ScheduleList: View {
    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    let results: [MeetingEvent]
    let selectedID: MeetingEvent.ID?
    let now: Date
    let scroll: ScrollIntent
    let onActivate: (MeetingEvent) -> Void
    let onActions: (MeetingEvent) -> Void

    /// 列表行：日期分组标题或会议行。
    private enum Row: Identifiable {
        case header(String)
        case meeting(MeetingEvent)
        var id: String {
            switch self {
            case .header(let title): return "header-" + title
            case .meeting(let meeting): return meeting.id
            }
        }
    }

    /// 按天分组展开后的行序列（日期标题 + 各会议）。
    private var rows: [Row] {
        MeetingDayGroup.grouping(results, now: now, calendar: .current).flatMap { group in
            [
                .header(
                    group.day.localizedTitle(
                        calendar: .current, language: settings.language))
            ] + group.meetings.map(Row.meeting)
        }
    }

    /// 当前选中项是否为列表首行（用于滚动锚点判断）。
    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == results.first?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        switch row {
                        case .header(let title):
                            SectionHeader(title: title, isFirst: row.id == rows.first?.id)
                        case .meeting(let meeting):
                            MeetingRow(
                                meeting: meeting, now: now, selected: meeting.id == selectedID
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { onActivate(meeting) }
                            .onRightClick { onActions(meeting) }
                            .selectionFrame(meeting.id == selectedID)
                        }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedID, atOrigin: firstRowSelected, proxy: proxy)
        }
    }
}

/// 日程列表中的单行会议。
private struct MeetingRow: View {

    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    let meeting: MeetingEvent
    let now: Date
    let selected: Bool
    @State private var hovered = false

    /// 行背景填充色：选中 > 悬停 > 透明。
    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            SymbolImage(
                name: meeting.link?.provider.sfSymbol ?? "calendar", size: metrics.size.resultRowIcon * 0.7
            )
            .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            .foregroundStyle(meeting.isInProgress(now: now) ? Theme.Colors.brand : .secondary)
            CalendarBar(color: meeting.calendarColor)
            Text(meeting.localizedTitle(settings.language))
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
            Spacer(minLength: metrics.spacing.md)
            MeetingTiming(meeting: meeting, now: now)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    /// 无障碍朗读文本：标题、时间、倒计时胶囊与日历名。
    private var accessibilityText: String {
        let parts = [
            meeting.localizedTitle(settings.language), MeetingTimeFormat.range(of: meeting),
            UpcomingWindow.rowPill(
                for: meeting, now: now, calendar: .current, language: settings.language)?.text,
            meeting.calendarName
        ]
        return parts.compactMap(\.self).joined(separator: ", ")
    }
}
