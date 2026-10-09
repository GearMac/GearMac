// 文件职责：会议的展示与动作：启动器上方的加入卡片、统一的时间格式化，以及卡片/列表行/详情页共用的会议动作菜单。
// 分层：UI（SwiftUI）；会议时间的文本化统一走 MeetingTimeFormat，保证各处展示一致。
import SwiftUI

/// 启动器结果上方的加入卡片；可像列表行一样选中，回车即加入。
struct MeetingCard: View {
    @Environment(\.metrics) private var metrics
    @Environment(AppSettings.self) private var settings
    let meeting: MeetingEvent
    let now: Date
    let selected: Bool

    var body: some View {
        HStack(spacing: metrics.spacing.xl) {
            SymbolImage(
                name: meeting.link?.provider.sfSymbol ?? "calendar",
                size: metrics.size.headerIconSlot
            )
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: metrics.spacing.xs) {
                Text(meeting.localizedTitle(settings.language))
                    .font(metrics.typography.calcResult.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack(spacing: metrics.spacing.sm) {
                    if let tint = meeting.calendarColor { ColorDot(color: tint.color) }
                    Text(subtitle)
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: metrics.spacing.md)
            Text(
                UpcomingWindow.countdown(
                    to: meeting.start, now: now, language: settings.language))
                .font(metrics.typography.rowTitle.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, metrics.spacing.md)
                .padding(.vertical, metrics.spacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: metrics.radius.keyCap, style: .continuous)
                        .fill(Theme.Colors.controlSurface)
                )
        }
        .padding(.horizontal, metrics.spacing.xl)
        .padding(.vertical, metrics.spacing.xxl)
        .leadCard(selected: selected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(meeting.localizedTitle(settings.language)), \(subtitle), "
                + UpcomingWindow.countdown(
                    to: meeting.start, now: now, language: settings.language)
        )
        .accessibilityAddTraits(.isButton)
    }

    /// 副标题：时间范围，并在有会议来源时附加来源名称。
    private var subtitle: String {
        let time = MeetingTimeFormat.range(of: meeting)
        guard let provider = meeting.link?.provider else { return time }
        return "\(time) · \(provider.localizedTitle(settings.language))"
    }
}

/// 会议时间转文本的唯一入口，使卡片与日程行不会出现格式分歧。
@MainActor
enum MeetingTimeFormat {
    private static let formatter: Date.FormatStyle = .dateTime.hour().minute()

    /// 把日期格式化为时:分。
    static func clock(_ date: Date) -> String { date.formatted(formatter) }

    /// 使用两个时钟而非区间样式：区间样式会丢掉共用的上午/下午标记，并把午夜带上日期。
    static func range(of meeting: MeetingEvent) -> String {
        "\(clock(meeting.start)) – \(clock(meeting.end))"
    }
}

extension MeetingEvent.CalendarColor {
    /// 转换为 SwiftUI 颜色。
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
    /// 转换为 AppKit 颜色。
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
}

/// 会议动作集合，供卡片、各启动器条目、日程行与详情页共用。
@MainActor
enum MeetingActionsMenu {
    /// 构建会议弹出菜单内容（加入/复制链接/在日历打开/显示详情）。
    static func content(
        meeting: MeetingEvent, core: AppCore, offersDetails: Bool = true
    ) -> PopoverMenuContent {
        var items: [PopoverMenuItem] = []
        if meeting.link != nil {
            items.append(
                PopoverMenuItem(
                    title: core.settings.text(CalendarKey.actionJoinMeeting),
                    systemImage: "video.fill", shortcut: "↵"
                ) {
                    core.calendarCoordinator.join(meeting)
                })
            items.append(
                PopoverMenuItem(
                    title: core.settings.text(CalendarKey.actionCopyMeetingLink),
                    systemImage: "link", shortcut: "⌘↵"
                ) {
                    core.calendarCoordinator.copyLink(meeting)
                })
        }
        items.append(
            PopoverMenuItem(
                title: core.settings.text(CalendarKey.actionOpenInCalendar),
                systemImage: "calendar", startsSection: true,
                shortcut: meeting.link == nil ? "↵" : "⌘O"
            ) {
                core.calendarCoordinator.openInCalendar(meeting)
            })
        if offersDetails {
            items.append(
                PopoverMenuItem(
                    title: core.settings.text(CalendarKey.actionShowDetails),
                    systemImage: "info.circle", shortcut: "⌘I"
                ) {
                    core.calendarCoordinator.showDetails(of: meeting)
                })
        }
        return PopoverMenuContent(
            header: meeting.localizedTitle(core.settings.language), items: items)
    }

    /// ⌘↵ 处理：无链接的会议返回 false，让该按键不被消费。
    static func secondary(meeting: MeetingEvent, core: AppCore) -> Bool {
        guard meeting.link != nil else { return false }
        core.calendarCoordinator.copyLink(meeting)
        return true
    }

    /// 按快捷键执行对应动作；无法处理时返回 false。
    static func perform(
        _ shortcut: PaletteShortcut, meeting: MeetingEvent, core: AppCore, offersDetails: Bool = true
    ) -> Bool {
        switch shortcut {
        case .openInApp:
            core.calendarCoordinator.openInCalendar(meeting)
        case .showDetails where offersDetails:
            core.calendarCoordinator.showDetails(of: meeting)
        default:
            return false
        }
        return true
    }
}
