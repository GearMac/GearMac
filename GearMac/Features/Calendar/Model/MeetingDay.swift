// 文件职责：把会议归到“从今天起算第几天”的日期分组，并提供分组的标题文案与按日聚合逻辑。
// 分层：Model；纯值类型 Sendable，不 import AppKit/SwiftUI，时间计算依赖传入的 Calendar。
import Foundation

/// 会议所属的日期，以今天为基准计数，使「My Schedule」与菜单栏给出相同的日期标题。
struct MeetingDay: Hashable, Sendable {
    /// 当天零点。
    let start: Date
    /// 距今天的天数（整天）；跨午夜仍在进行的会议算作今天。
    let offset: Int

    /// 根据日期、当前时间与日历计算日期及其相对今天的偏移。
    init(for date: Date, now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        offset = max(0, calendar.dateComponents([.day], from: today, to: day).day ?? 0)
        start = offset == 0 ? today : day
    }

    /// 该日期的分组标题（英文）：今天/明天带日期，其余显示星期几。
    func title(calendar: Calendar) -> String {
        let date = calendar.formatStyle.month(.abbreviated).day()
        switch offset {
        case 0: return "Today, \(start.formatted(date))"
        case 1: return "Tomorrow, \(start.formatted(date))"
        default: return start.formatted(date.weekday(.wide))
        }
    }

    /// 按界面语言给出的分组标题：今天/明天带日期，其余沿用日期格式化。
    func localizedTitle(calendar: Calendar, language: AppLanguage) -> String {
        let date = start.formatted(calendar.formatStyle.month(.abbreviated).day())
        switch offset {
        case 0:
            return String(
                format: L10n.string(CalendarKey.dayTodayFormat, language: language), date)
        case 1:
            return String(
                format: L10n.string(CalendarKey.dayTomorrowFormat, language: language), date)
        default:
            return title(calendar: calendar)
        }
    }
}

/// 同一天的会议（按开始时间排序）：一个标题及其下方的行。
struct MeetingDayGroup: Identifiable, Sendable {
    let day: MeetingDay
    private(set) var meetings: [MeetingEvent]

    /// 以 `MeetingDay` 作为分组标识。
    var id: MeetingDay { day }

    /// `agenda` 已按开始时间排序，因此日期变化处就是新分组的起点。
    static func grouping(
        _ agenda: [MeetingEvent], now: Date, calendar: Calendar
    ) -> [MeetingDayGroup] {
        var groups: [MeetingDayGroup] = []
        for meeting in agenda {
            let day = MeetingDay(for: meeting.start, now: now, calendar: calendar)
            if groups.last?.day == day {
                groups[groups.count - 1].meetings.append(meeting)
            } else {
                groups.append(MeetingDayGroup(day: day, meetings: [meeting]))
            }
        }
        return groups
    }
}

extension Calendar {
    /// 使用该日历自身的地区与时区，使测试日历的格式化结果与用户环境一致。
    var formatStyle: Date.FormatStyle {
        Date.FormatStyle(
            locale: locale ?? Locale(identifier: "en_US"), calendar: self, timeZone: timeZone)
    }
}
