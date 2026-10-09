// 文件职责：日历在菜单栏的 UI，包括状态栏标签、菜单栏下拉菜单（日历动作 + 仅日程）以及着色符号图像。
// 分层：UI（SwiftUI）；通过 AppCore.shared 只观察菜单栏标签所需的状态，不直接持有业务对象。
import SwiftUI

/// 在此读取 coordinator，可把 Observation 的观察范围限定在日历标签，而不是整个场景。
struct CalendarMenuBarLabel: View {
    let appName: String

    /// 菜单栏的显示模式（图标 / 标题 / 禁用）。
    private var display: CalendarMenuBarDisplay { AppCore.shared.settings.calendarMenuBarDisplay }
    /// 菜单栏当前承载的会议，nil 表示显示普通图标。
    private var meeting: MeetingEvent? { AppCore.shared.calendarCoordinator.menuBarEvent }

    var body: some View {
        switch (display, meeting) {
        case (.disabled, _):
            EmptyView()
        case (.meetingIcon, let meeting?):
            icon(
                meeting.link?.provider.sfSymbol ?? "calendar",
                describing: meeting.localizedTitle(AppCore.shared.settings.language))
        case (.meetingTitle, let meeting?):
            HStack(spacing: Theme.Spacing.xs) {
                if let color = meeting.calendarColor {
                    Image(nsImage: color.menuBarDot).accessibilityHidden(true)
                }
                title(summary(for: meeting))
            }
        case (.meetingTitle, nil)
        where !AppCore.shared.calendarCoordinator.hasUpcomingMenuBarEvent:
            title(text(.menuBarNoUpcoming))
        case (_, nil):
            icon("calendar", describing: text(.menuBarNoCurrentMeeting))
        }
    }

    /// 设置中的当前语言。
    private var language: AppLanguage { AppCore.shared.settings.language }

    /// 设置中的当前语言下取一句话。
    private func text(_ key: CalendarKey) -> String {
        AppCore.shared.settings.text(key)
    }

    /// 生成带无障碍描述的图标视图。
    private func icon(_ symbol: String, describing description: String) -> some View {
        Image(systemName: symbol).accessibilityLabel("\(appName): \(description)")
    }

    /// 生成带无障碍描述的文本视图。
    private func title(_ text: String) -> some View {
        Text(text).accessibilityLabel("\(appName): \(text)")
    }

    /// 组合菜单栏标题与倒计时。
    private func summary(for meeting: MeetingEvent) -> String {
        let countdown = UpcomingWindow.menuBarCountdown(
            for: meeting, now: AppCore.shared.meetingClock.now,
            language: AppCore.shared.settings.language)
        return "\(MenuBarSummary.title(meeting.localizedTitle(AppCore.shared.settings.language))) • \(countdown)"
    }
}

/// 仅包含日历动作：启动器条目承载应用菜单，两者互不重复。
struct CalendarMenuBarMenu: View {
    var body: some View {
        // macOS 菜单默认会丢弃标签的图标，除非样式显式要求保留。
        Group {
            let coordinator = AppCore.shared.calendarCoordinator
            if let meeting = coordinator.menuBarEvent {
                Section {
                    if let link = meeting.link {
                        Button(
                            String(
                                format: AppCore.shared.settings.text(
                                    CalendarKey.actionJoinNamedFormat),
                                meeting.localizedTitle(AppCore.shared.settings.language)),
                            systemImage: link.provider.sfSymbol
                        ) {
                            coordinator.join(meeting)
                        }
                    }
                    Button(
                        AppCore.shared.settings.text(CalendarKey.actionOpenInCalendar),
                        systemImage: "calendar"
                    ) {
                        coordinator.openInCalendar(meeting)
                    }
                    Button(
                        AppCore.shared.settings.text(CalendarKey.actionDismissEvent),
                        systemImage: "xmark.circle"
                    ) {
                        coordinator.dismissMenuBarEvent(meeting)
                    }
                }
            }
            MenuBarAgenda()
            Section {
                Button(
                    AppCore.shared.settings.text(CalendarKey.actionMySchedule),
                    systemImage: "calendar.day.timeline.left"
                ) {
                    coordinator.showSchedule()
                }
                .keyboardShortcut("o")
                Button(
                    AppCore.shared.settings.text(CalendarKey.actionCalendarSettings),
                    systemImage: "gearshape"
                ) {
                    AppCore.shared.settingsCoordinator.showSettings(tab: .calendar)
                }
                .keyboardShortcut(",")
            }
        }
        .labelStyle(.titleAndIcon)
    }
}

/// 按天列出时间跨度内剩余的会议；点击加入，无链接的则在系统日历中打开。
private struct MenuBarAgenda: View {
    var body: some View {
        let now = AppCore.shared.meetingClock.now
        ForEach(AppCore.shared.calendarCoordinator.menuBarAgenda) { group in
            Section(
                group.day.localizedTitle(
                    calendar: .current, language: AppCore.shared.settings.language)
            ) {
                ForEach(group.meetings) { meeting in
                    Button {
                        AppCore.shared.calendarCoordinator.join(meeting)
                    } label: {
                        Label {
                            Text(
                                "\(MeetingTimeFormat.range(of: meeting)) "
                                    + meeting.localizedTitle(
                                        AppCore.shared.settings.language))
                        } icon: {
                            CalendarSymbol(
                                name: meeting.isInProgress(now: now) ? "circle.fill" : "circle",
                                color: meeting.calendarColor)
                        }
                    }
                }
            }
        }
    }
}

/// 使用事件日历颜色的符号，否则菜单会像处理文本一样把它染成单色。
private struct CalendarSymbol: View {
    let name: String
    let color: MeetingEvent.CalendarColor?

    var body: some View {
        if let image = color?.menuSymbol(name) {
            Image(nsImage: image)
        } else {
            Image(systemName: name)
        }
    }
}

/// 两个图像都不是模板图，因此状态栏及其菜单会保留颜色而不会将其染成单色。
extension MeetingEvent.CalendarColor {
    /// 状态栏使用的实心圆点图像（非模板图）。
    fileprivate var menuBarDot: NSImage {
        let size = NSSize(width: Theme.Size.colorDot, height: Theme.Size.colorDot)
        let image = NSImage(size: size, flipped: false) { rect in
            nsColor.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    /// 为指定 SF Symbol 应用日历颜色，返回非模板图。
    fileprivate func menuSymbol(_ name: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .regular
        ).applying(NSImage.SymbolConfiguration(paletteColors: [nsColor]))
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = false
        return image
    }
}
