// 文件职责：日历功能的本地化键与中英词表。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 日历设置、菜单栏、日程页与提示文案的键。
enum CalendarKey: String, LocalizableKey {
    // MARK: - 设置

    case settingsEnable = "calendar.settings.enable"
    case settingsEnableSubtitle = "calendar.settings.enableSubtitle"
    case settingsLauncherLimit = "calendar.settings.launcherLimit"
    case settingsAccessNeededTitle = "calendar.settings.accessNeededTitle"
    case settingsAccessNeededSubtitle = "calendar.settings.accessNeededSubtitle"
    case settingsAllowAccess = "calendar.settings.allowAccess"
    case settingsAccessOffTitle = "calendar.settings.accessOffTitle"
    case settingsAccessOffSubtitle = "calendar.settings.accessOffSubtitle"
    case settingsOpenSystemSettings = "calendar.settings.openSystemSettings"
    case settingsShowJoinCard = "calendar.settings.showJoinCard"
    case settingsShowJoinCardSubtitle = "calendar.settings.showJoinCardSubtitle"
    case settingsAutoJoin = "calendar.settings.autoJoin"
    case settingsAutoJoinSubtitle = "calendar.settings.autoJoinSubtitle"
    case settingsKnownProvidersOnly = "calendar.settings.knownProvidersOnly"
    case settingsConfirmBeforeJoining = "calendar.settings.confirmBeforeJoining"
    case settingsCameraPreview = "calendar.settings.cameraPreview"
    case settingsCameraPreviewSubtitle = "calendar.settings.cameraPreviewSubtitle"
    case settingsOpenLinksIn = "calendar.settings.openLinksIn"
    case settingsOpenLinksInSubtitle = "calendar.settings.openLinksInSubtitle"
    case settingsMenuBar = "calendar.settings.menuBar"
    case settingsMenuBarSubtitle = "calendar.settings.menuBarSubtitle"
    case settingsDaysToShow = "calendar.settings.daysToShow"
    case settingsDaysToShowSubtitle = "calendar.settings.daysToShowSubtitle"
    case settingsUpcomingEvents = "calendar.settings.upcomingEvents"
    case settingsUpcomingEventsSubtitle = "calendar.settings.upcomingEventsSubtitle"
    case settingsLinkedOnly = "calendar.settings.linkedOnly"
    case settingsHideWhenEmpty = "calendar.settings.hideWhenEmpty"
    case settingsHideCurrentEvent = "calendar.settings.hideCurrentEvent"
    case settingsHideCurrentEventSubtitle = "calendar.settings.hideCurrentEventSubtitle"
    case settingsDefaultBrowser = "calendar.settings.defaultBrowser"
    case settingsSearchCalendars = "calendar.settings.searchCalendars"
    case settingsNoMatchesFormat = "calendar.settings.noMatches"
    case settingsNoCalendars = "calendar.settings.noCalendars"
    case settingsNothingToShow = "calendar.settings.nothingToShow"
    case settingsIncludeCalendarFormat = "calendar.settings.includeCalendar"

    // MARK: - 设置里的枚举选项（枚举本身定义在 AppSettings 中）

    case optionLauncherLimitOne = "calendar.option.launcherLimit.one"
    case optionLauncherLimitThree = "calendar.option.launcherLimit.three"
    case optionLauncherLimitFive = "calendar.option.launcherLimit.five"
    case optionLauncherLimitAll = "calendar.option.launcherLimit.all"
    case optionJoinWindowOne = "calendar.option.joinWindow.one"
    case optionJoinWindowMany = "calendar.option.joinWindow.many"
    case optionMenuBarEventsToday = "calendar.option.menuBarEvents.today"
    case optionMenuBarEventsBefore = "calendar.option.menuBarEvents.before"
    case optionMenuBarDisabled = "calendar.option.menuBar.disabled"
    case optionMenuBarIcon = "calendar.option.menuBar.icon"
    case optionMenuBarTitle = "calendar.option.menuBar.title"
    case optionHideCurrentKeepVisible = "calendar.option.hideCurrent.keepVisible"
    case optionHideCurrentAutomatically = "calendar.option.hideCurrent.automatically"
    case optionHideCurrentAfter = "calendar.option.hideCurrent.after"

    // MARK: - 时间跨度

