// 文件职责：日历功能的协调器，负责会议加入（授权同意门禁、卡片与快捷键动作）、功能开关、菜单栏事件以及启动器条目的发布。
// 分层：Coordinator（@MainActor）；对话框与 HUD 等均由 AppCore 持有，所有界面共用同一个 UpcomingWindow，避免口径不一致。
import AppKit

/// 负责会议加入：授权同意门禁、卡片与快捷键的动作，以及功能是否存在。
@MainActor
@Observable
final class CalendarCoordinator {
    private let store: CalendarStore
    private let clock: MeetingClock
    private let appIndex: AppIndex
    private let settings: AppSettings
    private let paletteCoordinator: PaletteCoordinator
    /// 对话框与 HUD，二者都保持由 `AppCore` 持有。
    private unowned let core: AppCore

    /// 拥有自己独立的界面，如同 `NotesCoordinator` 拥有笔记窗口。
    @ObservationIgnored private lazy var cameraPreview = CameraPreviewController(settings: settings)

    @ObservationIgnored private var paletteVisible = false
    /// 上次启用自动加入的时间；在该时刻已进行中的会议绝不会被自动加入。
    @ObservationIgnored private var armedAt = Date.distantFuture
    /// 本次启动中已自动加入的会议，使每个会议最多自动打开一次。
    @ObservationIgnored private var autoJoined: Set<MeetingEvent.ID> = []

    /// 仅在状态翻转时写入：菜单栏场景会读取它，不能每个时钟 tick 都重算。
    private(set) var hasMenuBarEvent = false
    /// 本次启动中从菜单栏关闭过的会议，作用类似 `autoJoined` 记录已打开过的会议。
    private var dismissedFromMenuBar: Set<MeetingEvent.ID> = []

