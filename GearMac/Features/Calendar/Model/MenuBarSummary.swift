// 文件职责：决定菜单栏显示哪一场会议及其显示时长：根据提前量、链接限制与隐藏规则从议程中挑出单个事件。
// 分层：Model；纯值类型 Sendable，不 import AppKit/SwiftUI，时间均以注入的 `now` 为准。
import Foundation

/// 菜单栏显示哪个事件以及持续多久。每次读取时钟都使用注入的 `now`。
struct MenuBarSummary: Sendable {
    /// 为 nil 表示把下一场事件保持可见直到今天结束。
    let leadMinutes: Int?
    /// 仅考虑 GearMac 真正可加入的事件；其余的只是日程，不是会议。
    let linkedOnly: Bool
    private let hideCurrentAtStart: Bool
    private let hideAfterMinutes: Int?
    private let calendar: Calendar

    /// 足够长到能认清一场会议，又足够短到不占据菜单栏。
    static let titleCap = 24
    /// 凌晨的会议在即将开始时才有用，不应把当天的菜单栏占满数小时。
    static let nextDayGrace: TimeInterval = 30 * 60

    /// 构造摘要配置；所有参数均有合理默认值。
    init(
        leadMinutes: Int?, hideAfterMinutes: Int? = nil, linkedOnly: Bool,
        hideCurrentAtStart: Bool = false,
        calendar: Calendar = .current
    ) {
        self.leadMinutes = leadMinutes
        self.linkedOnly = linkedOnly
        self.hideCurrentAtStart = hideCurrentAtStart
        self.hideAfterMinutes = hideAfterMinutes
        self.calendar = calendar
    }

    /// 选取窗口内最早且未被忽略的事件，使一项隐藏后自然交接给下一项。
    func event(
        from events: [MeetingEvent], now: Date, dismissed: Set<MeetingEvent.ID> = []
    ) -> MeetingEvent? {
        UpcomingWindow.agenda(from: events, now: now).first {
            !dismissed.contains($0.id) && (!linkedOnly || $0.link != nil)
                && isInsideLead(for: $0, now: now) && now < hidesAt($0)
        }
    }

    /// 空标签与菜单栏选择共用同一套「即将到来」定义。
    static func hasUpcomingEvent(
        from events: [MeetingEvent], now: Date, calendar: Calendar = .current
    ) -> Bool {
        UpcomingWindow.agenda(from: events, now: now).contains {
            calendar.isDate($0.start, inSameDayAs: now) || $0.start <= now + nextDayGrace
        }
    }

    /// 有意不按词边界截断：硬性长度上限是约束菜单栏的唯一手段。
    static func title(_ title: String) -> String {
        guard title.count > titleCap else { return title }
        return title.prefix(titleCap - 1).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// 事件是否已进入提前展示窗口。
    private func isInsideLead(for event: MeetingEvent, now: Date) -> Bool {
        guard let leadMinutes else {
            return Self.hasUpcomingEvent(from: [event], now: now, calendar: calendar)
        }
        return now >= event.start - TimeInterval(leadMinutes * 60)
    }

    /// 该事件应当从菜单栏隐藏的时刻。
    private func hidesAt(_ event: MeetingEvent) -> Date {
        if hideCurrentAtStart { return event.start }
        guard let hideAfterMinutes else { return event.end }
        return min(event.start + TimeInterval(hideAfterMinutes * 60), event.end)
    }
}