    case spanToday = "calendar.span.today"
    case spanTodayAndTomorrow = "calendar.span.todayAndTomorrow"
    case spanNextSevenDays = "calendar.span.nextSevenDays"
    case spanPossessiveToday = "calendar.span.possessiveToday"
    case spanPossessiveTodayAndTomorrow = "calendar.span.possessiveTodayAndTomorrow"
    case spanPossessiveNextSevenDays = "calendar.span.possessiveNextSevenDays"
    case spanOrToday = "calendar.span.orToday"
    case spanOrTodayAndTomorrow = "calendar.span.orTodayAndTomorrow"
    case spanOrNextSevenDays = "calendar.span.orNextSevenDays"

    // MARK: - 动作与菜单

    case actionJoinMeeting = "calendar.action.joinMeeting"
    case actionCopyMeetingLink = "calendar.action.copyMeetingLink"
    case actionOpenInCalendar = "calendar.action.openInCalendar"
    case actionShowDetails = "calendar.action.showDetails"
    case actionDismissEvent = "calendar.action.dismissEvent"
    case actionJoinNamedFormat = "calendar.action.joinNamed"
    case actionJoinConfirmFormat = "calendar.action.joinConfirm"
    case actionJoin = "calendar.action.join"
    case actionNotNow = "calendar.action.notNow"
    case actionMySchedule = "calendar.action.mySchedule"
    case actionCalendarSettings = "calendar.action.calendarSettings"

    // MARK: - 详情与表单

    case detailsOrganizer = "calendar.details.organizer"
    case detailsAttendees = "calendar.details.attendees"
    case detailsDescription = "calendar.details.description"
    case detailsAccepted = "calendar.details.accepted"
    case detailsMaybe = "calendar.details.maybe"
    case detailsDeclined = "calendar.details.declined"
    case detailsNoResponse = "calendar.details.noResponse"
    case emptyMeetingGone = "calendar.empty.meetingGone"
    case eventNoTitle = "calendar.event.noTitle"
    case draftEventTitle = "calendar.draft.eventTitle"
    case draftStarts = "calendar.draft.starts"
    case draftFor = "calendar.draft.for"
    case draftNow = "calendar.draft.now"
    case draftMinutesFormat = "calendar.draft.minutes"
    case draftHoursFormat = "calendar.draft.hours"

    // MARK: - 相对时间

    case timeNow = "calendar.time.now"
    case timeInFormat = "calendar.time.in"
    case timeLeftFormat = "calendar.time.left"
    case timeMinutesFormat = "calendar.time.minutes"
    case timeHoursFormat = "calendar.time.hours"
    case dayTodayFormat = "calendar.time.dayToday"
    case dayTomorrowFormat = "calendar.time.dayTomorrow"
    case menuBarNoUpcoming = "calendar.menuBar.noUpcoming"
    case menuBarNoCurrentMeeting = "calendar.menuBar.noCurrentMeeting"

    // MARK: - 空态与提示

    case emptyNoAccess = "calendar.empty.noAccess"
    case emptyNoMatches = "calendar.empty.noMatches"
    case emptyNothingScheduledFormat = "calendar.empty.nothingScheduled"
    case hudNothingToJoin = "calendar.hud.nothingToJoin"
    case hudCalendarOff = "calendar.hud.calendarOff"
    case hudLinkCopied = "calendar.hud.linkCopied"
    case hudNoLink = "calendar.hud.noLink"
    case hudEventCreated = "calendar.hud.eventCreated"
    case errorEnableTitle = "calendar.error.enableTitle"
    case errorEnableMessage = "calendar.error.enableMessage"
    case errorEnableAction = "calendar.error.enableAction"
    case errorCreateEventTitle = "calendar.error.createEventTitle"
    case errorCreateEventMessage = "calendar.error.createEventMessage"
    case errorOpenLinkTitle = "calendar.error.openLinkTitle"
    case errorOpenLinkMessageFormat = "calendar.error.openLinkMessage"
    case providerGeneric = "calendar.provider.generic"

