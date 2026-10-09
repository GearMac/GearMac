// 文件职责：从 EventKit 读取指定时间跨度内的会议事件与日历列表，管理授权、缓存重载、详情按需读取与逐日历开关。
// 分层：Service；@MainActor 隔离，`EKEventStore` 不跨界（非 Sendable），仅纯值类型对外发布。
import AppKit
import EventKit

/// 某一时间跨度内的会议，从 EventKit 读取。详见 docs/features/calendar.md。
@MainActor
@Observable
final class CalendarStore {
    /// 在 `span` 内拍平的事件实例，后发起的查询覆盖先前的。
    private(set) var events: [MeetingEvent] = []
    private(set) var calendars: [MeetingCalendar] = []
    private(set) var access: CalendarAccess = Permissions.calendarAccess()
    /// 详情页的会议，每次重载都会重新读取，使编辑不会展示陈数据。
    private(set) var details: MeetingDetails?

    /// 改变它会触发重读：不得把一个快照过滤到它从未获取过的跨度。
    var span: MeetingSpan = .todayAndTomorrow {
        didSet {
            guard span != oldValue, lastReloadAt != nil else { return }
            reload()
        }
    }

    /// `events` 变化时触发，使启动器的会议切片重新发布。
    @ObservationIgnored var onChange: (() -> Void)?

    private let defaults = UserDefaults.standard
    private let hiddenKey = "hiddenMeetingCalendars"
    /// 存排除项而非包含项，使在写入之后新增的日历默认处于开启状态。
    private var hiddenCalendarIDs: Set<String>

    /// 首次使用时才创建，使未开启该功能的 Mac 启动时从不加载 EventKit。
    @ObservationIgnored private var eventStore: EKEventStore?
    @ObservationIgnored private var changeObserver: NotificationToken?
    @ObservationIgnored private var wakeObserver: NotificationToken?
    @ObservationIgnored private var lastReloadAt: Date?

    /// 覆盖跨日和休眠的 Mac；编辑由 EventKit 通知驱动。
    private static let staleAfter: TimeInterval = 10 * 60

    /// 从 UserDefaults 恢复被隐藏的日历 id 集合。
    init() {
        hiddenCalendarIDs = Set(defaults.stringArray(forKey: hiddenKey) ?? [])
    }

    /// 在设置中改变授权时 TCC 不会发出任何通知，因此任何依赖 `access` 的地方都需重新读取。
    func refreshAccess() {
        access = Permissions.calendarAccess()
    }

    // MARK: - Lifecycle

    /// 启动：刷新授权、开始监听唤醒并异步进行首次重载。
    func start() {
        refreshAccess()
        guard access == .granted else { return }
        observeWake()
        // 延后执行：首次 EventKit 查询需要为它的 XPC 预热付出代价，而启动过程需要自我保护。
        Task { reload() }
    }

    /// 停止：移除监听、释放 EventStore 并清空已发布状态。
    func stop() {
        changeObserver = nil
        wakeObserver = nil
        eventStore = nil
        lastReloadAt = nil
        publish([])
        calendars = []
        details = nil
    }

    /// 运行到此处时 GearMac 自身的同意弹窗已被接受。
    func requestAccess() async -> Bool {
        let granted = await Permissions.requestCalendarAccess()
        refreshAccess()
        guard granted else { return false }
        // 授权前创建的 store 看不到新出现的日历；丢弃重建。
        changeObserver = nil
        eventStore = nil
        reload()
        return true
    }

