// 文件职责：单会议详情页的 PaletteScreen 适配，把详情页接入启动器的行选中、弹出菜单与快捷键体系。
// 分层：UI / Coordinator 桥接；页面只有一行，所有动作委托给 MeetingActionsMenu。
import SwiftUI

/// 单个会议的页面；↵、⌘↵、⌘O 与 ⌘K 的行为与其在日程行上完全一致。
struct MeetingDetailsScreen: PaletteScreen {
    let store: CalendarStore
    let core: AppCore

    /// 从 store.details 解析出对应会议；无详情或找不到事件时为 nil。
    private var meeting: MeetingEvent? {
        store.details.flatMap { store.event(id: $0.meetingID) }
    }

    /// 页面只有一行：该会议本身。
    var rows: [MeetingEvent] { meeting.map { [$0] } ?? [] }

    /// 主操作标题：无链接时为「在日历中打开」，否则为「加入会议」。
    var primaryActionTitle: String {
        core.settings.text(
            meeting?.link == nil ? CalendarKey.actionOpenInCalendar : CalendarKey.actionJoinMeeting)
    }

    /// 该会议的弹出菜单内容（不提供「显示详情」）。
    func actions(at selection: Int) -> PopoverMenuContent? {
        meeting.map { MeetingActionsMenu.content(meeting: $0, core: core, offersDetails: false) }
    }

    /// 选中行时执行加入。
    func activate(at selection: Int) {
        guard let meeting else { return }
        core.calendarCoordinator.join(meeting)
    }

    /// ⌘↵ 快捷键：复制会议链接。
    func secondary(at selection: Int) -> Bool {
        guard let meeting else { return false }
        return MeetingActionsMenu.secondary(meeting: meeting, core: core)
    }

    /// 按快捷键执行对应动作（不提供「显示详情」）。
    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        guard let meeting else { return false }
        return MeetingActionsMenu.perform(shortcut, meeting: meeting, core: core, offersDetails: false)
    }

    /// 页面主体：详情缺失时显示空结果提示，否则渲染详情视图。
    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        guard let details = store.details, let meeting = store.event(id: details.meetingID) else {
            return AnyView(
                EmptyResults(text: core.settings.text(CalendarKey.emptyMeetingGone)))
        }
        return AnyView(MeetingDetailsView(meeting: meeting, details: details))
    }
}
