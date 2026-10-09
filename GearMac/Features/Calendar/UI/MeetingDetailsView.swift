// 文件职责：会议详情页的内容渲染：标题头、地点、与会者列表与邀请正文。
// 分层：UI（SwiftUI）；只读展示传入的 MeetingEvent 与 MeetingDetails，不发起任何副作用。
import SwiftUI

/// 会议详情页：标题头、地点、与会者，最后是邀请原文。
struct MeetingDetailsView: View {
    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    let meeting: MeetingEvent
    let details: MeetingDetails

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: metrics.spacing.md) {
                header
                if let location = details.location {
                    HStack(alignment: .firstTextBaseline, spacing: metrics.spacing.sm) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text(location)
                    }
                    .font(metrics.typography.rowTitle)
                    .padding(.top, metrics.spacing.xl)
                }
                if !details.attendees.isEmpty {
                    sectionHeader(settings.text(CalendarKey.detailsAttendees))
                    ForEach(details.attendees.indices, id: \.self) { index in
                        AttendeeRow(attendee: details.attendees[index])
                    }
                }
                if let notes = details.notes {
                    sectionHeader(settings.text(CalendarKey.detailsDescription))
                    Text(notes)
                        .font(metrics.typography.rowTitle)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .textSelection(.enabled)
            .padding(.horizontal, metrics.spacing.xxl)
            .padding(.top, metrics.spacing.md)
            .padding(.bottom, metrics.spacing.xxl)
            .hideNativeScrollers()
        }
        .edgeDissolve()
        .thinScrollbar()
        // 切换会议时从标题开始展示，而不是停留在上一个会议的滚动位置。
        .id(meeting.id)
    }

    /// 详情页顶部：来源图标、标题与时间副标题。
    private var header: some View {
        HStack(spacing: metrics.spacing.xl) {
            SymbolImage(
                name: meeting.link?.provider.sfSymbol ?? "calendar",
                size: metrics.size.headerIconSlot
            )
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                Text(meeting.localizedTitle(settings.language))
                    .font(metrics.typography.calcResult.weight(.semibold))
                HStack(spacing: metrics.spacing.sm) {
                    if let tint = meeting.calendarColor { ColorDot(color: tint.color) }
                    Text(subtitle)
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 副标题：日期 · 时间范围 · 日历名称。
    private var subtitle: String {
        let day = UpcomingWindow.dayLabel(meeting.start, calendar: .current)
        return "\(day) · \(MeetingTimeFormat.range(of: meeting)) · \(meeting.calendarName)"
    }

    /// 区块标题及其下方的分隔线。
    private func sectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            Text(title)
                .font(metrics.typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textTertiary)
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(height: 1)
        }
        .padding(.top, metrics.spacing.xl)
    }
}

/// 一行与会者：响应状态图标、姓名、组织者标记与响应文案。
private struct AttendeeRow: View {
    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    let attendee: MeetingDetails.Attendee

    var body: some View {
        HStack(spacing: metrics.spacing.sm) {
            Image(systemName: attendee.response.symbol)
                .foregroundStyle(attendee.response.tint)
            Text(attendee.name)
                .lineLimit(1)
            if attendee.isOrganizer {
                Text(settings.text(CalendarKey.detailsOrganizer))
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            Spacer(minLength: metrics.spacing.md)
            Text(attendee.response.localizedLabel(settings.language))
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .font(metrics.typography.rowTitle)
        .accessibilityElement(children: .combine)
    }
}

/// 与会者响应状态的展示映射：符号、颜色与文案。
private extension MeetingDetails.Attendee.Response {
    /// 响应状态对应的 SF Symbol 名称。
    var symbol: String {
        switch self {
        case .accepted: "checkmark.circle.fill"
        case .tentative: "questionmark.circle.fill"
        case .declined: "xmark.circle.fill"
        case .pending: "circle.dashed"
        }
    }

    /// 响应状态对应的强调色。
    var tint: Color {
        switch self {
        case .accepted: Theme.Colors.success
        case .tentative: Theme.Colors.warning
        case .declined: Theme.Colors.destructive
        case .pending: Theme.Colors.textTertiary
        }
    }

    /// 响应状态对应的展示文案（英文）；保留给尚未迁移的调用点。
    var label: String {
        switch self {
        case .accepted: "Accepted"
        case .tentative: "Maybe"
        case .declined: "Declined"
        case .pending: "No response"
        }
    }

    /// 按界面语言给出的响应文案。
    func localizedLabel(_ language: AppLanguage) -> String {
        let key: CalendarKey =
            switch self {
            case .accepted: .detailsAccepted
            case .tentative: .detailsMaybe
            case .declined: .detailsDeclined
            case .pending: .detailsNoResponse
            }
        return L10n.string(key, language: language)
    }
}
