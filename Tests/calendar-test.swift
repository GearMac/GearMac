// 文件职责：日历与会议链接的独立测试 harness，覆盖会议链接识别、加入窗口、菜单栏摘要、自动加入与事件草稿。
// 分层：测试 harness；直接编译真实源码（MeetingLink / UpcomingWindow / MenuBarSummary / AutoJoinPolicy / EventDraft / MeetingDetails 等），断言失败时以非零退出码结束。
import Foundation

/// 日历与会议链接功能的主测试套件，`main()` 顺序执行全部用例并汇总通过/失败数。
@main
@MainActor
struct CalendarTests {
    static var failures = 0
    static var passes = 0

    /// 所有构造日期的位置都注入该日历，因此任何断言都不依赖运行机器的时区。
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 测试入口：依次运行全部用例，打印通过率，失败时以退出码 1 结束。
    static func main() {
        providerDetection()
        rejectsNonMeetingPages()
        fieldPrecedence()
        linkScanning()
        appURLRewrites()
        accountPrefill()
        agendaFiltering()
        cardWindow()
        chordFallsBackWiderThanTheCard()
        countdownStrings()
        rowPills()
        dayBuckets()
        dayGroups()
        readSpan()
        menuBarWindow()
        menuBarDismissal()
        menuBarFiltering()
        menuBarToday()
        menuBarTitles()
        autoJoinFiresOnce()
        autoJoinRespectsArming()
        autoJoinSkipsBareLinks()
        eventDrafts()
        meetingDetails()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    // MARK: - 服务商识别

    /// 校验各会议服务商域名都能被识别为对应的 Provider。
    static func providerDetection() {
        expect(provider("https://us02web.zoom.us/j/8901234567") == .zoom, "a Zoom /j/ link is Zoom")
        expect(provider("https://zoom.us/w/123?pwd=xy") == .zoom, "a Zoom webinar link is Zoom")
        expect(provider("https://acme.zoomgov.com/j/55") == .zoom, "zoomgov is Zoom")
        expect(
            provider("https://meet.google.com/abc-defg-hij") == .googleMeet,
            "a Meet code is Google Meet")
        expect(
            provider("https://teams.microsoft.com/l/meetup-join/19%3ameeting_Zm8") == .teams,
            "a Teams meetup-join link is Teams")
        expect(provider("https://teams.live.com/meet/9312") == .teams, "a Teams personal link is Teams")
        expect(provider("https://acme.webex.com/acme/j.php?MTID=m1") == .webex, "a Webex site is Webex")
        expect(provider("https://meet.jit.si/DailyStandup") == .jitsi, "meet.jit.si is Jitsi")
        expect(provider("https://8x8.vc/room") == .jitsi, "8x8.vc is Jitsi")
        expect(provider("https://whereby.com/acme") == .whereby, "whereby.com is Whereby")
        expect(provider("https://chime.aws/1234567890") == .chime, "chime.aws is Amazon Chime")
        expect(
            provider("https://global.gotomeeting.com/join/123456789") == .gotoMeeting,
            "gotomeeting.com is GoTo Meeting")
        expect(provider("https://app.goto.com/meeting/xy") == .gotoMeeting, "app.goto.com is GoTo")
        expect(provider("https://bluejeans.com/123456") == .blueJeans, "bluejeans.com is BlueJeans")
        expect(provider("https://join.skype.com/abcdef") == .skype, "join.skype.com is Skype")
        expect(
            provider("https://example.com/rooms/standup") == .generic,
            "an unknown host is still a joinable link")
        expect(MeetingLink.detect(in: "no links here at all") == nil, "plain prose has no link")
        expect(
            MeetingLink.detect(in: "mailto:someone@example.com") == nil,
            "a mailto address is not a join link")
    }

    /// 下载页、拨入辅助页等非会议页面不得被当作可加入的会议链接。
    static func rejectsNonMeetingPages() {
        expect(
            MeetingLink.detect(in: "https://zoom.us/download") == nil,
            "a Zoom download page is not a meeting, and does not fall back to a bare link")
        expect(
            MeetingLink.detect(in: "https://meet.google.com/tel/123") == nil,
            "a Meet dial-in helper is not a meeting")
        expect(
            MeetingLink.detect(in: "https://teams.microsoft.com/downloads") == nil,
            "a Teams download page is not a meeting")
        expect(
            MeetingLink.detect(in: "Join: https://zoom.us/download or https://zoom.us/j/42")?.provider
                == .zoom,
            "a rejected page does not stop the real link being found")
    }

    // MARK: - 链接来自哪个字段

    /// 多个候选字段中，命名的会议服务商优先于更早出现的裸链接。
    static func fieldPrecedence() {
        let link = MeetingLink.detect(fields: [
            "https://example.com/first", "https://meet.google.com/abc-defg-hij"
        ])
        expect(link?.provider == .googleMeet, "a named provider beats a bare link found earlier")
        let bare = MeetingLink.detect(fields: [nil, "https://example.com/room", "https://other.test/x"])
        expect(
            bare?.url.absoluteString == "https://example.com/room",
            "with no named provider the earliest bare link wins")
        expect(MeetingLink.detect(fields: [nil, nil]) == nil, "empty fields yield no link")
    }

    /// 从普通文本中提取 URL 的边界：尾随标点、引号、换行与大小写。
    static func linkScanning() {
        expect(
            MeetingLink.detect(in: "Dial in (https://whereby.com/acme).")?.url.absoluteString
                == "https://whereby.com/acme",
            "trailing punctuation is not part of the URL")
        expect(
            MeetingLink.detect(in: "<a href=\"https://whereby.com/acme\">join</a>")?.url
                .absoluteString == "https://whereby.com/acme",
            "a quoted href yields the URL alone")
        expect(
            MeetingLink.detect(in: "line one\nhttps://whereby.com/acme\nline three")?.url
                .absoluteString == "https://whereby.com/acme",
            "a newline ends the URL")
        expect(
            MeetingLink.detect(in: "HTTPS://WHEREBY.COM/Acme")?.provider == .whereby,
            "the scheme and host match case-insensitively")
    }

    /// 各服务商链接是否改写为桌面 App 的 URL scheme。
    static func appURLRewrites() {
        expect(
            link("https://us02web.zoom.us/j/8901234567")?.appURL?.absoluteString
                == "zoommtg://zoom.us/join?confno=8901234567",
            "a Zoom link rewrites to the desktop app")
        expect(
            link("https://us02web.zoom.us/j/89?pwd=SeCrEt")?.appURL?.absoluteString
                == "zoommtg://zoom.us/join?confno=89&pwd=SeCrEt",
            "the Zoom passcode travels with the rewrite")
        expect(
            link("https://teams.microsoft.com/l/meetup-join/19%3ameeting_Zm8?x=1")?.appURL?
                .absoluteString == "msteams:/l/meetup-join/19%3ameeting_Zm8?x=1",
            "a Teams link rewrites to msteams:, path and query intact")
        expect(
            link("https://meet.google.com/abc-defg-hij")?.appURL == nil,
            "a provider with no unambiguous scheme opens the web instead")
        expect(link("https://example.com/room")?.appURL == nil, "a bare link opens the web")
    }

    /// Meet 链接按承载它的日历账户预填 `authuser`，其它服务商不改写。
    static func accountPrefill() {
        expect(
            hosted("https://meet.google.com/abc-defg-hij", "user@domain.com")?.webURL.absoluteString
                == "https://meet.google.com/abc-defg-hij?authuser=user@domain.com",
            "a Meet link opens as the account whose calendar carried it")
        expect(
            hosted("https://meet.google.com/abc?hs=1", "user@domain.com")?.webURL.absoluteString
                == "https://meet.google.com/abc?hs=1&authuser=user@domain.com",
            "the account joins a query the invite already had")
        expect(
            hosted("https://meet.google.com/abc?authuser=1", "user@domain.com")?.webURL
                .absoluteString == "https://meet.google.com/abc?authuser=1",
            "a link naming its own account is left alone")
        expect(
            hosted("https://meet.google.com/abc", "a+b@domain.com")?.webURL.absoluteString
                == "https://meet.google.com/abc?authuser=a%2Bb@domain.com",
            "a plus in the address is encoded, so it cannot be read as a space")
        expect(
            hosted("https://us02web.zoom.us/j/89", "user@domain.com")?.webURL.absoluteString
                == "https://us02web.zoom.us/j/89",
            "no other provider takes an account in the URL")
        expect(
            hosted("https://meet.google.com/abc-defg-hij", nil)?.webURL.absoluteString
                == "https://meet.google.com/abc-defg-hij",
            "a calendar with no address of its own leaves the link as written")
        expect(
            hosted("https://meet.google.com/abc-defg-hij", "user@domain.com")?.url.absoluteString
                == "https://meet.google.com/abc-defg-hij",
            "the link as written is what Copy Meeting Link keeps")
        expect(
            hosted("https://meet.google.com/abc", participant("mailto:user@domain.com"))?.webURL
                .absoluteString == "https://meet.google.com/abc?authuser=user@domain.com",
            "the current user's mailto address reaches the Meet link as its account")
        expect(
            hosted(
                "https://meet.google.com/abc",
                participant("mailto:user@domain.com", isCurrentUser: false))?.webURL
                .absoluteString == "https://meet.google.com/abc",
            "another participant's address is never used as ours")
        expect(
            participant("mailto:user%40domain.com") == "user@domain.com",
            "a percent-encoded address is decoded once, here")
        expect(
            participant("mailto:a+b@domain.com") == "a+b@domain.com",
            "a plus survives the decode, so accountURL can encode it again")
        expect(
            participant("urn:uuid:1F2A") == nil,
            "a non-mailto participant URL yields no address")
        expect(
            participant("mailto:unknownorganizer@calendar.google.com") != nil,
            "a placeholder organizer address is still an address, left for isCurrentUser to refuse")
    }

    // MARK: - 加入窗口

    /// 议程只保留定时且未拒绝的事件，并按开始时间排序。
    static func agendaFiltering() {
        let events = [
            event(id: "late", start: 60), event(id: "early", start: 0),
            event(id: "allday", start: 30, isAllDay: true),
            event(id: "declined", start: 30, isDeclined: true)
        ]
        let agenda = UpcomingWindow.agenda(from: events, now: at(0))
        expect(agenda.map(\.id) == ["early", "late"], "the agenda is timed, accepted and in start order")

        let over = event(id: "over", start: 0, minutes: 30)
        expect(
            UpcomingWindow.agenda(from: [over], now: at(30)).isEmpty,
            "a meeting is off the agenda the moment it ends, the way it leaves the menu bar")
        expect(
            UpcomingWindow.agenda(from: [over], now: at(29)).map(\.id) == ["over"],
            "one still running stays, however long ago it started")
    }

    /// 卡片窗口的开启与结束边界：提前 `leadMinutes` 出现，开始后按宽限期消失。
    static func cardWindow() {
        let window = UpcomingWindow(leadMinutes: 5)
        let meeting = event(id: "standup", start: 60, minutes: 30)
        let start = at(60)
        expect(
            window.carded(from: [meeting], now: start.addingTimeInterval(-300))?.id == "standup",
            "the card appears exactly five minutes out")
        expect(
            window.carded(from: [meeting], now: start.addingTimeInterval(-301)) == nil,
            "one second earlier it is not there yet")
        expect(
            window.carded(from: [meeting], now: start.addingTimeInterval(299))?.id == "standup",
            "it survives almost five minutes past the start, because everyone joins late")
        expect(
            window.carded(from: [meeting], now: start.addingTimeInterval(300)) == nil,
            "the grace period ends five minutes past the start")

        let brief = event(id: "brief", start: 60, minutes: 3)
        expect(
            window.carded(from: [brief], now: at(60).addingTimeInterval(179))?.id == "brief",
            "a three-minute meeting is carded until it ends")
        expect(
            window.carded(from: [brief], now: at(60).addingTimeInterval(180)) == nil,
            "the grace period never outlives the meeting")

        let linkless = event(id: "linkless", start: 60, link: nil)
        expect(
            window.carded(from: [linkless], now: start) == nil,
            "a meeting with no link is never carded")
        expect(
            UpcomingWindow.agenda(from: [linkless], now: start).map(\.id) == ["linkless"],
            "but it stays on the agenda, so it is still listed and searchable")
    }

    /// 快捷键（chord）的候选范围比卡片更宽：进行中的会议仍可加入，否则给出下一个。
    static func chordFallsBackWiderThanTheCard() {
        let window = UpcomingWindow(leadMinutes: 5)
        let running = event(id: "running", start: 0, minutes: 60)
        let next = event(id: "next", start: 120)
        let now = at(0).addingTimeInterval(1800)

        expect(window.carded(from: [running], now: now) == nil, "half an hour in, the card is gone")
        expect(
            window.joinable(from: [running], now: now)?.id == "running",
            "the chord still joins the call that is running")
        expect(
            window.joinable(from: [next], now: now)?.id == "next",
            "with nothing running it offers the next one")
        expect(
            window.joinable(from: [running, next], now: at(120).addingTimeInterval(-120))?.id
                == "next",
            "inside the card window the chord joins what is on screen")
        expect(
            window.joinable(from: [], now: now) == nil, "an empty day offers nothing to join")
        expect(
            window.joinable(from: [event(id: "past", start: -120)], now: now) == nil,
            "a meeting that is over is not offered")
    }

    /// 行内时间标签（pill）在临近、当天、隔日等情况下显示倒计时或日期。
    static func rowPills() {
        var calendar = Self.calendar
        calendar.locale = Locale(identifier: "en_US")
        let start = date(year: 2026, month: 9, day: 23, hour: 17)
        let meeting = event(id: "review", starting: start, minutes: 30)
        func pill(_ offset: TimeInterval) -> UpcomingWindow.RowPill? {
            UpcomingWindow.rowPill(
                for: meeting, now: start.addingTimeInterval(offset), calendar: calendar)
        }
        expect(
            pill(-60 * 60) == .init(text: "in 60 min", isImminent: true),
            "exactly an hour out is imminent")
        expect(
            pill(-3 * 60 * 60) == .init(text: "in 3 hr", isImminent: false),
            "later today counts down in hours")
        expect(
            pill(-18 * 60 * 60) == .init(text: "Wed, Sep 23", isImminent: false),
            "a meeting tomorrow names its date")
        expect(
            pill(-40 * 60)?.text == "in 40 min", "inside the hour a countdown beats the date")
        expect(pill(0)?.text == "Now", "the start reads as Now")
        expect(pill(29 * 60) == .init(text: "Now", isImminent: true), "a meeting under way stays Now")
        expect(pill(30 * 60) == nil, "a finished meeting earns no pill")

        let lateNight = date(year: 2026, month: 9, day: 23, hour: 23, minute: 30)
        let pastMidnight = event(id: "late", starting: lateNight.addingTimeInterval(40 * 60))
        expect(
            UpcomingWindow.rowPill(for: pastMidnight, now: lateNight, calendar: calendar)?.text
                == "in 40 min",
            "a meeting just past midnight still counts down")
    }

    /// 倒计时文案与菜单栏倒计时在不同时间点的措辞。
    static func countdownStrings() {
        let start = at(60)
        expect(
            UpcomingWindow.countdown(to: start, now: start.addingTimeInterval(-240)) == "in 4 min",
            "four minutes out reads as in 4 min")
        expect(
            UpcomingWindow.countdown(to: start, now: start.addingTimeInterval(-60)) == "in 1 min",
            "one minute out reads as in 1 min")
        expect(
            UpcomingWindow.countdown(to: start, now: start.addingTimeInterval(-1)) == "in 1 min",
            "a partial minute rounds up rather than reading as now")
        expect(UpcomingWindow.countdown(to: start, now: start) == "Now", "the start reads as Now")
        expect(
            UpcomingWindow.countdown(to: start, now: start.addingTimeInterval(299)) == "Now",
            "the first five minutes after the start still read as Now")
        expect(
            UpcomingWindow.countdown(to: start, now: start.addingTimeInterval(301)) == "Now",
            "a started event stays Now outside the menu-bar-specific timer")
        expect(
            UpcomingWindow.countdown(to: start, now: start.addingTimeInterval(-619 * 60)) == "in 10 hr",
            "a long wait rounds to hours")

        let meeting = event(id: "standup", start: 60, minutes: 30)
        expect(
            UpcomingWindow.menuBarCountdown(for: meeting, now: start.addingTimeInterval(299)) == "Now",
            "the menu bar says Now during the first five minutes")
        expect(
            UpcomingWindow.menuBarCountdown(for: meeting, now: start.addingTimeInterval(301))
                == "24 min left",
            "the menu bar switches to time left after five minutes")
    }

    // MARK: - 菜单栏

    static let automatic = MenuBarSummary(
        leadMinutes: 5, hideAfterMinutes: nil, linkedOnly: false, hideCurrentAtStart: true)

    /// 菜单栏在 lead 时间内拾取事件，并按「开始时隐藏/保留」配置决定何时清除。
    static func menuBarWindow() {
        let meeting = event(id: "standup", start: 60, minutes: 30)
        let start = at(60)
        expect(
            automatic.event(from: [meeting], now: start.addingTimeInterval(-300))?.id == "standup",
            "the menu bar picks the event up exactly at the lead time")
        expect(
            automatic.event(from: [meeting], now: start.addingTimeInterval(-301)) == nil,
            "one second earlier it is not there yet")
        expect(
            automatic.event(from: [meeting], now: start.addingTimeInterval(-1))?.id == "standup",
            "it is still there a second before the start")
        expect(
            automatic.event(from: [meeting], now: start) == nil,
            "Automatically clears it exactly at the start")

        let showTimeLeft = MenuBarSummary(leadMinutes: 5, linkedOnly: false)
        expect(
            showTimeLeft.event(from: [meeting], now: start)?.id == "standup",
            "Keep visible leaves the current event available for its time left")

        let lingering = MenuBarSummary(leadMinutes: 5, hideAfterMinutes: 5, linkedOnly: false)
        expect(
            lingering.event(from: [meeting], now: start.addingTimeInterval(299))?.id == "standup",
            "a five-minute grace keeps it up counting past the start")
        expect(
            lingering.event(from: [meeting], now: start.addingTimeInterval(300)) == nil,
            "and clears it when the grace runs out")

        let brief = event(id: "brief", start: 60, minutes: 3)
        expect(
            lingering.event(from: [brief], now: start.addingTimeInterval(180)) == nil,
            "the grace never outlives the meeting")

        let next = event(id: "next", start: 62)
        expect(
            automatic.event(from: [meeting, next], now: start)?.id == "next",
            "when the current one hides, the next inside its lead time takes the space")
    }

    /// 用户关闭菜单栏中展示的事件后，名额让给下一个进入 lead 的事件。
    static func menuBarDismissal() {
        let meeting = event(id: "standup", start: 60, minutes: 30)
        let next = event(id: "next", start: 62)
        let now = at(60).addingTimeInterval(-60)
        expect(
            automatic.event(from: [meeting, next], now: now, dismissed: [])?.id == "standup",
            "nothing dismissed leaves the earliest event in the menu bar")
        expect(
            automatic.event(from: [meeting, next], now: now, dismissed: ["standup"])?.id == "next",
            "dismissing the displayed event hands the space to the next one inside its lead")
        expect(
            automatic.event(from: [meeting], now: now, dismissed: ["standup"]) == nil,
            "with nothing behind it the menu bar clears instead")
        expect(
            automatic.event(from: [meeting, next], now: now, dismissed: ["next"])?.id == "standup",
            "dismissing an event that is not displayed leaves the displayed one alone")
        expect(
            automatic.event(from: [meeting, next], now: now, dismissed: ["standup", "next"]) == nil,
            "dismissing both clears the menu bar")

        let later = at(62).addingTimeInterval(-60)
        expect(
            automatic.event(from: [meeting, next], now: later, dismissed: ["standup"])?.id == "next",
            "a dismissal is per occurrence, so the next event still arrives on its own lead")
    }

    /// `linkedOnly` 过滤：只显示含会议链接的事件，全天事件一律排除。
    static func menuBarFiltering() {
        let linkless = event(id: "linkless", start: 60, link: nil)
        let linked = event(id: "linked", start: 61)
        let now = at(60).addingTimeInterval(-120)
        expect(
            automatic.event(from: [linkless, linked], now: now)?.id == "linkless",
            "with the filter off an appointment can hold the menu bar")
        let linkedOnly = MenuBarSummary(leadMinutes: 5, hideAfterMinutes: nil, linkedOnly: true)
        expect(
            linkedOnly.event(from: [linkless, linked], now: now)?.id == "linked",
            "Only show events with meetings skips the one there is nothing to join")
        expect(
            linkedOnly.event(from: [linkless], now: now) == nil,
            "and shows nothing when no event has a link")
        expect(
            automatic.event(from: [event(id: "allday", start: 60, isAllDay: true)], now: now) == nil,
            "the menu bar reads the same agenda as everything else, so all-day events are out")
    }

    /// 「今天」模式保留当天剩余事件，并容忍跨过午夜的临近会议。
    static func menuBarToday() {
        let summary = MenuBarSummary(
            leadMinutes: nil, hideAfterMinutes: nil, linkedOnly: false, calendar: calendar)
        let morning = date(year: 2026, month: 8, day: 23, hour: 10)
        let laterToday = event(id: "later", starting: date(year: 2026, month: 8, day: 23, hour: 15))
        expect(
            summary.event(from: [laterToday], now: morning)?.id == "later",
            "Today carries an event later on the same day")

        let justBeforeMidnight = date(year: 2026, month: 8, day: 23, hour: 23, minute: 30)
        let midnight = event(id: "midnight", starting: date(year: 2026, month: 8, day: 24, hour: 0))
        expect(
            summary.event(from: [midnight], now: justBeforeMidnight)?.id == "midnight",
            "Today keeps a meeting that starts exactly thirty minutes after midnight")
        expect(
            MenuBarSummary.hasUpcomingEvent(from: [midnight], now: justBeforeMidnight, calendar: calendar),
            "the empty label agrees with the midnight grace")

        let thirtyOneMinutesOut = date(year: 2026, month: 8, day: 23, hour: 23, minute: 29)
        expect(
            summary.event(from: [midnight], now: thirtyOneMinutesOut) == nil,
            "Today does not keep tomorrow's event more than thirty minutes away")
        expect(
            !MenuBarSummary.hasUpcomingEvent(
                from: [midnight], now: thirtyOneMinutesOut, calendar: calendar),
            "the empty label appears once today is over and tomorrow is not imminent")
    }

    /// 菜单栏标题超过上限时截断并补省略号。
    static func menuBarTitles() {
        expect(MenuBarSummary.title("Standup") == "Standup", "a short title is untouched")
        let long = String(repeating: "a", count: MenuBarSummary.titleCap + 5)
        let capped = MenuBarSummary.title(long)
        expect(capped.count == MenuBarSummary.titleCap, "a long title is capped")
        expect(capped.hasSuffix("…"), "and says it was cut")
        expect(
            MenuBarSummary.title(String(repeating: "b", count: MenuBarSummary.titleCap))
                == String(repeating: "b", count: MenuBarSummary.titleCap),
            "a title exactly at the cap keeps every character")
    }

    // MARK: - 自动加入

    /// 自动加入只在会议开始时触发一次，宽限期内唤醒的 Mac 仍会加入。
    static func autoJoinFiresOnce() {
        let window = UpcomingWindow(leadMinutes: 5)
        let policy = AutoJoinPolicy(armedAt: at(0), namedProvidersOnly: false)
        let meeting = event(id: "standup", start: 60, minutes: 30)
        let start = at(60)

        expect(
            policy.meeting(
                from: [meeting], now: start.addingTimeInterval(-60), window: window,
                joined: []) == nil,
            "auto join never fires early, however close the card is")
        expect(
            policy.meeting(from: [meeting], now: start, window: window, joined: [])?.id == "standup",
            "it fires at the start")
        expect(
            policy.meeting(from: [meeting], now: start, window: window, joined: ["standup"]) == nil,
            "and never twice for the same meeting")
        expect(
            policy.meeting(
                from: [meeting], now: start.addingTimeInterval(299), window: window,
                joined: [])?.id == "standup",
            "a Mac waking inside the window still joins")
        expect(
            policy.meeting(
                from: [meeting], now: start.addingTimeInterval(300), window: window,
                joined: []) == nil,
            "past the window it stays out of the way")
        expect(
            policy.meeting(
                from: [event(id: "linkless", start: 60, link: nil)], now: start,
                window: window, joined: []) == nil,
            "a meeting with no link is never auto joined")
    }

    /// 自动加入只对「开启开关之后」开始的会议生效，不会把用户拽进进行中的通话。
    static func autoJoinRespectsArming() {
        let window = UpcomingWindow(leadMinutes: 5)
        let running = event(id: "running", start: 60, minutes: 60)
        // 在会议已开始一分钟后才开启开关。
        let policy = AutoJoinPolicy(armedAt: at(61), namedProvidersOnly: false)
        expect(
            policy.meeting(from: [running], now: at(61), window: window, joined: []) == nil,
            "arming the switch mid-call does not yank you into the call")
        let later = event(id: "later", start: 90)
        expect(
            policy.meeting(from: [running, later], now: at(90), window: window, joined: [])?.id
                == "later",
            "but the next meeting after arming is fair game")
    }

    /// `namedProvidersOnly` 拒绝无明确服务商的裸链接，但不会遮蔽旁边的真实通话链接。
    static func autoJoinSkipsBareLinks() {
        let window = UpcomingWindow(leadMinutes: 5)
        let placeholder = event(id: "placeholder", start: 60)
        let call = event(id: "call", start: 60, link: link("https://zoom.us/j/8901234567"))
        let start = at(60)

        expect(
            AutoJoinPolicy(armedAt: at(0), namedProvidersOnly: false)
                .meeting(from: [placeholder], now: start, window: window, joined: [])?.id
                == "placeholder",
            "a bare link still auto joins by default")
        let namedOnly = AutoJoinPolicy(armedAt: at(0), namedProvidersOnly: true)
        expect(
            namedOnly.meeting(from: [placeholder], now: start, window: window, joined: []) == nil,
            "named providers only leaves a bare link to the card")
        let earlier = event(id: "earlier", start: 58)
        expect(
            namedOnly.meeting(from: [earlier, call], now: start, window: window, joined: [])?.id
                == "call",
            "and a bare link the card would pick first does not shadow a call beside it")
    }

    // MARK: - 事件草稿

    /// 事件草稿的有效性、标题裁剪、起止时间与展示文案。
    static func eventDrafts() {
        var draft = EventDraft()
        expect(!draft.isValid, "a blank draft cannot be written")
        draft.title = "   "
        expect(!draft.isValid, "nor one that is only whitespace")
        draft.title = "  Standup  "
        expect(draft.isValid, "a real title is enough")
        expect(draft.trimmedTitle == "Standup", "the title is trimmed on the way out")

        let now = at(0)
        expect(draft.start(from: now) == now, "an offset of zero starts now")
        expect(
            draft.end(from: now) == now.addingTimeInterval(1800), "the default runs thirty minutes")
        draft.startOffsetMinutes = 30
        draft.durationMinutes = 60
        expect(draft.start(from: now) == at(30), "an offset pushes the start out")
        expect(draft.end(from: now) == at(90), "and the duration runs from there")

        expect(EventDraft.label(startOffset: 0) == "Now", "a zero offset reads as Now")
        expect(EventDraft.label(startOffset: 15) == "15 min", "a smaller offset reads in minutes")
        expect(EventDraft.label(duration: 45) == "45 min", "so does a sub-hour duration")
        expect(EventDraft.label(duration: 60) == "1 hr", "an hour reads as an hour")
    }

    // MARK: - 会议详情

    /// 会议详情的备注纯文本化与参与者排序（组织者在前）。
    static func meetingDetails() {
        let notes = MeetingDetails.plainText(fromNotes:)
        expect(notes("  Agenda\n\nBring numbers  ") == "Agenda\n\nBring numbers", "plain text is trimmed")
        expect(notes(" \n ") == nil, "blank notes are none at all")
        expect(
            notes("Join <https://teams.microsoft.com/l/meetup-join/1> now")
                == "Join <https://teams.microsoft.com/l/meetup-join/1> now",
            "an angle-bracketed link in plain text survives")
        expect(notes("a < b and c > d") == "a < b and c > d", "bare angle brackets are not markup")
        expect(
            notes("<b>Agenda</b><br>Q&amp;A<br/><br><br>Wrap&nbsp;up") == "Agenda\nQ&A\n\nWrap up",
            "HTML notes lose their tags, keep their breaks and decode entities")
        expect(
            notes("<ul><li>One</li><li>Two</li></ul>") == "• One\n• Two", "list items become bullets")
        expect(
            notes("<p>See <a href=\"https://example.com\">https://example.com</a></p>")
                == "See https://example.com",
            "a link keeps its text")
        expect(notes("&amp;lt;b&amp;gt; <br>") == "&lt;b&gt;", "entities decode exactly once")

        let organizer = MeetingDetails.Attendee(name: "Ana", response: .accepted, isOrganizer: true)
        let guest = MeetingDetails.Attendee(name: "Ben", response: .pending, isOrganizer: false)
        let other = MeetingDetails.Attendee(name: "Cy", response: .declined, isOrganizer: false)
        let details = MeetingDetails(
            meetingID: "m", location: "  \n", notes: nil, attendees: [guest, organizer, other])
        expect(details.attendees == [organizer, guest, other], "the organizer leads, the rest keep order")
        expect(details.location == nil, "a blank location is none at all")
    }

    // MARK: - 按天处理

    /// 会议按天归类：今天 / 明天 / 后天，以及跨夜仍在进行的会议。
    static func dayBuckets() {
        var calendar = Self.calendar
        calendar.locale = Locale(identifier: "en_US")
        let now = date(year: 2026, month: 8, day: 23, hour: 22)
        func day(_ hours: Double) -> MeetingDay {
            MeetingDay(for: now.addingTimeInterval(hours * 3600), now: now, calendar: calendar)
        }
        expect(day(1).offset == 0, "an hour before midnight is still today")
        expect(day(2).offset == 1, "an hour past midnight is tomorrow")
        expect(
            day(48).offset == 2 && day(48).start == date(year: 2026, month: 8, day: 25, hour: 0),
            "the day after tomorrow is its own day, keyed by its midnight")
        expect(day(-24) == day(1), "a meeting still running from yesterday is happening today")
        expect(
            day(1).title(calendar: calendar) == "Today, Aug 23"
                && day(2).title(calendar: calendar) == "Tomorrow, Aug 24"
                && day(48).title(calendar: calendar) == "Tuesday, Aug 25",
            "a day is named relative to today while it can be, then by weekday, always dated")
    }

    /// 按天分组：每天一组、按开始时间排序。
    static func dayGroups() {
        let now = at(9 * 60)
        let agenda = [
            event(id: "standup", start: 10 * 60), event(id: "review", start: 14 * 60),
            event(id: "kickoff", start: 33 * 60), event(id: "offsite", start: 81 * 60)
        ]
        let groups = MeetingDayGroup.grouping(agenda, now: now, calendar: calendar)
        expect(
            groups.map(\.day.offset) == [0, 1, 3],
            "one group per day, in start order")
        expect(
            groups.map { $0.meetings.map(\.id) } == [["standup", "review"], ["kickoff"], ["offsite"]],
            "a day's meetings stay together and in order")
        expect(
            MeetingDayGroup.grouping([], now: now, calendar: calendar).isEmpty,
            "an empty agenda has no days")
    }

    // MARK: - 读取跨度

    /// 读取跨度（今天 / 今明 / 未来七天）的时间区间与措辞。
    static func readSpan() {
        let now = date(year: 2026, month: 8, day: 23, hour: 22)
        let midnight = date(year: 2026, month: 8, day: 23, hour: 0)
        expect(
            MeetingSpan.today.interval(from: now, calendar: calendar)
                == DateInterval(start: midnight, end: date(year: 2026, month: 8, day: 24, hour: 0)),
            "today alone runs midnight to midnight, from an evening `now`")
        expect(
            MeetingSpan.todayAndTomorrow.interval(from: now, calendar: calendar)
                == DateInterval(start: midnight, end: date(year: 2026, month: 8, day: 25, hour: 0)),
            "tomorrow adds a second day to the same start")
        expect(
            MeetingSpan.nextSevenDays.interval(from: now, calendar: calendar)
                == DateInterval(start: midnight, end: date(year: 2026, month: 8, day: 30, hour: 0)),
            "the week runs seven days from the same start, today included")
        expect(
            MeetingSpan.today.possessivePhrase == "today's"
                && MeetingSpan.todayAndTomorrow.orPhrase == "today or tomorrow"
                && MeetingSpan.nextSevenDays.possessivePhrase == "the next 7 days'"
                && MeetingSpan.nextSevenDays.orPhrase == "in the next 7 days",
            "the wording follows the span")
    }

    // MARK: - 辅助方法

    /// 测试用的时间基准（参考日期 0），配合 `at(_:)` 构造相对时间。
    static let epoch = Date(timeIntervalSinceReferenceDate: 0)

    /// 由时间基准偏移若干分钟得到时间点。
    static func at(_ minutes: Int) -> Date {
        epoch.addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// 用固定日历构造指定年月日时分的时间点。
    static func date(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static func link(_ text: String) -> MeetingLink? { MeetingLink.detect(in: text) }

    /// 以指定账户语义解析单个字段中的会议链接。
    static func hosted(_ text: String, _ account: String?) -> MeetingLink? {
        MeetingLink.detect(fields: [text], account: account)
    }

    /// 从参与者 URL（mailto）中解析账户地址。
    static func participant(_ url: String, isCurrentUser: Bool = true) -> String? {
        MeetingLink.accountAddress(of: URL(string: url)!, isCurrentUser: isCurrentUser)
    }

    static func provider(_ text: String) -> MeetingLink.Provider? { link(text)?.provider }

    /// 以自时间基准的分钟偏移构造测试用会议事件。
    static func event(
        id: String, start minutes: Int, minutes duration: Int = 30, isAllDay: Bool = false,
        isDeclined: Bool = false, link: MeetingLink? = MeetingLink.detect(in: "https://example.com/x")
    ) -> MeetingEvent {
        MeetingEvent(
            id: id, title: id, start: at(minutes),
            end: at(minutes).addingTimeInterval(TimeInterval(duration * 60)),
            isAllDay: isAllDay, isDeclined: isDeclined, calendarID: "cal", calendarName: "Work",
            calendarColor: nil, calendarItemID: id, link: link)
    }

    /// 以绝对开始时间构造测试用会议事件。
    static func event(
        id: String, starting start: Date, minutes duration: Int = 30,
        link: MeetingLink? = MeetingLink.detect(in: "https://example.com/x")
    ) -> MeetingEvent {
        MeetingEvent(
            id: id, title: id, start: start,
            end: start.addingTimeInterval(TimeInterval(duration * 60)),
            isAllDay: false, isDeclined: false, calendarID: "cal", calendarName: "Work",
            calendarColor: nil, calendarItemID: id, link: link)
    }

    /// 断言辅助：条件成立则通过数加一。
    static func expect(_ condition: Bool, _ label: String) {
        if condition {
            passes += 1
        } else {
            fail(label)
        }
    }

    /// 记录一次失败并打印其标签。
    static func fail(_ label: String) {
        print("FAIL: \(label)")
        failures += 1
    }
}