    /// EventKit 会告知何时应重载；面板每次召唤再额外刷新一次。
    private func observeStoreChanges() {
        guard changeObserver == nil, let eventStore else { return }
        let center = NotificationCenter.default
        let token = center.addObserver(
            forName: .EKEventStoreChanged, object: eventStore, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        changeObserver = NotificationToken(token, center: center)
    }

    /// 在会议期间休眠的 Mac 唤醒后快照已过时，且没有编辑事件触发重载。
    private func observeWake() {
        guard wakeObserver == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        let token = center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        wakeObserver = NotificationToken(token, center: center)
    }

    // MARK: - Reading

    /// 每分钟的刷新：快照仍有效时几乎没有开销，而绝大多数情况都是如此。
    func reloadIfStale(now: Date) {
        guard let lastReloadAt else {
            reload()
            return
        }
        let aged = now.timeIntervalSince(lastReloadAt) >= Self.staleAfter
        // 跨日会使跨度本身失效，无论快照有多新鲜。
        let rolled = !Calendar.current.isDate(lastReloadAt, inSameDayAs: now)
        guard aged || rolled else { return }
        reload()
    }

    /// 重读日历列表与事件；`EKEventStore` 不是 `Sendable`，所以全程在主线程，只有纯值离开。
    func reload() {
        defer { refreshDetails() }
        refreshAccess()
        guard access == .granted else {
            publish([])
            return
        }
        let store = eventStore ?? EKEventStore()
        eventStore = store
        observeStoreChanges()
        lastReloadAt = Date()

        let sources = store.calendars(for: .event)
        calendars =
            sources
            .map {
                MeetingCalendar(
                    id: $0.calendarIdentifier, title: $0.title, accountName: $0.source.title)
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        let selected = sources.filter { !hiddenCalendarIDs.contains($0.calendarIdentifier) }
        guard !selected.isEmpty,
            let interval = span.interval(from: Date(), calendar: .current)
        else {
            publish([])
            return
        }
        // 谓词自身会展开重复事件；自己实现从来没有可行过。
        let predicate = store.predicateForEvents(
            withStart: interval.start, end: interval.end, calendars: selected)
        publish(store.events(matching: predicate).compactMap(Self.meeting(from:)))
    }

    /// 发布新的事件列表，仅在内容变化时通知。
    private func publish(_ next: [MeetingEvent]) {
        guard next != events else { return }
        events = next
        onChange?()
    }

    /// 把 `EKEvent` 转换为 `MeetingEvent`，取消或缺少必要字段的事件返回 nil。
    private static func meeting(from event: EKEvent) -> MeetingEvent? {
        // 已取消的事件不算发生，因此绝不会抵达任何界面。
        guard event.status != .canceled, let start = event.startDate, let end = event.endDate,
            let calendar = event.calendar
        else { return nil }
        let me = event.attendees?.first { $0.isCurrentUser }
        return MeetingEvent(
            id: occurrenceID(of: event, start: start),
            title: event.title ?? MeetingEvent.missingTitlePlaceholder,
            start: start,
            end: end,
            isAllDay: event.isAllDay,
            isDeclined: me?.participantStatus == .declined,
            calendarID: calendar.calendarIdentifier,
            calendarName: calendar.title,
            calendarColor: color(of: calendar),
            calendarItemID: event.calendarItemIdentifier,
            link: MeetingLink.detect(
                fields: [event.url?.absoluteString, event.location, event.notes],
                account: accountEmail(of: me ?? event.organizer)))
    }

    /// 生成每次实例唯一的 id（事件标识 + 开始时间）。
    private static func occurrenceID(of event: EKEvent, start: Date) -> MeetingEvent.ID {
        (event.eventIdentifier ?? event.calendarItemIdentifier)
            + "|\(start.timeIntervalSinceReferenceDate)"
    }

    /// 把日历的 CGColor 转成 sRGB 分量，失败时返回 nil。
    private static func color(of calendar: EKCalendar) -> MeetingEvent.CalendarColor? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let components = calendar.cgColor?.converted(
                to: space, intent: .defaultIntent, options: nil)?.components,
            components.count >= 3
        else { return nil }
        return MeetingEvent.CalendarColor(
            red: components[0], green: components[1], blue: components[2])
    }

    /// 组织者覆盖了没有受邀嘉宾、因而没有参与者列表的事件。
    private static func accountEmail(of participant: EKParticipant?) -> String? {
        guard let participant else { return nil }
        return MeetingLink.accountAddress(
            of: participant.url, isCurrentUser: participant.isCurrentUser)
    }

    /// 按 id 在当前已加载的事件中查找。
    func event(id: String) -> MeetingEvent? {
        events.first { $0.id == id }
    }

    // MARK: - Details

    /// 加载指定会议的详情并发布。
    func loadDetails(of meeting: MeetingEvent) {
        let next = fetchDetails(of: meeting)
        if next != details { details = next }
    }

    /// 清空当前详情。
    func clearDetails() {
        if details != nil { details = nil }
    }

    /// 重新获取当前已展示会议的详情，会议已不存在时置空。
    private func refreshDetails() {
        guard let shown = details?.meetingID else { return }
        let next = event(id: shown).flatMap(fetchDetails(of:))
        if next != details { details = next }
    }

    /// 只查询该次实例所在的时间窗，使打开的页面每次重载仅付出一次极小查询。
    private func fetchDetails(of meeting: MeetingEvent) -> MeetingDetails? {
        guard let eventStore, let calendar = eventStore.calendar(withIdentifier: meeting.calendarID)
        else { return nil }
        // 两端各加一点余量，否则零长度事件会落在自己的窗口之外。
        let predicate = eventStore.predicateForEvents(
            withStart: meeting.start, end: meeting.end.addingTimeInterval(1), calendars: [calendar])
        let match = eventStore.events(matching: predicate).first { event in
            event.startDate.map { Self.occurrenceID(of: event, start: $0) } == meeting.id
        }
        guard let match else { return nil }
        return MeetingDetails(
            meetingID: meeting.id, location: match.location, notes: match.notes,
            attendees: Self.attendees(of: match))
    }

    /// 把事件的参与者转为详情用的 `Attendee`，无名字的跳过。
    private static func attendees(of event: EKEvent) -> [MeetingDetails.Attendee] {
        let organizer = event.organizer?.url
        return (event.attendees ?? []).compactMap { participant in
            guard let name = participant.name ?? MeetingLink.address(of: participant.url) else {
                return nil
            }
            return MeetingDetails.Attendee(
                name: name, response: response(to: participant.participantStatus),
                isOrganizer: participant.url == organizer)
        }
    }

    /// 把 EventKit 的参与者状态映射为详情用的回复状态。
    private static func response(
        to status: EKParticipantStatus
    ) -> MeetingDetails.Attendee.Response {
        switch status {
        case .accepted: .accepted
        case .tentative: .tentative
        case .declined: .declined
        default: .pending
        }
    }

    /// 返回 false 表示不存在可用日历，这是一次明确报告，而不是静默的无操作。
    func createEvent(_ draft: EventDraft, now: Date) -> Bool {
        let store = eventStore ?? EKEventStore()
        eventStore = store
        guard access == .granted, let calendar = store.defaultCalendarForNewEvents else {
            return false
        }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = draft.trimmedTitle
        event.startDate = draft.start(from: now)
        event.endDate = draft.end(from: now)
        guard (try? store.save(event, span: .thisEvent, commit: true)) != nil else { return false }
        reload()
        return true
    }

    // MARK: - Per-calendar switches

    /// 指定日历是否处于启用状态。
    func isEnabled(_ calendar: MeetingCalendar) -> Bool {
        !hiddenCalendarIDs.contains(calendar.id)
    }

    /// 开关指定日历：更新隐藏集合、持久化到 UserDefaults 并重载。
    func setEnabled(_ enabled: Bool, for calendar: MeetingCalendar) {
        if enabled {
            hiddenCalendarIDs.remove(calendar.id)
        } else {
            hiddenCalendarIDs.insert(calendar.id)
        }
        defaults.set(Array(hiddenCalendarIDs), forKey: hiddenKey)
        reload()
    }
}