    /// 注入依赖；`core` 以 unowned 方式持有，避免与其形成循环引用。
    init(
        store: CalendarStore,
        clock: MeetingClock,
        appIndex: AppIndex,
        settings: AppSettings,
        paletteCoordinator: PaletteCoordinator,
        core: AppCore
    ) {
        self.store = store
        self.clock = clock
        self.appIndex = appIndex
        self.settings = settings
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    /// 所有界面共用的时间窗口，使卡片、快捷键与日程视图不会出现口径不一致。
    var window: UpcomingWindow { UpcomingWindow(leadMinutes: settings.joinWindowMinutes.rawValue) }

    /// 加入卡片当前展示的会议；`now` 来自持续计时的时钟。
    var cardedMeeting: MeetingEvent? {
        guard settings.calendarEnabled else { return nil }
        return window.carded(from: store.events, now: clock.now)
    }

    /// 实时计算而非依赖时钟：快捷键在没有计时器运行时读取它。
    var agenda: [MeetingEvent] { UpcomingWindow.agenda(from: store.events, now: Date()) }

    /// 日历标签在今日事件用尽前保持普通图标，并为即将开始的会议保留一小段跨午夜的宽限。
    var hasUpcomingMenuBarEvent: Bool {
        MenuBarSummary.hasUpcomingEvent(from: store.events, now: clock.now)
    }

    /// 菜单栏承载的事件；为 nil 时显示普通图标。
    var menuBarEvent: MeetingEvent? {
        guard settings.calendarEnabled, settings.calendarMenuBarDisplay != .disabled else {
            return nil
        }
        let summary = MenuBarSummary(
            leadMinutes: settings.menuBarEvents == .today ? nil : settings.menuBarEvents.rawValue,
            hideAfterMinutes: settings.hideCurrentEvent.minutes,
            linkedOnly: settings.menuBarLinkedEventsOnly,
            hideCurrentAtStart: settings.hideCurrentEvent.hidesAtStart)
        return summary.event(
            from: store.events, now: clock.now, dismissed: dismissedFromMenuBar)
    }

    /// 菜单栏的逐日列表；由时钟驱动，会议结束后会在整分钟被移除。
    var menuBarAgenda: [MeetingDayGroup] {
        let now = clock.now
        return MeetingDayGroup.grouping(
            UpcomingWindow.agenda(from: store.events, now: now), now: now, calendar: .current)
    }

    /// 关闭菜单栏当前展示的事件：交接过程中发生的点击不能吞掉新到来的事件。
    func dismissMenuBarEvent(_ meeting: MeetingEvent) {
        dismissedFromMenuBar.insert(meeting.id)
        refreshMenuBarEvent()
    }

    // MARK: - Feature switch

    /// 开关统一走这里，因此「启用」（同时也是授权同意）会先弹出确认。
    func setCalendarEnabled(_ enabled: Bool) {
        if !enabled {
            guard settings.calendarEnabled else { return }
            settings.calendarEnabled = false
            return
        }

        // 唯一恢复途径是重新发起请求：设置面板无法添加 TCC 没有记录的应用。
        store.refreshAccess()
        guard !settings.calendarEnabled || store.access != .granted else { return }
        NSApp.activate(ignoringOtherApps: true)
        Task {
            guard
                await core.confirm(
                    title: settings.text(CalendarKey.errorEnableTitle),
                    message: String(
                        format: settings.text(CalendarKey.errorEnableMessage),
                        settings.calendarSpan.localizedPossessivePhrase(settings.language)),
                    symbol: "calendar", confirmTitle: settings.text(CalendarKey.errorEnableAction),
                    tone: .neutral, confirmRole: .standard)
            else { return }

            guard await store.requestAccess() else { return }
            // 该标志代表授权同意，因此只在 macOS 实际授权后才写入。
            settings.calendarEnabled = true
            applyEnabled()
        }
    }

    /// 发布或撤回该功能向启动器贡献的全部内容。
    func applyEnabled() {
        let enabled = settings.calendarEnabled
        appIndex.setCommandsVisible(
            [.joinNextMeeting, .copyMeetingLink, .mySchedule, .openInCalendar, .createEvent], enabled)
        guard enabled else {
            store.stop()
            clock.stop()
            publishEntries()
            refreshMenuBarEvent()
            return
        }
        store.onChange = { [weak self] in
            self?.publishEntries()
            self?.refreshMenuBarEvent()
        }
        clock.onTick = { [weak self] in self?.minuteDidPass() }
        applySpan()
        store.start()
        publishEntries()
        applyClock()
    }

    /// 改动读取的天数范围会重新查询 EventKit，因此统一经由 store 处理。
    func applySpan() {
        store.span = settings.calendarSpan
    }

    /// 只有在有人观察时时钟才运行；三者都关闭时，空闲的 Mac 不会持有计时器。
    func applyClock() {
        armAutoJoin()
        let watched =
            paletteVisible || settings.calendarMenuBarDisplay != .disabled
            || settings.autoJoinMeetings
        guard settings.calendarEnabled, watched else {
            clock.stop()
            return
        }
        clock.start()
        refreshMenuBarEvent()
    }

    /// 在开启自动加入时打上时间戳，因此通话中途打开该功能不会把你拽进当前通话。
    private func armAutoJoin() {
        guard settings.calendarEnabled, settings.autoJoinMeetings else {
            armedAt = .distantFuture
            return
        }
        if armedAt == .distantFuture { armedAt = Date() }
    }

    /// 事件结束不会在 EventKit 中产生任何变化，因此靠重新发布来移除它。
    private func minuteDidPass() {
        store.reloadIfStale(now: clock.now)
        publishEntries()
        refreshMenuBarEvent()
        autoJoinIfDue()
    }

    /// 重新判断菜单栏是否有事件，仅在结果变化时写入 `hasMenuBarEvent`。
    private func refreshMenuBarEvent() {
        forgetStaleDismissals()
        let hasEvent = menuBarEvent != nil
        guard hasEvent != hasMenuBarEvent else { return }
        hasMenuBarEvent = hasEvent
    }

    /// 仅在变化时赋值：每个 tick 都写入会让标签做无谓的重算。
    private func forgetStaleDismissals() {
        guard !dismissedFromMenuBar.isEmpty else { return }
        let live = dismissedFromMenuBar.intersection(store.events.map(\.id))
        guard live != dismissedFromMenuBar else { return }
        dismissedFromMenuBar = live
    }

    /// 到点则自动加入符合策略的会议；询问前先标记为已加入，避免重复询问。
    private func autoJoinIfDue() {
        guard settings.calendarEnabled, settings.autoJoinMeetings, !core.isShowingDialog else {
            return
        }
        let policy = AutoJoinPolicy(
            armedAt: armedAt, namedProvidersOnly: settings.autoJoinNamedProvidersOnly)
        guard
            let meeting = policy.meeting(
                from: store.events, now: clock.now, window: window, joined: autoJoined)
        else { return }
        // 在询问前先标记，避免拒绝确认后过一分钟又被询问。
        autoJoined.insert(meeting.id)
        join(meeting, uninvited: true)
    }

    /// 「在启动器中显示」只约束这些行，因此关闭会议展示时 My Schedule 仍可被检索到。
    func publishEntries() {
        guard settings.calendarEnabled, settings.calendarShowInLauncher else {
            appIndex.setMeetings([])
            return
        }
        let meetings =
            settings.calendarLauncherLimit.maximum.map { Array(agenda.prefix($0)) } ?? agenda
        appIndex.setMeetings(meetings.map { Self.entry(for: $0, language: settings.language) })
    }

    /// 把会议转换为启动器条目；URL 中的会议 ID 做百分号编码。
    private static func entry(for meeting: MeetingEvent, language: AppLanguage) -> AppEntry {
        AppEntry(
            id: meeting.entryID, name: meeting.localizedTitle(language),
            url: URL(
                string: "gearmac://meeting/"
                    + (meeting.id.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
                        ?? ""))!,
            bundleID: nil, kind: .meeting,
            symbolName: meeting.link?.provider.sfSymbol ?? "calendar",
            keywords: [meeting.calendarName])
    }

    // MARK: - Palette lifecycle

    /// 面板关闭期间事件会过期，倒计时也只在实际可见时才走动。
    func paletteDidShow() {
        paletteVisible = true
        applyClock()
        guard settings.calendarEnabled else { return }
        // 面板关闭期间会议可能已经结束，而没有时钟就没有任何东西重新发布它们。
        publishEntries()
        // 脱离召唤路径：卡片由观察驱动，晚一帧到达也可以。
        Task { store.reload() }
    }

    /// 面板关闭：清除可见标记并重算时钟的启停。
    func paletteDidHide() {
        paletteVisible = false
        applyClock()
    }

    // MARK: - Commands

    /// 快捷键动作：加入下一个可加入的会议。
    func joinNextMeeting() {
        guard let meeting = nextJoinable() else {
            report(settings.text(CalendarKey.hudNothingToJoin))
            return
        }
        join(meeting)
    }

    /// 快捷键动作：复制下一个可加入会议的链接。
    func copyNextMeetingLink() {
        guard let meeting = nextJoinable() else {
            report(settings.text(CalendarKey.hudNothingToJoin))
            return
        }
        copyLink(meeting)
    }

    /// 打开创建事件草稿对话框，成功写入后通过 HUD 提示。
    func createEvent() {
        paletteCoordinator.hidePalette(restoreFocus: false)
        guard settings.calendarEnabled, store.access == .granted else {
            report(settings.text(CalendarKey.hudCalendarOff))
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        Task {
            guard let draft = await core.createEvent() else { return }
            guard store.createEvent(draft, now: Date()) else {
                _ = await core.reportFailure(
                    title: settings.text(CalendarKey.errorCreateEventTitle),
                    message: settings.text(CalendarKey.errorCreateEventMessage),
                    symbol: "calendar.badge.exclamationmark", recovery: nil)
                return
            }
            core.showMessage(settings.text(CalendarKey.hudEventCreated))
        }
    }

    /// 快捷键动作：在系统日历中打开下一个会议，没有即将到来的会议时退回到议程首项。
    func openNextMeetingInCalendar() {
        guard let meeting = window.joinable(from: store.events, now: Date()) ?? agenda.first else {
            report(
                String(
                    format: settings.text(CalendarKey.emptyNothingScheduledFormat),
                    settings.calendarSpan.localizedOrPhrase(settings.language)))
            return
        }
        openInCalendar(meeting)
    }

    /// 实时计算而非依赖时钟：快捷键触发时面板未打开，没有计时器在运行。
    private func nextJoinable() -> MeetingEvent? {
        guard settings.calendarEnabled else { return nil }
        return window.joinable(from: store.events, now: Date())
    }

    // MARK: - Row actions

    /// 会议行的 ↵ 动作：加入会议；无链接的会议则交给系统日历处理。
    func activateMeeting(id: String) {
        guard let meeting = store.event(id: id) else { return }
        join(meeting)
    }

    /// 由启动器条目 ID 反查会议；ID 无法解码时返回 nil。
    func meeting(entryID: String) -> MeetingEvent? {
        MeetingEvent.id(fromEntryID: entryID).flatMap(store.event(id:))
    }

    /// `uninvited` 标记自动加入，这是唯一可能需要在动作前先询问的场景。
    func join(_ meeting: MeetingEvent, uninvited: Bool = false) {
        guard let link = meeting.link else {
            openInCalendar(meeting)
            return
        }
        paletteCoordinator.hidePalette(restoreFocus: false)
        Task { await joinAfterGate(meeting, link: link, uninvited: uninvited) }
    }

    /// 摄像头预览同时充当自动加入的确认，因此只有一个界面而不是两个。
    private func joinAfterGate(
        _ meeting: MeetingEvent, link: MeetingLink, uninvited: Bool
    ) async {
        // 预览本身就是一种确认，因此两者都开启时由它代替确认框。
        if settings.cameraPreview {
            guard await cameraPreview.present(meeting: meeting, now: Date()) else { return }
        } else if uninvited, settings.autoJoinConfirms {
            NSApp.activate(ignoringOtherApps: true)
            guard
                await core.confirm(
                    title: String(
                        format: settings.text(CalendarKey.actionJoinConfirmFormat),
                        meeting.localizedTitle(settings.language)),
                    message: UpcomingWindow.countdown(
                        to: meeting.start, now: Date(), language: settings.language),
                    symbol: link.provider.sfSymbol,
                    confirmTitle: settings.text(CalendarKey.actionJoin), tone: .neutral,
                    confirmRole: .standard,
                    dismissTitle: settings.text(CalendarKey.actionNotNow))
            else { return }
        }
        if await MeetingLauncher.join(link, browserBundleID: settings.meetingBrowserBundleID) {
            return
        }
        _ = await core.reportFailure(
            title: settings.text(CalendarKey.errorOpenLinkTitle),
            message: String(
                format: settings.text(CalendarKey.errorOpenLinkMessageFormat),
                link.url.absoluteString),
            symbol: "video.slash", recovery: nil)
    }

    /// 复制会议链接到剪贴板；会议没有链接时通过 HUD 提示。
    func copyLink(_ meeting: MeetingEvent) {
        guard let link = meeting.link else {
            report(settings.text(CalendarKey.hudNoLink))
            return
        }
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(link.url.absoluteString)
        core.showMessage(settings.text(CalendarKey.hudLinkCopied))
    }

    /// 在系统日历中显示该会议。
    func openInCalendar(_ meeting: MeetingEvent) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        MeetingLauncher.showInCalendar(meeting)
    }

    /// 把启动器切换到日程页面。
    func showSchedule() {
        paletteCoordinator.togglePalette(mode: .schedule)
    }

    /// 在页面跳转前先加载详情，使页面首帧就已有内容。
    func showDetails(of meeting: MeetingEvent) {
        store.loadDetails(of: meeting)
        paletteCoordinator.navigate(to: .meetingDetails)
    }

    /// 未命中属于瞬时情况，因此通过 HUD 提示，而不弹需要手动关闭的对话框。
    private func report(_ message: String) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        core.showMessage(message, tone: .neutral)
    }
}