    static let table: [String: L10nEntry] = [
        CalendarKey.settingsEnable.rawValue: L10nEntry(
            "Join meetings from GearMac", "通过 GearMac 加入会议"),
        CalendarKey.settingsEnableSubtitle.rawValue: L10nEntry(
            "Reads %@ events for join links. Nothing leaves this Mac.",
            "读取%@的日程以查找会议链接，数据不会离开本机。"),
        CalendarKey.errorEnableMessage.rawValue: L10nEntry(
            "GearMac reads %@ events to find join links. Nothing leaves this Mac.",
            "GearMac 读取%@的日程以查找会议链接，数据不会离开本机。"),
        CalendarKey.settingsLauncherLimit.rawValue: L10nEntry(
            "Upcoming meetings in launcher", "启动器中的待开始会议"),
        CalendarKey.settingsAccessNeededTitle.rawValue: L10nEntry(
            "Calendar access is needed", "需要日历访问权限"),
        CalendarKey.settingsAccessNeededSubtitle.rawValue: L10nEntry(
            "Needed to read events and find join links.", "用于读取日程并查找会议链接。"),
        CalendarKey.settingsAllowAccess.rawValue: L10nEntry(
            "Allow Calendar Access…", "允许访问日历…"),
        CalendarKey.settingsAccessOffTitle.rawValue: L10nEntry(
            "Calendar access is off", "日历访问已关闭"),
        CalendarKey.settingsAccessOffSubtitle.rawValue: L10nEntry(
            "Allow it in Privacy & Security ▸ Calendars.", "请在「隐私与安全性 ▸ 日历」中允许。"),
        CalendarKey.settingsOpenSystemSettings.rawValue: L10nEntry(
            "Open System Settings…", "打开系统设置…"),
        CalendarKey.settingsShowJoinCard.rawValue: L10nEntry(
            "Show the join card", "显示加入卡片"),
        CalendarKey.settingsShowJoinCardSubtitle.rawValue: L10nEntry(
            "Before and after a meeting starts.", "会议开始前后展示。"),
        CalendarKey.settingsAutoJoin.rawValue: L10nEntry("Auto Join Meetings", "自动加入会议"),
        CalendarKey.settingsAutoJoinSubtitle.rawValue: L10nEntry(
            "As they start.", "会议开始时自动加入。"),
        CalendarKey.settingsKnownProvidersOnly.rawValue: L10nEntry(
            "Only join known meeting services", "仅加入已知的会议服务"),
        CalendarKey.settingsConfirmBeforeJoining.rawValue: L10nEntry(
            "Confirm before joining", "加入前确认"),
        CalendarKey.settingsCameraPreview.rawValue: L10nEntry("Camera Preview", "摄像头预览"),
        CalendarKey.settingsCameraPreviewSubtitle.rawValue: L10nEntry(
            "Before joining a meeting.", "加入会议前预览。"),
        CalendarKey.settingsOpenLinksIn.rawValue: L10nEntry(
            "Open Meeting Links In", "打开会议链接的应用"),
        CalendarKey.settingsOpenLinksInSubtitle.rawValue: L10nEntry(
            "When no meeting app handles the link.", "当没有会议应用处理该链接时。"),
        CalendarKey.settingsMenuBar.rawValue: L10nEntry(
            "Calendar in Menu Bar", "菜单栏中的日历"),
        CalendarKey.settingsMenuBarSubtitle.rawValue: L10nEntry(
            "Separate from the GearMac icon.", "与 GearMac 图标分开显示。"),
        CalendarKey.settingsDaysToShow.rawValue: L10nEntry("Days to Show", "显示天数"),
        CalendarKey.settingsDaysToShowSubtitle.rawValue: L10nEntry(
            "In the menu, My Schedule and launcher search.", "用于菜单、我的日程与启动器搜索。"),
        CalendarKey.settingsUpcomingEvents.rawValue: L10nEntry(
            "Show Upcoming Events", "显示即将开始的事件"),
        CalendarKey.settingsUpcomingEventsSubtitle.rawValue: L10nEntry(
            "When the next event appears.", "下一场事件何时出现。"),
        CalendarKey.settingsLinkedOnly.rawValue: L10nEntry(
            "Only show events with meetings", "仅显示带会议链接的事件"),
        CalendarKey.settingsHideWhenEmpty.rawValue: L10nEntry(
            "Hide when there are no upcoming events", "没有即将开始的事件时隐藏"),
        CalendarKey.settingsHideCurrentEvent.rawValue: L10nEntry(
            "Hide Current Event", "隐藏当前事件"),
        CalendarKey.settingsHideCurrentEventSubtitle.rawValue: L10nEntry(
            "Once it has started.", "事件开始后隐藏。"),
        CalendarKey.settingsDefaultBrowser.rawValue: L10nEntry("Default Browser", "默认浏览器"),
        CalendarKey.settingsSearchCalendars.rawValue: L10nEntry("Search calendars…", "搜索日历…"),
        CalendarKey.settingsNoMatchesFormat.rawValue: L10nEntry(
            "No matches for “%@”.", "没有匹配“%@”的日历。"),
        CalendarKey.settingsNoCalendars.rawValue: L10nEntry(
            "No calendars on this Mac.", "本机没有日历。"),
        CalendarKey.settingsNothingToShow.rawValue: L10nEntry(
            "Nothing to show yet.", "暂无可显示的内容。"),
        CalendarKey.settingsIncludeCalendarFormat.rawValue: L10nEntry(
            "Include %@ in meetings", "在会议中包含「%@」"),

        CalendarKey.optionLauncherLimitOne.rawValue: L10nEntry("1 next", "接下来 1 场"),
        CalendarKey.optionLauncherLimitThree.rawValue: L10nEntry("3 next", "接下来 3 场"),
        CalendarKey.optionLauncherLimitFive.rawValue: L10nEntry("5 next", "接下来 5 场"),
        CalendarKey.optionLauncherLimitAll.rawValue: L10nEntry("All", "全部"),
        CalendarKey.optionJoinWindowOne.rawValue: L10nEntry("1 minute", "1 分钟"),
        CalendarKey.optionJoinWindowMany.rawValue: L10nEntry("%d minutes", "%d 分钟"),
        CalendarKey.optionMenuBarEventsToday.rawValue: L10nEntry("Today", "今天"),
        CalendarKey.optionMenuBarEventsBefore.rawValue: L10nEntry(
            "%d minutes before", "提前 %d 分钟"),
        CalendarKey.optionMenuBarDisabled.rawValue: L10nEntry("Disabled", "已关闭"),
        CalendarKey.optionMenuBarIcon.rawValue: L10nEntry("Meeting Icon", "会议图标"),
        CalendarKey.optionMenuBarTitle.rawValue: L10nEntry("Meeting Title", "会议标题"),
        CalendarKey.optionHideCurrentKeepVisible.rawValue: L10nEntry(
            "Keep visible — show time left", "保持显示——展示剩余时间"),
        CalendarKey.optionHideCurrentAutomatically.rawValue: L10nEntry("Automatically", "自动"),
        CalendarKey.optionHideCurrentAfter.rawValue: L10nEntry("%d minutes", "%d 分钟后"),

        CalendarKey.spanToday.rawValue: L10nEntry("Today", "今天"),
        CalendarKey.spanTodayAndTomorrow.rawValue: L10nEntry(
            "Today and Tomorrow", "今天和明天"),
        CalendarKey.spanNextSevenDays.rawValue: L10nEntry("Next 7 Days", "未来 7 天"),
        CalendarKey.spanPossessiveToday.rawValue: L10nEntry("today's", "今天的"),
        CalendarKey.spanPossessiveTodayAndTomorrow.rawValue: L10nEntry(
            "today's and tomorrow's", "今明两天的"),
        CalendarKey.spanPossessiveNextSevenDays.rawValue: L10nEntry(
            "the next 7 days'", "未来 7 天的"),
        CalendarKey.spanOrToday.rawValue: L10nEntry("today", "今天"),
        CalendarKey.spanOrTodayAndTomorrow.rawValue: L10nEntry(
            "today or tomorrow", "今天或明天"),
        CalendarKey.spanOrNextSevenDays.rawValue: L10nEntry(
            "in the next 7 days", "未来 7 天内"),

        CalendarKey.actionJoinMeeting.rawValue: L10nEntry("Join Meeting", "加入会议"),
        CalendarKey.actionCopyMeetingLink.rawValue: L10nEntry("Copy Meeting Link", "复制会议链接"),
        CalendarKey.actionOpenInCalendar.rawValue: L10nEntry("Open in Calendar", "在日历中打开"),
        CalendarKey.actionShowDetails.rawValue: L10nEntry("Show Details", "显示详情"),
        CalendarKey.actionDismissEvent.rawValue: L10nEntry("Dismiss Event", "忽略此事件"),
        CalendarKey.actionJoinNamedFormat.rawValue: L10nEntry("Join %@", "加入 %@"),
        CalendarKey.actionJoinConfirmFormat.rawValue: L10nEntry("Join %@?", "加入 %@？"),
        CalendarKey.actionJoin.rawValue: L10nEntry("Join", "加入"),
        CalendarKey.actionNotNow.rawValue: L10nEntry("Not Now", "暂不"),
        CalendarKey.actionMySchedule.rawValue: L10nEntry("My Schedule", "我的日程"),
        CalendarKey.actionCalendarSettings.rawValue: L10nEntry(
            "Calendar Settings…", "日历设置…"),

        CalendarKey.detailsOrganizer.rawValue: L10nEntry("Organizer", "组织者"),
        CalendarKey.detailsAttendees.rawValue: L10nEntry("Attendees", "与会者"),
        CalendarKey.detailsDescription.rawValue: L10nEntry("Description", "描述"),
        CalendarKey.detailsAccepted.rawValue: L10nEntry("Accepted", "已接受"),
        CalendarKey.detailsMaybe.rawValue: L10nEntry("Maybe", "待定"),
        CalendarKey.detailsDeclined.rawValue: L10nEntry("Declined", "已拒绝"),
        CalendarKey.detailsNoResponse.rawValue: L10nEntry("No response", "未回复"),
        CalendarKey.emptyMeetingGone.rawValue: L10nEntry(
            "This meeting is no longer available", "该会议已不可用"),
        CalendarKey.eventNoTitle.rawValue: L10nEntry("(No Title)", "（无标题）"),
        CalendarKey.draftEventTitle.rawValue: L10nEntry("Event title", "事件标题"),
        CalendarKey.draftStarts.rawValue: L10nEntry("Starts", "开始时间"),
        CalendarKey.draftFor.rawValue: L10nEntry("For", "时长"),
        CalendarKey.draftNow.rawValue: L10nEntry("Now", "现在"),
        CalendarKey.draftMinutesFormat.rawValue: L10nEntry("%d min", "%d 分钟"),
        CalendarKey.draftHoursFormat.rawValue: L10nEntry("%d hr", "%d 小时"),

        CalendarKey.timeNow.rawValue: L10nEntry("Now", "现在"),
        CalendarKey.timeInFormat.rawValue: L10nEntry("in %@", "%@后"),
        CalendarKey.timeLeftFormat.rawValue: L10nEntry("%@ left", "剩余 %@"),
        CalendarKey.timeMinutesFormat.rawValue: L10nEntry("%d min", "%d 分钟"),
        CalendarKey.timeHoursFormat.rawValue: L10nEntry("%d hr", "%d 小时"),
        CalendarKey.dayTodayFormat.rawValue: L10nEntry("Today, %@", "今天，%@"),
        CalendarKey.dayTomorrowFormat.rawValue: L10nEntry("Tomorrow, %@", "明天，%@"),
        CalendarKey.menuBarNoUpcoming.rawValue: L10nEntry(
            "No upcoming events", "暂无即将开始的事件"),
        CalendarKey.menuBarNoCurrentMeeting.rawValue: L10nEntry(
            "no current meeting", "当前没有会议"),

        CalendarKey.emptyNoAccess.rawValue: L10nEntry(
            "GearMac has no access to your calendar", "GearMac 没有日历访问权限"),
        CalendarKey.emptyNoMatches.rawValue: L10nEntry("No matching meetings", "没有匹配的会议"),
        CalendarKey.emptyNothingScheduledFormat.rawValue: L10nEntry(
            "Nothing scheduled %@", "%@没有安排"),
        CalendarKey.hudNothingToJoin.rawValue: L10nEntry(
            "Nothing to join right now", "当前没有可加入的会议"),
        CalendarKey.hudCalendarOff.rawValue: L10nEntry(
            "Turn Calendar on in Settings first", "请先在设置中开启日历"),
        CalendarKey.hudLinkCopied.rawValue: L10nEntry("Meeting link copied", "已复制会议链接"),
        CalendarKey.hudNoLink.rawValue: L10nEntry("This meeting has no link", "该会议没有链接"),
        CalendarKey.hudEventCreated.rawValue: L10nEntry("Event created", "事件已创建"),
        CalendarKey.errorEnableTitle.rawValue: L10nEntry("Enable calendar?", "启用日历？"),
        CalendarKey.errorEnableAction.rawValue: L10nEntry("Continue", "继续"),
        CalendarKey.errorCreateEventTitle.rawValue: L10nEntry(
            "Couldn't create the event", "无法创建事件"),
        CalendarKey.errorCreateEventMessage.rawValue: L10nEntry(
            "No calendar on this Mac accepts new events.", "本机没有可写入新事件的日历。"),
        CalendarKey.errorOpenLinkTitle.rawValue: L10nEntry(
            "Couldn't open the meeting link", "无法打开会议链接"),
        CalendarKey.errorOpenLinkMessageFormat.rawValue: L10nEntry(
            "Nothing on this Mac would open %@.", "本机没有可打开 %@ 的应用。"),
        CalendarKey.providerGeneric.rawValue: L10nEntry("Meeting Link", "会议链接"),
    ]
}
