// 文件职责：My Schedule 日程页，实现 PaletteScreen：按查询词过滤会议、渲染日程列表并提供行动作与快捷键。
// 分层：UI / Coordinator 桥接；行的取用与动作委托给 MeetingActionsMenu 与 CalendarCoordinator。
import SwiftUI

/// My Schedule 页面：按查询词过滤 store 时间跨度内的事件。回车加入，⌘K 承载其余动作。
struct ScheduleScreen: PaletteScreen {
    let store: CalendarStore
    let clock: MeetingClock
    let core: AppCore
    let vm: PaletteState
    let openActions: () -> Void

    /// 依据查询词过滤后的议程行；查询为空时返回全部议程。
    var rows: [MeetingEvent] {
        let query = vm.query.trimmingCharacters(in: .whitespaces)
        let agenda = UpcomingWindow.agenda(from: store.events, now: clock.now)
        guard !query.isEmpty else { return agenda }
        return agenda.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.calendarName.localizedCaseInsensitiveContains(query)
        }
    }

    /// 无链接的会议无从加入，因此主操作改为它能提供的动作。
    var primaryActionTitle: String {
        core.settings.text(
            meeting(at: vm.selection)?.link == nil
                ? CalendarKey.actionOpenInCalendar : CalendarKey.actionJoinMeeting)
    }

    /// 按选中下标取出会议；越界时返回 nil。
    private func meeting(at selection: Int) -> MeetingEvent? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    /// 该会议的弹出菜单内容。
    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let meeting = meeting(at: selection) else { return nil }
        return MeetingActionsMenu.content(meeting: meeting, core: core)
    }

    /// 选中行时加入会议（无链接则交给系统日历）。
    func activate(at selection: Int) {
        guard let meeting = meeting(at: selection) else { return }
        core.calendarCoordinator.activateMeeting(id: meeting.id)
    }

    /// ⌘↵：复制链接，用于「链接是什么」的场景，而不是直接发起通话。
    func secondary(at selection: Int) -> Bool {
        guard let meeting = meeting(at: selection) else { return false }
        return MeetingActionsMenu.secondary(meeting: meeting, core: core)
    }

    /// 按快捷键执行对应动作。
    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        guard let meeting = meeting(at: selection) else { return false }
        return MeetingActionsMenu.perform(shortcut, meeting: meeting, core: core)
    }

    /// 页面主体，委托给 content。
    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    /// 列表为空时显示空态文案，否则渲染日程列表。
    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        if rows.isEmpty {
            EmptyResults(text: emptyMessage)
        } else {
            ScheduleList(
                results: rows,
                selectedID: meeting(at: selection)?.id,
                now: clock.now,
                scroll: scroll,
                onActivate: { activate(at: rows.firstIndex(of: $0) ?? selection) },
                onActions: { meeting in
                    if let index = rows.firstIndex(of: meeting) { vm.selection = index }
                    openActions()
                }
            )
        }
    }

    /// 说明列表为空的原因：无权限与「下午没有安排」的提示含义完全不同。
    private var emptyMessage: String {
        if store.access != .granted { return core.settings.text(CalendarKey.emptyNoAccess) }
        if !vm.query.trimmingCharacters(in: .whitespaces).isEmpty {
            return core.settings.text(CalendarKey.emptyNoMatches)
        }
        return String(
            format: core.settings.text(CalendarKey.emptyNothingScheduledFormat),
            store.span.localizedOrPhrase(core.settings.language))
    }
}
