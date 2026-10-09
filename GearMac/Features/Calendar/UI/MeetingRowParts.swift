// 文件职责：会议列表行的可复用组件：日历颜色竖条、时间+倒计时胶囊，以及按条目 ID 实时解析会议的容器。
// 分层：UI（SwiftUI）；条目容器直接从 Environment 读取 CalendarStore 与 MeetingClock，不依赖重新发布。
import SwiftUI

/// 会议行图标与标题之间的日历颜色竖条。
struct CalendarBar: View {
    @Environment(\.metrics) private var metrics
    let color: MeetingEvent.CalendarColor?

    var body: some View {
        Capsule()
            .fill(color?.color ?? .clear)
            .frame(width: metrics.size.calendarBarWidth, height: metrics.size.calendarBarHeight)
            .accessibilityHidden(true)
    }
}

/// 时间范围，以及始终预留位置的倒计时胶囊，使各行的胶囊排成一列。
struct MeetingTiming: View {
    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    let meeting: MeetingEvent
    let now: Date

    var body: some View {
        let pill = UpcomingWindow.rowPill(
            for: meeting, now: now, calendar: .current, language: settings.language)
        HStack(spacing: metrics.spacing.md) {
            Text(MeetingTimeFormat.range(of: meeting))
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(meeting.isInProgress(now: now) ? .primary : .secondary)
            ZStack {
                Text(
                    UpcomingWindow.countdown(
                        to: now + 60 * 60, now: now, language: settings.language)
                ).hidden()
                Text(UpcomingWindow.dayLabel(now + 24 * 60 * 60, calendar: .current)).hidden()
                Text(pill?.text ?? "")
                    .foregroundStyle(pill?.isImminent == true ? .primary : .secondary)
            }
            .font(metrics.typography.rowTrailing.weight(.medium))
            .padding(.horizontal, metrics.spacing.sm)
            .padding(.vertical, metrics.spacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: metrics.radius.keyCap, style: .continuous)
                    .fill(pill == nil ? .clear : Theme.Colors.controlSurface))
        }
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
    }
}

/// 实时解析启动器中的会议条目，使其色条与倒计时无需等待重新发布。
struct MeetingEntryContent<Content: View>: View {
    @Environment(CalendarStore.self) private var store
    @Environment(MeetingClock.self) private var clock
    let entryID: String
    @ViewBuilder let content: (MeetingEvent, Date) -> Content

    var body: some View {
        if let id = MeetingEvent.id(fromEntryID: entryID), let meeting = store.event(id: id) {
            content(meeting, clock.now)
        }
    }
}
